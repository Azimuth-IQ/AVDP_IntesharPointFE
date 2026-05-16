import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/pos/presentation/printer_picker_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

class PosHomePage extends ConsumerStatefulWidget {
  const PosHomePage({super.key});

  @override
  ConsumerState<PosHomePage> createState() => _PosHomePageState();
}

class _PosHomePageState extends ConsumerState<PosHomePage> {
  List<Product>? _products;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authStateProvider).valueOrNull;
      if (auth is! AuthAuthenticated) throw Exception('Not authenticated');

      final api = ref.read(apiClientProvider);
      final repo = ProductRepository(api);
      final all = await repo.readByEntity(auth.entity.id);
      // POS only shows AVAILABLE products
      final available = all.where((p) => p.status == ProductStatus.AVAILABLE).toList();
      if (mounted) setState(() => _products = available);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Groups available products by SKU for display.
  Map<String, List<Product>> _groupBySku(List<Product> products) {
    final map = <String, List<Product>>{};
    for (final p in products) {
      map.putIfAbsent(p.productDefinition.sku, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.posHome),
        actions: [
          Consumer(
            builder: (ctx, ref, _) {
              final ps = ref.watch(bluetoothServiceProvider);
              final isConnected = ps.status == PrinterStatus.connected;
              return IconButton(
                icon: Icon(isConnected ? Icons.print : Icons.print_outlined, color: isConnected ? Colors.green : null),
                tooltip: isConnected ? 'Printer: ${ps.deviceName}' : 'Setup Printer',
                onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : _buildGrid(l),
    );
  }

  Widget _buildGrid(AppLocalizations l) {
    final products = _products ?? [];
    final groups = _groupBySku(products);

    if (groups.isEmpty) {
      return EmptyState(message: 'No available products in inventory', actionLabel: 'Refresh', onAction: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.85),
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final sku = groups.keys.elementAt(i);
          final items = groups[sku]!;
          return _SkuCard(sku: sku, products: items, onTap: () => _showVoucher(items.first));
        },
      ),
    );
  }

  void _showVoucher(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VoucherSheet(
        product: product,
        onPrinted: () {
          Navigator.pop(ctx);
          _markPrinted(product);
        },
      ),
    );
  }

  Future<void> _markPrinted(Product product) async {
    try {
      final api = ref.read(apiClientProvider);
      final repo = ProductRepository(api);
      await repo.update(product.copyWith(status: ProductStatus.PRINTED));
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update status: $e')));
      }
    }
  }
}

class _SkuCard extends StatelessWidget {
  final String sku;
  final List<Product> products;
  final VoidCallback onTap;

  const _SkuCard({required this.sku, required this.products, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final def = products.first.productDefinition;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  sku.length > 3 ? sku.substring(0, 3) : sku,
                  style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                def.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                Formatters.iqd(def.defaultPrice),
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Text(l.posAvailable(products.length), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSecondaryContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoucherSheet extends ConsumerStatefulWidget {
  final Product product;
  final VoidCallback onPrinted;

  const _VoucherSheet({required this.product, required this.onPrinted});

  @override
  ConsumerState<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends ConsumerState<_VoucherSheet> {
  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
      final bytes = await buildVoucherReceipt(
        companyName: 'Inteshar Point',
        shopName: auth?.entity.meta.name ?? 'Store',
        posLabel: 'Counter 1',
        operatorPhone: auth?.entity.users.firstOrNull?.phone ?? '',
        denomination: '${widget.product.productDefinition.name} ${Formatters.iqd(widget.product.productDefinition.defaultPrice)}',
        serial: widget.product.serialNumber,
        pin: widget.product.pin,
        timestamp: DateTime.now(),
      );
      await ref.read(bluetoothServiceProvider.notifier).send(bytes);
      if (mounted) widget.onPrinted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e'), backgroundColor: Theme.of(context).colorScheme.error));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final p = widget.product;
    final def = p.productDefinition;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text(def.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          Text(
            Formatters.iqd(def.defaultPrice),
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l.posSerial, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                    SelectableText(
                      p.serialNumber,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l.posPin, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                    SelectableText(
                      p.pin,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 4, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Consumer(
            builder: (ctx, ref, _) {
              final ps = ref.watch(bluetoothServiceProvider);
              final isConnected = ps.status == PrinterStatus.connected;
              return Column(
                children: [
                  if (!isConnected)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                      icon: const Icon(Icons.bluetooth),
                      label: Text(l.posConnectPrinter),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bluetooth_connected, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Text(ps.deviceName ?? l.posPrinterConnected, style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_printing || !isConnected) ? null : _print,
                          icon: _printing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print),
                          label: Text(_printing ? 'Printing…' : l.posPrintVoucher),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
