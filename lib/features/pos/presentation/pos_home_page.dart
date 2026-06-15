import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/pos/presentation/printer_picker_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

class PosHomePage extends ConsumerStatefulWidget {
  const PosHomePage({super.key});

  @override
  ConsumerState<PosHomePage> createState() => _PosHomePageState();
}

class _PosHomePageState extends ConsumerState<PosHomePage> {
  List<Product>? _products;
  Object? _error;
  bool _loading = true;
  String _search = '';

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
      // Sellable / retryable = anything not already PRINTED or DAMAGED
      // (AVAILABLE, in-flight SENT_FOR_PRINTING, and FAILED_PRINTING).
      final available = all.where((p) => p.status != ProductStatus.PRINTED && p.status != ProductStatus.DAMAGED).toList();
      if (mounted) setState(() => _products = available);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onLongPress: () => context.go('/diagnostics'),
          child: Row(
            children: [
              IntesharStar(size: 22, color: cs.onSurface),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.posHome,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      letterSpacing: -0.3,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.posHomeLiveCounter,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Consumer(
            builder: (ctx, ref, _) {
              final ps = ref.watch(bluetoothServiceProvider);
              final isConnected = ps.status == PrinterStatus.connected;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.push<void>(
                      ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                          size: 16,
                          color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isConnected ? (ps.deviceName ?? l.posPrinterConnected) : l.posHomeSetupPrinter,
                          style: TextStyle(
                            fontFamily: 'CodecPro',
                            fontSize: 12,
                            color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_outlined),
            tooltip: l.signOut,
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
    final cs = Theme.of(context).colorScheme;
    final products = _products ?? [];
    final filtered = _search.isEmpty
        ? products
        : products.where((p) {
            final q = _search.toLowerCase();
            return p.productDefinition.name.toLowerCase().contains(q) ||
                p.productDefinition.sku.toLowerCase().contains(q);
          }).toList();
    final groups = _groupBySku(filtered);

    final tileExtent = switch (context.screenSize) {
      ScreenSize.desktop => 260.0,
      ScreenSize.tablet => 220.0,
      ScreenSize.mobile => 168.0,
    };

    return MaxWidthBox(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.posHomePickDenomination,
                        style: IntesharType.display(28, color: cs.onSurface, w: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.posHomeCounterSubtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _StockTally(stock: products.length),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: TextField(
              decoration: InputDecoration(
                hintText: l.posHomeSearchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (groups.isEmpty)
            Expanded(
              child: EmptyState(
                message: products.isEmpty
                    ? l.posHomeNoVouchers
                    : l.posHomeNoMatches(_search),
                actionLabel: l.retryButton,
                onAction: _load,
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: tileExtent,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final sku = groups.keys.elementAt(i);
                    final items = groups[sku]!;
                    return _SkuTile(
                      sku: sku,
                      products: items,
                      onTap: () => _showVoucher(items.first),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showVoucher(Product product) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VoucherSheet(
        product: product,
        // The sheet resolves the voucher's print status itself (confirmPrint);
        // here we just close and refresh the list.
        onPrinted: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }
}

class _StockTally extends StatelessWidget {
  final int stock;
  const _StockTally({required this.stock});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: IntesharColors.saffron,
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        boxShadow: IntesharShadows.ctaShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            l.posHomeInStock,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 10,
              color: IntesharColors.ink.withValues(alpha: 0.65),
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stock.toString(),
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 28,
              color: IntesharColors.ink,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── SKU tile ────────────────────────────────────────────────────────────────

class _SkuTile extends StatefulWidget {
  final String sku;
  final List<Product> products;
  final VoidCallback onTap;
  const _SkuTile({required this.sku, required this.products, required this.onTap});

  @override
  State<_SkuTile> createState() => _SkuTileState();
}

class _SkuTileState extends State<_SkuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final def = widget.products.first.productDefinition;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: PressableScale(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: BorderRadius.circular(IntesharRadii.lg),
            boxShadow: _hover ? IntesharShadows.elev2 : IntesharShadows.elev1,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(IntesharRadii.lg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: IntesharColors.saffron,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          widget.sku,
                          style: IntesharType.mono(13, color: IntesharColors.ink, w: FontWeight.w900, letterSpacing: 0.6),
                        ),
                      ),
                      const Spacer(),
                      StampPill(label: '× ${widget.products.length}', color: IntesharColors.sage),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    def.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      color: cs.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Formatters.iqd(def.defaultPrice),
                    style: IntesharType.mono(15, color: cs.onSurface, w: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  BrandCTAButton(
                    label: l.posHomePrint,
                    leading: Icons.print_outlined,
                    onPressed: widget.onTap,
                    height: 38,
                    fontSize: 12.5,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Voucher sheet ───────────────────────────────────────────────────────────

class _VoucherSheet extends ConsumerStatefulWidget {
  final Product product;
  final VoidCallback onPrinted;

  const _VoucherSheet({required this.product, required this.onPrinted});

  @override
  ConsumerState<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends ConsumerState<_VoucherSheet> {
  bool _printing = false;
  // The list product arrives with its PIN stripped (encrypted at rest). Opening
  // the sheet "sends for printing": the backend flips the voucher to
  // SENT_FOR_PRINTING and returns the decrypted code — the only channel that
  // ever exposes a working PIN.
  Product? _sent;
  Object? _sendError;
  bool _sending = true;

  @override
  void initState() {
    super.initState();
    _sendForPrinting();
  }

  Future<void> _sendForPrinting() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final repo = ProductRepository(api);
      final full = await repo.sendForPrinting(widget.product.id);
      if (mounted) setState(() => _sent = full);
    } catch (e) {
      if (mounted) setState(() => _sendError = e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // Resolve the in-flight voucher: PRINTED on success, FAILED_PRINTING otherwise.
  // Best-effort — the status reconciles on the next inventory load if it fails.
  Future<void> _confirm(bool printed) async {
    try {
      final api = ref.read(apiClientProvider);
      await ProductRepository(api).confirmPrint(widget.product.id, printed: printed);
    } catch (_) {}
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      final auth = ref.read(authStateProvider).valueOrNull as AuthAuthenticated?;
      final src = _sent ?? widget.product;
      final def = src.productDefinition;
      final bytes = await buildVoucherReceipt(
        template: def.template,
        companyName: 'Inteshar Point',
        shopName: auth?.entity.meta.name ?? 'Store',
        posLabel: 'Counter 1',
        operatorPhone: auth?.entity.users.firstOrNull?.phone ?? '',
        productName: def.name,
        price: Formatters.iqd(def.defaultPrice),
        serial: src.serialNumber,
        pin: src.pin,
        timestamp: DateTime.now(),
      );
      await ref.read(bluetoothServiceProvider.notifier).send(bytes);
      await _confirm(true); // → PRINTED
      if (mounted) widget.onPrinted();
    } catch (e) {
      await _confirm(false); // → FAILED_PRINTING (stays sellable for retry)
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.posHomePrintFailed(e.toString())), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // Closing without printing: the code was revealed but not printed → mark
  // FAILED_PRINTING so the voucher stays sellable for a later retry.
  Future<void> _cancel() async {
    if (_sent != null) await _confirm(false);
    if (mounted) widget.onPrinted();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    if (_sending) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 56),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_sendError != null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorState(error: _sendError!, onRetry: _sendForPrinting),
        ),
      );
    }
    final p = _sent!;
    final def = p.productDefinition;
    final t = def.template;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24,
          right: 24,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            // Receipt preview tile
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(IntesharRadii.lg),
                  boxShadow: IntesharShadows.elev2,
                ),
                child: Column(
                  children: [
                    IntesharStar(size: 36, color: cs.onSurface),
                    const SizedBox(height: 10),
                    Text(
                      t.headerText.trim().isNotEmpty
                          ? t.headerText.trim().toUpperCase()
                          : 'INTESHAR STORE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        fontSize: 12,
                        color: cs.onSurface,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (t.showProductName) ...[
                      const SizedBox(height: 16),
                      Text(
                        def.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'CodecPro',
                          fontSize: 22,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                    if (t.showPrice) ...[
                      const SizedBox(height: 4),
                      Text(
                        Formatters.iqd(def.defaultPrice),
                        style: IntesharType.mono(17, color: IntesharColors.saffronDeep, w: FontWeight.w800),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const _ReceiptDivider(),
                    const SizedBox(height: 14),
                    if (t.showSerial) ...[
                      _ReceiptRow(label: l.posSerial, value: p.serialNumber, monoSize: 13),
                      const SizedBox(height: 12),
                    ],
                    if (t.showPin)
                      _ReceiptRow(label: l.posPin, value: p.pin, monoSize: 20, monoSpacing: 5),
                    if (t.qrEnabled) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(IntesharRadii.sm),
                        ),
                        child: QrImageView(
                          data: t.qrPayload(pin: p.pin, serial: p.serialNumber),
                          version: QrVersions.auto,
                          size: 128,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: IntesharColors.ink,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: IntesharColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.redeemInstructions.trim().isNotEmpty
                            ? t.redeemInstructions.trim()
                            : t.qrPayload(pin: p.pin, serial: p.serialNumber),
                        textAlign: TextAlign.center,
                        style: IntesharType.mono(12, color: cs.onSurface, w: FontWeight.w700),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const _ReceiptDivider(),
                    const SizedBox(height: 14),
                    Text(
                      t.footerText.trim().isNotEmpty
                          ? t.footerText.trim()
                          : l.posHomeScratchNote,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Consumer(
              builder: (ctx, ref, _) {
                final ps = ref.watch(bluetoothServiceProvider);
                final isConnected = ps.status == PrinterStatus.connected;
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? IntesharColors.sage.withValues(alpha: 0.10)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isConnected ? IntesharColors.sage.withValues(alpha: 0.4) : cs.outline,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                            size: 14,
                            color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isConnected
                                ? (ps.deviceName ?? l.posPrinterConnected)
                                : l.posHomePrinterNotConnected,
                            style: TextStyle(
                              fontFamily: 'CodecPro',
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isConnected ? IntesharColors.sage : cs.onSurfaceVariant,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!isConnected)
                      BrandCTAButton(
                        label: l.posConnectPrinter,
                        leading: Icons.bluetooth,
                        variant: BrandCTAVariant.outline,
                        onPressed: () => Navigator.push<void>(
                            ctx, MaterialPageRoute(builder: (_) => const PrinterPickerPage())),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: BrandCTAButton(
                            label: l.posHomeCancel,
                            variant: BrandCTAVariant.outline,
                            onPressed: _printing ? null : () => _cancel(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: BrandCTAButton(
                            label: _printing ? l.posHomePrinting : l.posPrintVoucher,
                            leading: _printing ? null : Icons.print_outlined,
                            loading: _printing,
                            onPressed: (_printing || !isConnected) ? null : _print,
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
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final double monoSize;
  final double monoSpacing;
  const _ReceiptRow({required this.label, required this.value, this.monoSize = 13, this.monoSpacing = 0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'CodecPro',
            color: cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        SelectableText(
          value,
          style: IntesharType.mono(monoSize, color: cs.onSurface, w: FontWeight.w800, letterSpacing: monoSpacing),
        ),
      ],
    );
  }
}

class _ReceiptDivider extends StatelessWidget {
  const _ReceiptDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedLinePainter(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 3.0;
    const gap = 3.0;
    final paint = Paint()..color = color..strokeWidth = 1;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
