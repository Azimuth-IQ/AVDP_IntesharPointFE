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
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/confirm_code_dialog.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_search_field.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/loading_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// Where the cards pulled out of an agent's warehouse are headed (C-19).
///
/// The client asked for two destinations beyond the original — "تحويل لوكيل اخر
/// او اخراج من السستم بشكل نهائي".
///
/// [transfer] is a DELIVERY and the server selects it differently because of
/// that: region-locked stock outside the destination's governorates, expired
/// cards and supplier-recalled batches are all skipped. Pulling those back to
/// HQ is fine; handing them to an agent who cannot sell them is not.
enum WithdrawDestination {
  /// Back to HQ's own shelf, still sellable. The original behaviour.
  hq,

  /// Straight to another agent's warehouse, still sellable — by them.
  transfer,

  /// Out of circulation for good — non-sellable, kept for audit, restorable by HQ.
  retire,
}

/// Which destinations the "move stock out" dialog may offer, given whether the
/// warehouse on screen belongs to the viewer.
///
/// [WithdrawDestination.hq] means "put these cards back on HQ's own shelf". When
/// the warehouse on screen already IS HQ's, that is a move to where the cards
/// already sit — and the server says so twice: `POST /product/transfer` answers
/// `from == to` with a 400 ("Source and destination are the same account"), and
/// `InventoryHelper.transferStock` guards it again with
/// `!fromEntityId.equals(toEntityId)`. Offering it would be a control whose only
/// possible outcome is an error, so it is dropped rather than disabled.
///
/// The other two survive: transferring out to an agent is the core distribution
/// act, and retiring takes cards off the shelf wherever they are.
List<WithdrawDestination> stockDestinationsFor({required bool isOwnWarehouse}) =>
    isOwnWarehouse
        ? const [WithdrawDestination.transfer, WithdrawDestination.retire]
        : const [
            WithdrawDestination.hq,
            WithdrawDestination.transfer,
            WithdrawDestination.retire,
          ];

/// The destination a freshly opened dialog starts on — always the first one
/// actually offered, so the dialog never opens on a choice it does not show.
WithdrawDestination defaultStockDestination({required bool isOwnWarehouse}) =>
    stockDestinationsFor(isOwnWarehouse: isOwnWarehouse).first;

/// The one stock screen, reached through four doors:
///
///   * `/hq/inventory` — HQ's own holding, with a picker onto any Main Agent's;
///   * `/hq/entities/:id/inventory` — HQ drilling into a child from the tree;
///   * `/agent1/inventory` — a Main Agent's own warehouse;
///   * `/agent1|/agent2/entities/:id/inventory` — an agent drilling downstream.
///
/// UX-104: no two of them used to grant the same powers. HQ could withdraw and
/// correct codes through the dropdown but not through the tree drill-in — the
/// same person, looking at the same warehouse, with different buttons depending
/// on which link they had clicked, and nothing on either screen saying which
/// mode they were in.
///
/// What the viewer may do is now decided from **who is signed in** and **whose
/// warehouse is on screen** (see `_canEditProducts` / `_canMoveStock`), never
/// from the route. The only thing the route still decides is navigation: the
/// standalone screen carries the "viewing inventory of" picker, the pushed
/// drill-in carries a back-aware AppBar naming one account.
class InventoryPage extends ConsumerStatefulWidget {
  /// When set, browses this entity's inventory instead of the signed-in
  /// entity's — used for the drill-in to a child's stock.
  final String? entityId;

  /// Forces browse-only regardless of the viewer's tier. A floor, not the rule:
  /// the powers themselves come from the viewer/target pair, so a caller that
  /// leaves this `false` still gets read-only unless the viewer actually has
  /// authority over the warehouse on screen.
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

  /// UX-104: the signed-in tier. Together with [_selfId] and the account being
  /// viewed it decides every power on this screen.
  EntityType? _viewerType;
  String? _selfId; // signed-in entity id (the default "own holding" option)
  String? _selectedId; // chosen entity to view (null => self)
  List<EntitySummaryRow> _mainAgents = [];

  bool get _viewerIsHq => _viewerType == EntityType.INTESHAR;

  /// The "view a Main Agent's inventory" picker. Conceptually only HQ and the
  /// Main Agents hold stock, so HQ can inspect its own holding or any AGENT1
  /// pool. Navigation, not authority: the pushed drill-in already names one
  /// account in its AppBar, so it does not carry a control for switching away.
  bool get _showOwnerPicker => widget.entityId == null && _viewerIsHq;

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
      _viewerType = auth is AuthAuthenticated ? auth.entity.type : null;
      if (_showOwnerPicker && _mainAgents.isEmpty) {
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

  /// UX-104: may this viewer change a card's status or correct its code here?
  ///
  /// HQ publishes the catalog and loads the codes, so it may do both in any
  /// warehouse it can see — its own or an agent's, reached through the picker or
  /// through the tree. Every other tier browses: a Main Agent's stock is fed and
  /// recalled by HQ, and a sub-agent/shop holds no cards at all (draw-on-print).
  bool get _canEditProducts => !widget.readOnly && _viewerIsHq;

  /// May this viewer move stock out of the warehouse currently on screen?
  ///
  /// The same authority as [_canEditProducts]. This used to additionally require
  /// the warehouse to belong to somebody ELSE, on the reasoning that there was
  /// "nowhere to pull it to" from your own holding. That was true while the only
  /// destination was *back to HQ* — but C-19 added **transfer to another agent**
  /// and **retire**, and both are meaningful from HQ's own warehouse. Moving
  /// stock out of it to an agent is, in fact, the core distribution act.
  ///
  /// With the exclusion in place, anything already sitting in HQ's own warehouse
  /// was stranded: the only way to get cards to an agent was to name the target
  /// at batch-load time, so a batch loaded without one had no control on it at
  /// all. Reported by the client 2026-08-29 as
  /// "بضاعة بالمخزن بدون تحكم" — stock in the warehouse with nothing you can do
  /// to it. The server never carried this restriction: `/product/transfer` is
  /// HQ-only and rejects only `from == to`.
  bool get _canMoveStock => _canEditProducts;

  int _statusCount(SkuSummary s, ProductStatus status) => switch (status) {
        ProductStatus.AVAILABLE => s.available,
        ProductStatus.PRINTED => s.printed,
        ProductStatus.DAMAGED => s.damaged,
        ProductStatus.SENT_FOR_PRINTING => s.sentForPrinting,
        ProductStatus.FAILED_PRINTING => s.failedPrinting,
        ProductStatus.RETIRED => s.retired,
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
      return LoadingState(
        message: Localizations.localeOf(context).languageCode == 'ar'
            ? 'جارٍ تحميل المخزون…'
            : 'Loading inventory…',
      );
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final all = _summary ?? [];
    final filtered = _filtered;
    final lowStock = _lowStockThreshold();

    // UX-44: every number on this screen now counts what is ON SCREEN. Totals
    // taken from `all` while the list rendered `filtered` were the classic
    // misread — the whole warehouse's value sitting above three search matches,
    // with nothing saying so.
    final isFiltered = _search.isNotEmpty || _statusFilter != null;
    final filterNote =
        isFiltered ? l.inventoryFilteredNote(filtered.length, all.length) : null;
    final availableTotal = filtered.fold(0, (s, e) => s + e.available);
    final printedTotal = filtered.fold(0, (s, e) => s + e.printed);
    final damagedTotal = filtered.fold(0, (s, e) => s + e.damaged);
    final value = filtered.fold<num>(0, (s, e) => s + e.availableValue);
    // UX-36: this figure is a CLIENT-side sum of `SkuSummary.availableValue`,
    // while the pricing screen and the detailed report print the server's
    // `inventoryWorth` under the same two words (قيمة المخزون). Two screens, one
    // name, and — when a SKU arrives without governorate buckets —
    // `available × defaultPrice` instead of the effective per-agent price. The
    // label now states which basis produced the number rather than letting the
    // two look interchangeable.
    final estimatedBasis =
        filtered.any((e) => e.governorates.isEmpty && e.available > 0);

    // UX-13: a stock list is compared down a column (which SKU is low, where),
    // not read. It takes the data cap rather than the prose one.
    return MaxWidthBox.wide(
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
              filterNote: filterNote,
            ),
          ),
          if (_showOwnerPicker)
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
          if (filtered.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
              child: _InventoryValueCard(
                value: value,
                availableUnits: availableTotal,
                filterNote: filterNote,
                estimatedBasis: estimatedBasis,
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
                          child: SkuGroupCard(
                            key: ValueKey(s.sku),
                            summary: s,
                            entityId: _entityId!,
                            // UX-104: the viewer's authority, not the route's.
                            readOnly: !_canEditProducts,
                            lowStock: lowStock,
                            statusFilter: _statusFilter,
                            canWithdraw: _canMoveStock,
                            // Decides the DESTINATIONS offered, not whether the
                            // action exists: "back to the HQ warehouse" is a
                            // no-op when HQ's warehouse is the one on screen.
                            isOwnWarehouse: _entityId == _selfId,
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

  /// Set while a search or status filter is narrowing the list — the value below
  /// is then the value of the MATCHES, and has to say so.
  final String? filterNote;

  /// UX-36: at least one SKU in the sum had no governorate buckets, so its line
  /// fell back to `available × defaultPrice` instead of the effective per-agent
  /// price. The caption says so — the same words on the pricing screen name the
  /// server's `inventoryWorth`, which is a different calculation.
  final bool estimatedBasis;
  const _InventoryValueCard({
    required this.value,
    required this.availableUnits,
    this.filterNote,
    this.estimatedBasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final l = AppLocalizations.of(context)!;
    return InkCard(
      // UX-135: was a hand-typed 18/16 inset. `normal` is the 16 every other
      // content card in the app carries.
      density: CardDensity.normal,
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
          const SizedBox(width: IntesharSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l.inventoryValueLabel,
                        style: IntesharType.sans(12,
                            color: cs.onSurfaceVariant, w: IntesharWeight.semibold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (filterNote != null) ...[
                      const SizedBox(width: IntesharSpacing.sm),
                      StampPill(
                        label: filterNote!,
                        color: context.tones.brandInk,
                        icon: Icons.filter_alt_outlined,
                        fontSize: 10,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: IntesharSpacing.xs),
                Text(
                  Formatters.iqd(value.round()),
                  style: IntesharType.display(24, color: cs.onSurface, w: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: IntesharSpacing.xs),
                // UX-36: the basis, stated. "قيمة المخزون" names a server figure
                // on the pricing screen and the detailed report; this one is
                // summed here, from these rows, at these prices — so it says
                // which, instead of borrowing their authority.
                Text(
                  ar
                      ? (estimatedBasis
                          ? 'الكروت المتاحة × السعر — بعض الفئات بالسعر الافتراضي'
                          : 'الكروت المتاحة × سعرك الفعّال')
                      : (estimatedBasis
                          ? 'available cards × price — some categories at the default price'
                          : 'available cards × your effective price'),
                  style: IntesharType.sans(11, color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: IntesharSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.money(availableUnits),
                style: IntesharType.display(20, color: cs.onSurface, w: FontWeight.w800),
              ),
              Text(
                l.inventoryValueUnits,
                style: IntesharType.sans(11, color: cs.onSurfaceVariant),
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

  /// "Filtered · 3 of 41" — these tallies count the matches, not the warehouse.
  final String? filterNote;
  const _Tallies({
    required this.available,
    required this.printed,
    required this.damaged,
    this.filterNote,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: IntesharSpacing.sm,
      runSpacing: IntesharSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (filterNote != null)
          StampPill(
            label: filterNote!,
            color: context.tones.brandInk,
            icon: Icons.filter_alt_outlined,
            fontSize: 10,
          ),
        _TallyChip(label: l.inventoryStatusAvailable, value: available, color: context.status.success),
        _TallyChip(label: l.inventoryStatusPrinted, value: printed, color: context.tones.brandInk),
        _TallyChip(label: l.inventoryStatusDamaged, value: damaged, color: context.status.danger),
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
      padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.md, vertical: IntesharSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IntesharRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Formatters.money(value),
            // UX-127: was an off-scale 18. `title` (16) rather than the next step
            // up: three of these ride in the header's capped trailing slot beside
            // a 12px word each, and a seven-digit tally at 20 stops fitting.
            style: IntesharType.display(IntesharScale.title,
                color: color, w: IntesharWeight.black),
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
              // UX-12: inventory is a find-a-serial screen. Autofocused on the
              // web console only — this same page runs on the POS handheld,
              // where an unbidden keyboard would cover the stock list.
              autofocus: desktopSearchAutofocus(context),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.inventorySearchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: onSearchChanged,
            ),
          ),
          const SizedBox(width: IntesharSpacing.md),
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
      (ProductStatus.AVAILABLE, l.inventoryStatusAvailable, context.status.success),
      (ProductStatus.PRINTED, l.inventoryStatusPrinted, context.tones.brandInk),
      (ProductStatus.DAMAGED, l.inventoryStatusDamaged, context.status.danger),
      (ProductStatus.RETIRED, l.inventoryStatusRetired, context.tones.brandInk),
    ];
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(IntesharRadii.pill),
      ),
      padding: const EdgeInsets.all(IntesharSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final active = value == opt.$1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: InkWell(
              borderRadius: BorderRadius.circular(IntesharRadii.pill),
              onTap: () => onChanged(opt.$1),
              // UX-119: the painted pill was ~31dp tall — five of them side by
              // side, on a handheld. It is floored at the 48dp target, and the
              // PILL itself grows rather than a transparent hit box around it:
              // the brand fill is the selection indicator, so slack between it
              // and the track would read as a control that missed.
              //
              // Height only. Widening these would push the fifth chip out of the
              // filter row, which is already tight beside the search field.
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.md),
                decoration: BoxDecoration(
                  color: active ? context.tones.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(IntesharRadii.pill),
                ),
                child: Text(
                  opt.$2,
                  style: IntesharType.sans(
                    12,
                    // Selected = a brand pill, so the label is the measured
                    // on-brand foreground, not a hardcoded ink.
                    color: active ? context.tones.onBrand : opt.$3,
                    w: active ? IntesharWeight.heavy : IntesharWeight.bold,
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

class SkuGroupCard extends ConsumerStatefulWidget {
  final SkuSummary summary;
  final String entityId;
  final bool readOnly;
  final int lowStock;
  final VoidCallback onChanged;
  /// Whether this viewer may move stock out of this warehouse at all.
  final bool canWithdraw;

  /// Whether the warehouse on screen is the viewer's OWN. Narrows the choice of
  /// destinations rather than removing the action: "back to the HQ warehouse" is
  /// a no-op when you already are the HQ warehouse, but transferring to an agent
  /// and retiring both still apply.
  final bool isOwnWarehouse;

  /// The status the list is filtered to, or null for "all". When it is set the
  /// card shows only that status's pill: filtering to Damaged used to leave big
  /// green "available" pills on every row, which reads as the filter not working.
  final ProductStatus? statusFilter;
  const SkuGroupCard({
    super.key,
    required this.summary,
    required this.entityId,
    required this.readOnly,
    required this.lowStock,
    required this.onChanged,
    this.canWithdraw = false,
    this.isOwnWarehouse = false,
    this.statusFilter,
  });

  @override
  ConsumerState<SkuGroupCard> createState() => _SkuGroupCardState();
}

class _SkuGroupCardState extends ConsumerState<SkuGroupCard> {
  static const _pageSize = 50;

  bool _open = false;
  final List<Product> _products = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loadingFirst = false;
  bool _loadingMore = false;

  /// A stock withdrawal is in flight — see [_withdrawDialog] (UX-87).
  bool _withdrawing = false;
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
      if (mounted) showError(context, e);
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
      if (mounted) showError(context, e);
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
              const SizedBox(height: IntesharSpacing.md),
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
              const SizedBox(height: IntesharSpacing.md),
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
      showOk(context, isAr ? 'تم تحديث رمز القسيمة' : 'Voucher code updated');
      await _reloadLoaded();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _tr(String ar, String en) =>
      Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

  /// Whether a status pill belongs on the header row under the current filter.
  bool _showsPill(ProductStatus status) =>
      widget.statusFilter == null || widget.statusFilter == status;

  /// Asks how many cards of this SKU to pull back and where they should go, then
  /// reports what actually moved — which can be fewer than asked if some sold in
  /// the meantime.
  Future<void> _withdrawDialog() async {
    final s = widget.summary;
    final controller = TextEditingController(text: '${s.available}');
    final formKey = GlobalKey<FormState>();
    final offered =
        stockDestinationsFor(isOwnWarehouse: widget.isOwnWarehouse);
    // On your own warehouse "back to HQ" is not offered, so it cannot be the
    // default either — transfer is the reason you opened this.
    final fallback =
        defaultStockDestination(isOwnWarehouse: widget.isOwnWarehouse);
    var destination = fallback;
    EntitySummaryRow? transferTarget;

    final entered =
        await showDialog<(int, WithdrawDestination, EntitySummaryRow?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(widget.isOwnWarehouse
              ? _tr('تحويل أو إخراج بضاعة', 'Move stock out')
              : _tr('سحب من المخزن', 'Withdraw from warehouse')),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.isOwnWarehouse
                      ? _tr(
                          'إخراج كروت "${s.name}" من مخزنك. '
                              'المتاح الآن ${s.available}. الكروت المباعة لا يمكن سحبها.',
                          'Move "${s.name}" cards out of your warehouse. '
                              '${s.available} available now. Sold cards cannot be taken back.',
                        )
                      : _tr(
                          'سحب كروت "${s.name}" من مخزن هذا الوكيل. '
                              'المتاح الآن ${s.available}. الكروت المباعة لا يمكن سحبها.',
                          'Pull "${s.name}" cards out of this agent\'s warehouse. '
                              '${s.available} available now. Sold cards cannot be taken back.',
                        )),
                  const SizedBox(height: IntesharSpacing.md),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration:
                        InputDecoration(labelText: _tr('العدد', 'How many')),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) {
                        return _tr('أدخل عدداً صحيحاً', 'Enter a whole number');
                      }
                      if (n > s.available) {
                        return _tr('المتاح ${s.available} فقط',
                            'Only ${s.available} available');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: IntesharSpacing.sm),
                  Text(
                    _tr('إلى أين؟', 'Where to?'),
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  RadioGroup<WithdrawDestination>(
                    groupValue: destination,
                    onChanged: (v) => setLocal(() => destination = v ?? fallback),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (offered.contains(WithdrawDestination.hq))
                          RadioListTile<WithdrawDestination>(
                            value: WithdrawDestination.hq,
                            contentPadding: EdgeInsets.zero,
                            title: Text(_tr(
                                'إلى مخزن المركز', 'To the HQ warehouse')),
                            subtitle: Text(_tr(
                              'تبقى الكروت صالحة للبيع ويمكن توزيعها من جديد.',
                              'The cards stay sellable and can be handed out again.',
                            )),
                          ),
                        RadioListTile<WithdrawDestination>(
                          value: WithdrawDestination.transfer,
                          contentPadding: EdgeInsets.zero,
                          title:
                              Text(_tr('تحويل لوكيل آخر', 'To another agent')),
                          subtitle: Text(transferTarget == null
                              ? _tr(
                                  'اختر الوكيل. تُرسل فقط الكروت التي يستطيع بيعها.',
                                  'Pick the agent. Only cards they can sell are sent.',
                                )
                              : _tr(
                                  'إلى ${transferTarget!.name}',
                                  'To ${transferTarget!.name}',
                                )),
                          secondary: TextButton(
                            onPressed: () async {
                              final picked = await showEntitySearchPicker(
                                ctx,
                                repository: EntityRepository(
                                    ref.read(apiClientProvider)),
                                title: _tr('اختر الوكيل', 'Pick the agent'),
                                // Only tiers that HOLD stock may receive it.
                                // A Sub-Agent and a shop draw from their parent
                                // Main Agent's pool at print time, so cards
                                // handed to them sit where nothing can sell
                                // them: the POS sells by drawing on the PARENT,
                                // and no screen browses a shop's own warehouse.
                                // The picker offered every entity, so "transfer
                                // to a POS" looked like a supported operation —
                                // reported by the client 2026-08-31, after five
                                // vouchers had already been stranded that way.
                                // What flows down to a POS is balance.
                                where: (r) =>
                                    r.id != widget.entityId &&
                                    r.type.inventoryBacked,
                              );
                              if (picked != null) {
                                setLocal(() {
                                  transferTarget = picked;
                                  destination = WithdrawDestination.transfer;
                                });
                              }
                            },
                            child: Text(transferTarget == null
                                ? _tr('اختيار', 'Choose')
                                : _tr('تغيير', 'Change')),
                          ),
                        ),
                        RadioListTile<WithdrawDestination>(
                          value: WithdrawDestination.retire,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_tr('إخراج من السستم نهائياً',
                              'Out of the system permanently')),
                          subtitle: Text(_tr(
                            'تتوقف عن البيع نهائياً. يبقى الرمز محفوظاً للتدقيق '
                                'ويمكن للمركز إرجاعها.',
                            'They stop being sellable for good. The code is kept '
                                'for audit and HQ can put them back.',
                          )),
                        ),
                      ],
                    ),
                  ),
                  // Naming the destination is part of the instruction, not a
                  // detail: "transfer" with nobody chosen would otherwise fall
                  // through to a silent no-op at the server.
                  if (destination == WithdrawDestination.transfer &&
                      transferTarget == null)
                    Padding(
                      padding: const EdgeInsets.only(top: IntesharSpacing.sm),
                      child: Text(
                        _tr('اختر الوكيل المستلم أولاً.',
                            'Choose the receiving agent first.'),
                        style: Theme.of(ctx)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(ctx).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_tr('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: destination == WithdrawDestination.transfer &&
                      transferTarget == null
                  ? null
                  : () {
                      if (formKey.currentState?.validate() ?? false) {
                        Navigator.pop(ctx, (
                          int.parse(controller.text.trim()),
                          destination,
                          transferTarget
                        ));
                      }
                    },
              child: Text(switch (destination) {
                WithdrawDestination.retire => _tr('إخراج نهائي', 'Retire'),
                WithdrawDestination.transfer => _tr('تحويل', 'Transfer'),
                WithdrawDestination.hq => _tr('سحب', 'Withdraw'),
              }),
            ),
          ],
        ),
      ),
    );
    if (entered == null || !mounted) return;
    final (count, dest, target) = entered;

    // Retiring is irreversible in the same sense a delete is — it takes real,
    // money-backed codes off the shelf — so it is confirmed by the person doing
    // it, like /entity/delete and the POS revoke.
    String? code;
    if (dest == WithdrawDestination.retire) {
      code = await showConfirmCodeDialog(
        context,
        title: _tr('إخراج من السستم نهائياً', 'Retire permanently'),
        warning: _tr(
          'سيتم إخراج $count كرت من "${s.name}" من السستم ولن تعود للبيع. '
              'يبقى الرمز محفوظاً ويمكن للمركز إرجاعها لاحقاً.',
          '$count "${s.name}" card(s) will leave the system and stop being sellable. '
              'The codes are kept and HQ can restore them later.',
        ),
        confirmLabel: _tr('إخراج نهائي', 'Retire'),
      );
      if (code == null || !mounted) return;
    }

    // UX-87: the confirm closes instantly and the withdraw can take up to ~15s
    // on a bad link. Without this flag the icon stayed live and armed, and
    // "withdraw 100" tapped twice moved 200 cards. The button below reads
    // `_withdrawing` and shows a spinner instead.
    setState(() => _withdrawing = true);
    try {
      if (dest == WithdrawDestination.retire) {
        final res = await _repo.retireStock(
          fromEntityId: widget.entityId,
          sku: s.sku,
          count: count,
          totp: code,
        );
        if (!mounted) return;
        final ref = res.retireRef;
        showOk(
          context,
          res.isShort
              ? _tr(
                  'تم إخراج ${res.retired} من ${res.requested} — المتبقي ${res.remaining}',
                  'Retired ${res.retired} of ${res.requested} — ${res.remaining} left')
              : _tr('تم إخراج ${res.retired} كرت نهائياً',
                  'Retired ${res.retired} cards'),
          // The undo is offered where the mistake is noticed, not only on a
          // separate screen — pulling the wrong agent's stock is realised in the
          // second after it happens.
          actionLabel: ref == null ? null : _tr('تراجع', 'Undo'),
          onAction: ref == null ? null : () => _restoreRetired(ref),
        );
      } else if (dest == WithdrawDestination.transfer && target != null) {
        final res = await _repo.transferStock(
          fromEntityId: widget.entityId,
          toEntityId: target.id,
          sku: s.sku,
          count: count,
        );
        if (!mounted) return;
        // A transfer can move nothing for a reason that is not "out of stock":
        // the destination may not operate in the region this stock is locked to.
        // Saying only "Transferred 0 of 50" would read as a broken button.
        showOk(
          context,
          res.moved == 0 && res.remaining > 0
              ? _tr(
                  'لم يُحوَّل شيء — ${res.remaining} كرت لدى الوكيل لا يمكن '
                      'بيعها في مناطق ${target.name}',
                  'Nothing transferred — the agent\'s ${res.remaining} card(s) '
                      'cannot be sold in ${target.name}\'s regions')
              : res.isShort
                  ? _tr(
                      'تم تحويل ${res.moved} من ${res.requested} إلى ${target.name} — المتبقي ${res.remaining}',
                      'Transferred ${res.moved} of ${res.requested} to ${target.name} — ${res.remaining} left')
                  : _tr('تم تحويل ${res.moved} كرت إلى ${target.name}',
                      'Transferred ${res.moved} cards to ${target.name}'),
        );
      } else {
        final res = await _repo.withdrawStock(
          fromEntityId: widget.entityId,
          sku: s.sku,
          count: count,
        );
        if (!mounted) return;
        // Say what actually happened: "asked for 100, got 60" is the useful line.
        showOk(
            context,
            res.isShort
                ? _tr('تم سحب ${res.reclaimed} من ${res.requested} — المتبقي ${res.remaining}',
                    'Withdrew ${res.reclaimed} of ${res.requested} — ${res.remaining} left')
                : _tr('تم سحب ${res.reclaimed} كرت', 'Withdrew ${res.reclaimed} cards'));
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, serverReason(e) ?? e);
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  /// Puts a retire back — the undo behind the toast's action.
  ///
  /// Asks for the code again rather than reusing the one that authorised the
  /// retire: it is a second write, and a code that has already been spent on one
  /// action should not silently authorise another.
  Future<void> _restoreRetired(String retireRef) async {
    final code = await showConfirmCodeDialog(
      context,
      title: _tr('إرجاع الكروت', 'Restore the cards'),
      warning: _tr(
        'سيتم إرجاع الكروت إلى الوكيل الذي سُحبت منه وتعود للبيع.',
        'The cards go back to the account they were taken from and become sellable again.',
      ),
      confirmLabel: _tr('إرجاع', 'Restore'),
      destructive: false,
    );
    if (code == null || !mounted) return;
    try {
      final lot = await _repo.restoreRetired(retireRef, totp: code);
      if (!mounted) return;
      showOk(
          context,
          _tr('تم إرجاع ${lot.count} كرت إلى ${lot.displayFrom}',
              'Restored ${lot.count} cards to ${lot.displayFrom}'));
      widget.onChanged();
    } catch (e) {
      if (mounted) showError(context, serverReason(e) ?? e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final s = widget.summary;

    return InkCard(
      density: CardDensity.flush,
      ruleColor: s.available > 0 ? context.status.success : null,
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: IntesharSpacing.xs),
                        // The SKU used to lead the row inside a 44px gold
                        // circle. A circle is an avatar treatment and a SKU is
                        // a part number: "ASIACELL-5000" is thirteen monospace
                        // characters, about 100px of text, so it wrapped to
                        // three lines and clipped inside a 44px box — and it
                        // painted the brand at full saturation on every row,
                        // which fought the status rule already running down the
                        // card's start edge for the same "in stock" signal.
                        //
                        // It is a code, so it is set as one: monospace, on a
                        // quiet plate, in the metadata line where the rest of
                        // the identifying detail lives. Full SKU, no clipping.
                        Row(
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                    6, 1, 6, 2),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius:
                                      BorderRadius.circular(IntesharRadii.xs),
                                ),
                                child: Text(
                                  s.sku,
                                  // UX-147: full-strength ink, not the muted
                                  // variant. This is now the only place the SKU
                                  // appears, and it is content an operator
                                  // reads back — the class of text that item
                                  // says must not sit at chrome contrast.
                                  style: IntesharType.mono(11,
                                      color: cs.onSurface,
                                      w: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: IntesharSpacing.sm),
                            Flexible(
                              child: Text(
                                '${Formatters.iqd(s.defaultPrice.round())}  ·  ${l.inventoryUnitCount(s.total)}',
                                style: IntesharType.sans(12,
                                    color: cs.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: IntesharSpacing.sm),
                  // Only the pills the filter is asking about (all three when
                  // there is no filter).
                  if (_showsPill(ProductStatus.AVAILABLE) && s.available > 0) ...[
                    StampPill(label: l.inventoryAvailableCount(s.available), color: context.status.success),
                    const SizedBox(width: 6),
                  ],
                  if (_showsPill(ProductStatus.PRINTED) && s.printed > 0) ...[
                    StampPill(label: l.inventoryPrintedCount(s.printed), color: context.tones.brandInk),
                    const SizedBox(width: 6),
                  ],
                  if (_showsPill(ProductStatus.DAMAGED) && s.damaged > 0) ...[
                    StampPill(label: l.inventoryDamagedCount(s.damaged), color: context.status.danger),
                    const SizedBox(width: 6),
                  ],
                  // C-19: retired cards stay in `total`, so they need a pill of
                  // their own or the header reads as if some stock vanished.
                  if (_showsPill(ProductStatus.RETIRED) && s.retired > 0) ...[
                    StampPill(label: l.inventoryRetiredCount(s.retired), color: context.tones.brandInk),
                    const SizedBox(width: 6),
                  ],
                  // C-09: pull stock back from THIS agent's warehouse — the
                  // reallocation removed in B-051 ("سحب الكروت من المخزن … سابقا
                  // جان موجود"). Only where it can actually do something: HQ
                  // looking at somebody else's stock that is still sellable.
                  if (widget.canWithdraw && s.available > 0) ...[
                    IconButton(
                      // "Undo" reads as pulling stock BACK, which is only what
                      // this does on someone else's warehouse. On your own the
                      // same control sends stock out to an agent or retires it,
                      // so it is named and drawn for that.
                      tooltip: widget.isOwnWarehouse
                          ? _tr('تحويل أو إخراج', 'Transfer or retire')
                          : _tr('سحب من المخزن', 'Withdraw from warehouse'),
                      icon: _withdrawing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              widget.isOwnWarehouse
                                  ? Icons.move_down_outlined
                                  : Icons.undo_outlined,
                              size: 18),
                      onPressed: _withdrawing ? null : _withdrawDialog,
                    ),
                    const SizedBox(width: IntesharSpacing.xs),
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.xl),
        child: Center(
          child: LoadingState(
            compact: true,
            message: _tr('جارٍ تحميل الأكواد…', 'Loading codes…'),
          ),
        ),
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
                style: IntesharType.sans(14, color: context.status.danger, w: IntesharWeight.semibold),
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
        child: Text(l.inventoryNoCodes, style: IntesharType.sans(14, color: cs.onSurfaceVariant)),
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
        // UX-45: "Showing 50 of 10,000" used to render ONLY while the spinner was
        // up — the one piece of orientation in a very long list flashed for
        // 300ms and was replaced by "Load more". It is now always on screen,
        // including once everything is loaded.
        const Hairline(),
        _LoadMoreRow(
          loading: _loadingMore,
          shown: _products.length,
          total: widget.summary.total,
          onTap: _hasMore ? _loadMore : null,
        ),
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
              padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.xs),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: b.available > 0 ? context.status.success : cs.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: IntesharSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      style: IntesharType.sans(14, color: cs.onSurface, w: IntesharWeight.semibold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (low) ...[
                    // UX-128: low stock is `warn` — attention, not a failure.
                    StampPill(label: l.inventoryLow, color: context.status.warn, fontSize: 10),
                    const SizedBox(width: IntesharSpacing.sm),
                  ],
                  Text(
                    '${b.available} / ${b.total}',
                    style: IntesharType.mono(12, color: low ? context.status.warn : cs.onSurfaceVariant, w: FontWeight.w600),
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

/// The footer of an expanded SKU: where you are in the list, and — when there is
/// more — the control that fetches the next page. [onTap] is null once
/// everything is loaded, which leaves the position line on its own.
class _LoadMoreRow extends StatelessWidget {
  final bool loading;
  final int shown;
  final int total;
  final VoidCallback? onTap;
  const _LoadMoreRow({required this.loading, required this.shown, required this.total, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final canLoadMore = onTap != null;
    return InkWell(
      onTap: loading ? null : onTap,
      child: Padding(
        // UX-119/UX-135: was an off-scale `vertical: 14`, which made the row a
        // ~46dp target. `lg` is on the scale and clears 48.
        padding: const EdgeInsets.symmetric(
            vertical: IntesharSpacing.lg, horizontal: IntesharSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else if (canLoadMore)
              Icon(Icons.expand_more, size: 18, color: context.tones.brandInk),
            if (loading || canLoadMore) const SizedBox(width: IntesharSpacing.sm),
            // The position is permanent; "Load more" is the affordance beside it.
            Flexible(
              child: Text(
                l.inventoryShowingCount(shown, total),
                style: IntesharType.sans(14, color: cs.onSurfaceVariant, w: IntesharWeight.semibold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (canLoadMore && !loading) ...[
              const SizedBox(width: IntesharSpacing.sm),
              Text(
                l.inventoryLoadMore,
                style: IntesharType.sans(14, color: context.tones.brandInk, w: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductRowHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = IntesharType.sans(11,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        w: FontWeight.w700);
    final l = AppLocalizations.of(context)!;
    return Row(
      children: [
        const SizedBox(width: 20), // dot spacer
        const SizedBox(width: IntesharSpacing.md),
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
    return switch (product.status) {
      ProductStatus.AVAILABLE => context.status.success,
      ProductStatus.SENT_FOR_PRINTING => context.tones.brand,
      ProductStatus.PRINTED => context.tones.brandInk,
      ProductStatus.FAILED_PRINTING => context.status.danger,
      ProductStatus.DAMAGED => context.status.danger,
      ProductStatus.RETIRED => context.tones.brandInk,
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
      ProductStatus.RETIRED => l.inventoryStatusRetired,
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
          const SizedBox(width: IntesharSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(l.inventorySnLabel, style: IntesharType.overline(color: cs.onSurfaceVariant, size: 9)),
                    const SizedBox(width: IntesharSpacing.sm),
                    Flexible(
                      child: monoText(
                        // UX-127: was an off-scale 13 at a raw `w500` that has
                        // no registered face — both are monoText's defaults now.
                        product.serialNumber,
                        color: cs.onSurface,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                // PIN is encrypted at rest and stripped from list reads — only
                // shown if a value is actually present (e.g. legacy plaintext).
                if (product.pin.isNotEmpty) ...[
                  const SizedBox(height: IntesharSpacing.xs),
                  Row(
                    children: [
                      Text(l.posPin, style: IntesharType.overline(color: cs.onSurfaceVariant, size: 9)),
                      const SizedBox(width: IntesharSpacing.sm),
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
