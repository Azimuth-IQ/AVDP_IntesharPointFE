import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/agents/data/agent_repository.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

class InventoryPage extends ConsumerStatefulWidget {
  /// When set, browses this entity's inventory instead of the signed-in
  /// entity's — used for read-only drill-in to a child's stock.
  final String? entityId;

  /// Hides all mutating controls (per-product status changes).
  final bool readOnly;

  const InventoryPage({super.key, this.entityId, this.readOnly = false});

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  List<SkuSummary>? _summary;
  Object? _error;
  bool _loading = true;
  String _search = '';
  ProductStatus? _statusFilter;
  String? _entityId;

  // HQ-only "view a Main Agent's inventory" picker. Conceptually only Main Agents
  // hold stock, so HQ can inspect its own holding or any AGENT1 pool. Only shown on
  // HQ's own inventory screen (widget.entityId == null), not the read-only drill-in.
  bool _isHqRoot = false;
  String? _selfId; // signed-in HQ entity id (the default "HQ holding" option)
  String? _selectedId; // chosen entity to view (null => self)
  List<EntitySummaryRow> _mainAgents = [];

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
      _selfId = (auth is AuthAuthenticated)
          ? auth.entity.id
          : await sessionStorage.getCurrentEntityId();
      _isHqRoot = widget.entityId == null &&
          auth is AuthAuthenticated &&
          auth.entity.type == EntityType.INTESHAR;
      if (_isHqRoot && _mainAgents.isEmpty) {
        try {
          _mainAgents =
              await AgentRepository(ref.read(apiClientProvider)).listAll('AGENT1');
        } catch (_) {
          // Picker degrades to HQ-only if the Main-Agent list can't be loaded.
        }
      }
      // Drill-in id wins; else the HQ-picked agent; else the signed-in entity.
      final entityId = widget.entityId ?? _selectedId ?? _selfId;
      if (entityId == null) throw Exception('No entity id in session');
      _entityId = entityId;
      final repo = ProductRepository(ref.read(apiClientProvider));
      // One indexed aggregation — no longer downloads every voucher document.
      final summary = await repo.summaryByEntity(entityId);
      if (mounted) setState(() => _summary = summary);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _statusCount(SkuSummary s, ProductStatus status) => switch (status) {
        ProductStatus.AVAILABLE => s.available,
        ProductStatus.PRINTED => s.printed,
        ProductStatus.DAMAGED => s.damaged,
        ProductStatus.SENT_FOR_PRINTING => s.sentForPrinting,
        ProductStatus.FAILED_PRINTING => s.failedPrinting,
      };

  /// Low-stock threshold applied per (SKU × governorate) bucket — the viewer's
  /// per-account threshold (default 50 when unavailable).
  int _lowStockThreshold() {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is AuthAuthenticated) return auth.entity.meta.effectiveLowStockThreshold;
    return 50;
  }

  List<SkuSummary> get _filtered {
    final all = _summary ?? [];
    final q = _search.toLowerCase();
    return all.where((s) {
      final matchSearch = _search.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.sku.toLowerCase().contains(q);
      final matchStatus = _statusFilter == null || _statusCount(s, _statusFilter!) > 0;
      return matchSearch && matchStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final all = _summary ?? [];
    final filtered = _filtered;
    final lowStock = _lowStockThreshold();

    final availableTotal = all.fold(0, (s, e) => s + e.available);
    final printedTotal = all.fold(0, (s, e) => s + e.printed);
    final damagedTotal = all.fold(0, (s, e) => s + e.damaged);
    final value = all.fold<num>(0, (s, e) => s + e.availableValue);

    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: l.inventoryEyebrow,
            title: l.navInventory,
            subtitle: l.inventorySubtitle,
            trailing: _Tallies(
              available: availableTotal,
              printed: printedTotal,
              damaged: damagedTotal,
            ),
          ),
          if (_isHqRoot)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: _InventoryOwnerPicker(
                selfId: _selfId!,
                agents: _mainAgents,
                selectedId: _entityId!,
                onChanged: (id) {
                  setState(() => _selectedId = id);
                  _load();
                },
              ),
            ),
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
              child: _InventoryValueCard(
                value: value,
                availableUnits: availableTotal,
                skuCount: all.length,
              ),
            ),
          _FilterBar(
            search: _search,
            statusFilter: _statusFilter,
            onSearchChanged: (v) => setState(() => _search = v),
            onStatusChanged: (v) => setState(() => _statusFilter = v),
          ),
          Expanded(
            child: filtered.isEmpty
                ? EmptyState(
                    message: all.isEmpty
                        ? l.inventoryEmptyFirst
                        : l.inventoryEmptyFiltered,
                    actionLabel: all.isEmpty ? l.inventoryRefresh : null,
                    onAction: all.isEmpty ? _load : null,
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final s = filtered[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _SkuGroupCard(
                            key: ValueKey(s.sku),
                            summary: s,
                            entityId: _entityId!,
                            readOnly: widget.readOnly,
                            lowStock: lowStock,
                            onChanged: _load,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── HQ "view whose inventory" picker ──────────────────────────────────────────
// Lets HQ choose which Main Agent's stock to inspect (or its own holding). Stock
// conceptually lives with the Main Agents, so this is the HQ's window into each pool.
class _InventoryOwnerPicker extends StatelessWidget {
  final String selfId;
  final List<EntitySummaryRow> agents;
  final String selectedId;
  final ValueChanged<String> onChanged;
  const _InventoryOwnerPicker({
    required this.selfId,
    required this.agents,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: selfId,
        child: Text(ar ? 'إنتشار (المقر الرئيسي)' : 'Inteshar (HQ)'),
      ),
      ...agents.map((a) => DropdownMenuItem(
            value: a.id,
            child: Text('${a.label} · ${a.productsCount}',
                overflow: TextOverflow.ellipsis),
          )),
    ];
    // The selected id must exist among the items or the dropdown asserts.
    final value = items.any((i) => i.value == selectedId) ? selectedId : selfId;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: ar ? 'عرض مخزون' : 'Viewing inventory of',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: const Icon(Icons.warehouse_outlined, size: 20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: items,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ── Inventory value card ──────────────────────────────────────────────────────

class _InventoryValueCard extends StatelessWidget {
  final num value;
  final int availableUnits;
  final int skuCount;
  const _InventoryValueCard({
    required this.value,
    required this.availableUnits,
    required this.skuCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.tones.brand.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(IntesharRadii.md),
            ),
            child: Icon(Icons.savings_outlined, size: 22, color: context.tones.brandInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.inventoryValueLabel,
                  style: IntesharType.sans(12, color: IntesharColors.inkSoft, w: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.iqd(value.round()),
                  style: IntesharType.display(24, color: cs.onSurface, w: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.money(availableUnits),
                style: IntesharType.display(20, color: cs.onSurface, w: FontWeight.w800),
              ),
              Text(
                l.inventoryValueUnits,
                style: IntesharType.sans(11, color: IntesharColors.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Tallies ───────────────────────────────────────────────────────────────────

class _Tallies extends StatelessWidget {
  final int available;
  final int printed;
  final int damaged;
  const _Tallies({required this.available, required this.printed, required this.damaged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _TallyChip(label: l.inventoryStatusAvailable, value: available, color: IntesharColors.sage),
        _TallyChip(label: l.inventoryStatusPrinted, value: printed, color: context.tones.brandInk),
        _TallyChip(label: l.inventoryStatusDamaged, value: damaged, color: Theme.of(context).colorScheme.error),
      ],
    );
  }
}

class _TallyChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _TallyChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Formatters.money(value),
            style: IntesharType.display(18, color: color, w: FontWeight.w900),
          ),
          const SizedBox(width: 6),
          Text(
            label.toLowerCase(),
            style: IntesharType.sans(12, color: color, w: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String search;
  final ProductStatus? statusFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ProductStatus?> onStatusChanged;
  const _FilterBar({
    required this.search,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: l.inventorySearchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          _StatusFilterChips(value: statusFilter, onChanged: onStatusChanged),
        ],
      ),
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  final ProductStatus? value;
  final ValueChanged<ProductStatus?> onChanged;
  const _StatusFilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final options = <(ProductStatus?, String, Color)>[
      (null, l.inventoryFilterAll, cs.onSurface),
      (ProductStatus.AVAILABLE, l.inventoryStatusAvailable, IntesharColors.sage),
      (ProductStatus.PRINTED, l.inventoryStatusPrinted, context.tones.brandInk),
      (ProductStatus.DAMAGED, l.inventoryStatusDamaged, cs.error),
    ];
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final active = value == opt.$1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onChanged(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? context.tones.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  opt.$2,
                  style: IntesharType.sans(
                    12,
                    color: active ? IntesharColors.ink : opt.$3,
                    w: active ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── SKU group ─────────────────────────────────────────────────────────────────

class _SkuGroupCard extends ConsumerStatefulWidget {
  final SkuSummary summary;
  final String entityId;
  final bool readOnly;
  final int lowStock;
  final VoidCallback onChanged;
  const _SkuGroupCard({
    super.key,
    required this.summary,
    required this.entityId,
    required this.readOnly,
    required this.lowStock,
    required this.onChanged,
  });

  @override
  ConsumerState<_SkuGroupCard> createState() => _SkuGroupCardState();
}

class _SkuGroupCardState extends ConsumerState<_SkuGroupCard> {
  static const _pageSize = 50;

  bool _open = false;
  final List<Product> _products = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loadingFirst = false;
  bool _loadingMore = false;
  Object? _rowError;

  ProductRepository get _repo => ProductRepository(ref.read(apiClientProvider));

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && _products.isEmpty && !_loadingFirst) _loadFirst();
  }

  Future<void> _loadFirst() async {
    setState(() {
      _loadingFirst = true;
      _rowError = null;
    });
    try {
      final list = await _repo.readByEntityAndSku(widget.entityId, widget.summary.sku, page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(list);
        _page = 0;
        _hasMore = list.length == _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _rowError = e);
    } finally {
      if (mounted) setState(() => _loadingFirst = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _repo.readByEntityAndSku(widget.entityId, widget.summary.sku, page: _page + 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _products.addAll(next);
        _page += 1;
        _hasMore = next.length == _pageSize;
      });
    } catch (e) {
      if (mounted) _snack(AppLocalizations.of(context)!.inventoryLoadCodesFailed);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // Reload exactly the rows currently shown (after a mutation) in one request.
  Future<void> _reloadLoaded() async {
    final count = (_page + 1) * _pageSize;
    final list = await _repo.readByEntityAndSku(widget.entityId, widget.summary.sku, page: 0, size: count);
    if (!mounted) return;
    setState(() {
      _products
        ..clear()
        ..addAll(list);
      _hasMore = list.length == count;
    });
  }

  Future<void> _changeStatus(Product product, ProductStatus newStatus) async {
    try {
      await _repo.setStatus(product.id, newStatus);
      await _reloadLoaded();
      widget.onChanged(); // refresh the summary (counts, tallies, value)
    } catch (e) {
      if (mounted) {
        _snack(friendlyError(e, context));
      }
    }
  }

  /// Replaces the code on a voucher that has not been sold. The current PIN is
  /// never shown — it is encrypted at rest and only the sale reveals it — so this
  /// asks for the replacement rather than pretending to be an edit of a value.
  Future<void> _editPin(Product product) async {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'تعديل رمز القسيمة' : 'Correct voucher code'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAr
                    ? 'الرقم التسلسلي: ${product.serialNumber}'
                    : 'Serial: ${product.serialNumber}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: isAr ? 'الرمز الجديد' : 'New code',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? (isAr ? 'أدخل الرمز الجديد' : 'Enter the new code')
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                isAr
                    ? 'الرمز الحالي غير معروض لأنه مشفّر. لا يمكن تعديل قسيمة تم بيعها.'
                    : 'The current code is not shown because it is encrypted. '
                        'A voucher that has been sold cannot be changed.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text(isAr ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (entered == null || entered.isEmpty) return;
    try {
      await _repo.setPin(product.id, entered);
      if (!mounted) return;
      _snack(isAr ? 'تم تحديث رمز القسيمة' : 'Voucher code updated');
      await _reloadLoaded();
    } catch (e) {
      if (mounted) _snack(friendlyError(e, context));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final s = widget.summary;

    return InkCard(
      padding: EdgeInsets.zero,
      ruleColor: s.available > 0 ? IntesharColors.sage : null,
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.available > 0 ? context.tones.brand : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(
                      s.sku,
                      style: IntesharType.mono(
                        12,
                        color: s.available > 0 ? IntesharColors.ink : cs.onSurfaceVariant,
                        w: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: IntesharType.sans(17, color: cs.onSurface, w: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${Formatters.iqd(s.defaultPrice.round())}  ·  ${l.inventoryUnitCount(s.total)}',
                          style: IntesharType.sans(12, color: IntesharColors.inkSoft),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (s.available > 0) ...[
                    StampPill(label: l.inventoryAvailableCount(s.available), color: IntesharColors.sage),
                    const SizedBox(width: 6),
                  ],
                  if (s.printed > 0) ...[
                    StampPill(label: l.inventoryPrintedCount(s.printed), color: context.tones.brandInk),
                    const SizedBox(width: 6),
                  ],
                  if (s.damaged > 0) ...[
                    StampPill(label: l.inventoryDamagedCount(s.damaged), color: cs.error),
                    const SizedBox(width: 6),
                  ],
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _open ? 0.25 : 0,
                    child: Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          _GovBreakdown(summary: s, lowStock: widget.lowStock),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox(height: 0, width: double.infinity),
            secondChild: _expandedBody(l, cs),
          ),
        ],
      ),
    );
  }

  Widget _expandedBody(AppLocalizations l, ColorScheme cs) {
    if (_loadingFirst) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
    }
    if (_rowError != null) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l.inventoryLoadCodesFailed,
                style: IntesharType.sans(13, color: cs.error, w: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: _loadFirst, child: Text(l.retryButton)),
          ],
        ),
      );
    }
    if (_products.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
        child: Text(l.inventoryNoCodes, style: IntesharType.sans(13, color: cs.onSurfaceVariant)),
      );
    }
    return Column(
      children: [
        const Hairline(),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
          child: _ProductRowHeader(),
        ),
        const Hairline(),
        ...List.generate(_products.length, (i) {
          final p = _products[i];
          return Column(
            children: [
              _ProductRow(
                product: p,
                readOnly: widget.readOnly,
                onChangeStatus: (status) => _changeStatus(p, status),
                onEditPin: () => _editPin(p),
              ),
              if (i < _products.length - 1) const Hairline(),
            ],
          );
        }),
        if (_hasMore) ...[
          const Hairline(),
          _LoadMoreRow(
            loading: _loadingMore,
            shown: _products.length,
            total: widget.summary.total,
            onTap: _loadMore,
          ),
        ],
      ],
    );
  }
}

// ── Governorate subcategory breakdown ─────────────────────────────────────────

class _GovBreakdown extends StatelessWidget {
  final SkuSummary summary;
  final int lowStock;
  const _GovBreakdown({required this.summary, required this.lowStock});

  @override
  Widget build(BuildContext context) {
    final buckets = summary.governorates;
    // Only show the subcategory strip when there is a real governorate breakdown.
    if (buckets.isEmpty) return const SizedBox.shrink();
    if (buckets.length == 1 && buckets.first.isUntagged) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final loc = Localizations.localeOf(context).languageCode;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.inventoryByGovernorate, style: IntesharType.overline(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          ...buckets.map((b) {
            final label = b.isUntagged ? l.inventoryUntagged : governorateLabel(b.governorate, loc);
            final low = b.available < lowStock;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: b.available > 0 ? IntesharColors.sage : cs.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (low) ...[
                    StampPill(label: l.inventoryLow, color: cs.error, fontSize: 10),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '${b.available} / ${b.total}',
                    style: IntesharType.mono(12, color: low ? cs.error : cs.onSurfaceVariant, w: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _LoadMoreRow extends StatelessWidget {
  final bool loading;
  final int shown;
  final int total;
  final VoidCallback onTap;
  const _LoadMoreRow({required this.loading, required this.shown, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return InkWell(
      onTap: loading ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.expand_more, size: 18, color: context.tones.brandInk),
            const SizedBox(width: 8),
            Text(
              loading ? l.inventoryShowingCount(shown, total) : l.inventoryLoadMore,
              style: IntesharType.sans(13, color: context.tones.brandInk, w: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductRowHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = IntesharType.sans(11, color: IntesharColors.inkSoft, w: FontWeight.w700);
    final l = AppLocalizations.of(context)!;
    return Row(
      children: [
        const SizedBox(width: 20), // dot spacer
        const SizedBox(width: 12),
        Expanded(child: Text(l.invColSnPin, style: style)),
        SizedBox(width: 96, child: Text(l.dashColStatus, style: style)),
        const SizedBox(width: 36), // menu spacer
      ],
    );
  }
}

/// Menu value for "correct the code" — kept distinct from every ProductStatus
/// name so the two kinds of action cannot collide.
const String _kEditPin = '__edit_pin__';

class _ProductRow extends StatelessWidget {
  final Product product;
  final bool readOnly;
  final ValueChanged<ProductStatus> onChangeStatus;
  final VoidCallback onEditPin;
  const _ProductRow({
    required this.product,
    required this.readOnly,
    required this.onChangeStatus,
    required this.onEditPin,
  });

  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (product.status) {
      ProductStatus.AVAILABLE => IntesharColors.sage,
      ProductStatus.SENT_FOR_PRINTING => context.tones.brand,
      ProductStatus.PRINTED => context.tones.brandInk,
      ProductStatus.FAILED_PRINTING => cs.error,
      ProductStatus.DAMAGED => cs.error,
    };
  }

  String _statusLabel(BuildContext context, ProductStatus s) {
    final l = AppLocalizations.of(context)!;
    return switch (s) {
      ProductStatus.AVAILABLE => l.inventoryStatusAvailable,
      ProductStatus.SENT_FOR_PRINTING => l.inventoryStatusSentForPrinting,
      ProductStatus.PRINTED => l.inventoryStatusPrinted,
      ProductStatus.FAILED_PRINTING => l.inventoryStatusFailedPrinting,
      ProductStatus.DAMAGED => l.inventoryStatusDamaged,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final color = _statusColor(context);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(l.inventorySnLabel, style: IntesharType.overline(color: cs.onSurfaceVariant, size: 9)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: monoText(
                        product.serialNumber,
                        size: 13,
                        color: cs.onSurface,
                        w: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                // PIN is encrypted at rest and stripped from list reads — only
                // shown if a value is actually present (e.g. legacy plaintext).
                if (product.pin.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(l.posPin, style: IntesharType.overline(color: cs.onSurfaceVariant, size: 9)),
                      const SizedBox(width: 8),
                      monoText(product.pin, size: 12, color: IntesharColors.lichen, letterSpacing: 1.2),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: StampPill(label: _statusLabel(context, product.status), color: color, fontSize: 10),
            ),
          ),
          if (readOnly)
            const SizedBox(width: 36)
          else
            PopupMenuButton<String>(
              tooltip: l.inventoryChangeStatus,
              icon: Icon(Icons.more_horiz, size: 18, color: cs.onSurfaceVariant),
              onSelected: (value) {
                if (value == _kEditPin) {
                  onEditPin();
                } else {
                  onChangeStatus(ProductStatus.values.byName(value));
                }
              },
              itemBuilder: (_) => [
                ...ProductStatus.values
                    .where((s) =>
                        s != product.status &&
                        (s == ProductStatus.AVAILABLE || s == ProductStatus.DAMAGED))
                    .map(
                      (s) => PopupMenuItem(
                        value: s.name,
                        child: Text(l.inventoryMarkStatus(_statusLabel(context, s))),
                      ),
                    ),
                // Only an unsold voucher can have its code corrected — the server
                // refuses the rest, so offering it here would be a dead button.
                if (product.status == ProductStatus.AVAILABLE)
                  PopupMenuItem(
                    value: _kEditPin,
                    child: Text(
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'تعديل الرمز'
                          : 'Correct code',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
