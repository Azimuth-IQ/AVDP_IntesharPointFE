import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

class InventoryPage extends ConsumerStatefulWidget {
  const InventoryPage({super.key});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  List<Product>? _products;
  Object? _error;
  bool _loading = true;
  String _search = '';
  ProductStatus? _statusFilter;

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
      String? entityId;
      if (auth is AuthAuthenticated) {
        entityId = auth.entity.id;
      } else {
        entityId = await sessionStorage.getCurrentEntityId();
      }
      if (entityId == null) throw Exception('No entity id in session');

      final api = ref.read(apiClientProvider);
      final repo = ProductRepository(api);
      final products = await repo.readByEntity(entityId);
      if (mounted) setState(() => _products = products);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Product> get _filtered {
    final all = _products ?? [];
    return all.where((p) {
      final matchSearch = _search.isEmpty ||
          p.productDefinition.name
              .toLowerCase()
              .contains(_search.toLowerCase()) ||
          p.productDefinition.sku
              .toLowerCase()
              .contains(_search.toLowerCase()) ||
          p.serialNumber.toLowerCase().contains(_search.toLowerCase());
      final matchStatus =
          _statusFilter == null || p.status == _statusFilter;
      return matchSearch && matchStatus;
    }).toList();
  }

  /// Groups products by SKU and returns a map.
  Map<String, List<Product>> _groupBySku(List<Product> products) {
    final map = <String, List<Product>>{};
    for (final p in products) {
      final sku = p.productDefinition.sku;
      map.putIfAbsent(sku, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final filtered = _filtered;
    final groups = _groupBySku(filtered);

    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name, SKU, serial…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<ProductStatus?>(
                value: _statusFilter,
                hint: const Text('All'),
                isDense: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('All')),
                  ...ProductStatus.values.map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.name),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _statusFilter = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: groups.isEmpty
              ? EmptyState(
                  message: 'No products in your inventory',
                  actionLabel: 'Refresh',
                  onAction: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: groups.length,
                    itemBuilder: (context, i) {
                      final sku = groups.keys.elementAt(i);
                      final items = groups[sku]!;
                      final available = items
                          .where((p) => p.status == ProductStatus.AVAILABLE)
                          .length;
                      final printed = items
                          .where((p) => p.status == ProductStatus.PRINTED)
                          .length;
                      final damaged = items
                          .where((p) => p.status == ProductStatus.DAMAGED)
                          .length;

                      return Card(
                        child: ExpansionTile(
                          title: Text(
                            items.first.productDefinition.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'SKU: $sku  •  ${Formatters.iqd(items.first.productDefinition.defaultPrice)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _StatusBadge(
                                  count: available,
                                  status: ProductStatus.AVAILABLE),
                              const SizedBox(width: 4),
                              _StatusBadge(
                                  count: printed,
                                  status: ProductStatus.PRINTED),
                              if (damaged > 0) ...[
                                const SizedBox(width: 4),
                                _StatusBadge(
                                    count: damaged,
                                    status: ProductStatus.DAMAGED),
                              ],
                            ],
                          ),
                          children: items
                              .map((p) => _ProductTile(
                                    product: p,
                                    onStatusChanged: _load,
                                  ))
                              .toList(),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final int count;
  final ProductStatus status;

  const _StatusBadge({required this.count, required this.status});

  Color _color(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      ProductStatus.AVAILABLE => cs.primaryContainer,
      ProductStatus.PRINTED => cs.secondaryContainer,
      ProductStatus.DAMAGED => cs.errorContainer,
    };
  }

  Color _fg(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      ProductStatus.AVAILABLE => cs.onPrimaryContainer,
      ProductStatus.PRINTED => cs.onSecondaryContainer,
      ProductStatus.DAMAGED => cs.onErrorContainer,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: _fg(context),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  final Product product;
  final VoidCallback onStatusChanged;

  const _ProductTile({
    required this.product,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      leading: _statusIcon(product.status),
      title: Text(
        'SN: ${product.serialNumber}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      subtitle: Text('PIN: ${product.pin}'),
      trailing: PopupMenuButton<ProductStatus>(
        onSelected: (s) => _updateStatus(context, ref, s),
        itemBuilder: (_) => ProductStatus.values
            .where((s) => s != product.status)
            .map((s) =>
                PopupMenuItem(value: s, child: Text('Mark ${s.name}')))
            .toList(),
        child: const Icon(Icons.more_vert, size: 18),
      ),
    );
  }

  Widget _statusIcon(ProductStatus s) {
    return switch (s) {
      ProductStatus.AVAILABLE =>
        const Icon(Icons.check_circle, color: Colors.green),
      ProductStatus.PRINTED => const Icon(Icons.print, color: Colors.blue),
      ProductStatus.DAMAGED => const Icon(Icons.warning, color: Colors.red),
    };
  }

  Future<void> _updateStatus(
      BuildContext context, WidgetRef ref, ProductStatus newStatus) async {
    try {
      final api = ref.read(apiClientProvider);
      final repo = ProductRepository(api);
      await repo.update(product.copyWith(status: newStatus));
      onStatusChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }
}
