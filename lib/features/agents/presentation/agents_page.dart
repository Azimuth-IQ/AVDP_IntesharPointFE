import 'dart:async';
import 'package:inteshar/core/api/error_mapper.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/agents/data/agent_repository.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_form.dart';
import 'package:inteshar/features/agents/presentation/agent_strings.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/presentation/delete_agent_sheet.dart';
import 'package:inteshar/features/entities/presentation/visible_products_sheet.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_network.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// HQ admin directory for one agent tier (Main Agents or Sub Agents). Paged,
/// searchable; create/edit via the shared [AgentForm]; delete via the shared
/// [showDeleteAgentSheet] clear-out sheet (same path as the hierarchy tree). The
/// page is reached only on HQ routes; the backend independently enforces that
/// create/update/delete are HQ-only.
class AgentsPage extends ConsumerStatefulWidget {
  final AgentTier tier;
  const AgentsPage({super.key, required this.tier});

  @override
  ConsumerState<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends ConsumerState<AgentsPage> {
  static const _pageSize = 50;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  final List<EntitySummaryRow> _items = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  // ─── UX-02: onboarding has no completion state ─────────────────────────────
  //
  // Creating an agent pops back to this list, and nothing anywhere says the new
  // account has no cards, no POS points and no prices. The four screens that fix
  // that are unlinked, so a new admin cannot derive the remaining steps from the
  // UI at all.
  //
  // Both feeds are bulk (one call per tier, not one per card) and each is
  // allowed to fail on its own — a step whose source we could not read says
  // "not checked" rather than inventing a green tick or a red flag.
  static const int _readinessMaxPages = 5;
  Map<String, PosNetworkRow> _slots = const {};
  Map<String, int> _unpriced = const {};
  bool _slotsReady = false;
  bool _pricingReady = false;

  AgentTier get tier => widget.tier;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  AgentRepository get _repo => AgentRepository(ref.read(apiClientProvider));

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
    });
    try {
      final res = await _repo.list(tier.typeName, search: _searchCtrl.text.trim(), page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(res.items);
        _hasMore = res.hasMore;
        _loading = false;
      });
      unawaited(_loadReadiness());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final res = await _repo.list(tier.typeName, search: _searchCtrl.text.trim(), page: next, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(res.items);
        _page = next;
        _hasMore = res.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Fetches the two readiness signals that exist in bulk, for the whole tier at
  /// once. Deliberately silent on failure: the directory itself still works, and
  /// a step with no source shows as "not checked".
  Future<void> _loadReadiness() async {
    final api = ref.read(apiClientProvider);

    // POS points: one paged network table per tier (entityId → total/used).
    try {
      final acc = <String, PosNetworkRow>{};
      for (var page = 0; page < _readinessMaxPages; page++) {
        final res = await PosAdminRepository(api)
            // 100 is the server's hard cap; asking for more just gets 100 back
            // while `page` still steps by 100, so state it here.
            .network(tier: tier.typeName, page: page, size: 100);
        for (final r in res.items) {
          acc[r.entityId] = r;
        }
        if (!res.hasMore) break;
      }
      if (mounted) {
        setState(() {
          _slots = acc;
          _slotsReady = true;
        });
      }
    } catch (_) {/* step shows as unchecked */}

    // Prices: HQ-only, and Main Agents only — a sub agent inherits its main
    // agent's prices and has no pricing screen, so the step does not exist there.
    if (tier != AgentTier.main) return;
    try {
      final rows = await PricingRepository(api).unpricedAgents();
      if (mounted) {
        setState(() {
          _unpriced = {for (final r in rows) r.entityId: r.unpricedCount};
          _pricingReady = true;
        });
      }
    } catch (_) {/* step shows as unchecked */}
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  Future<void> _openForm({String? editId}) async {
    final repo = _repo;
    Entity? existing;
    if (editId != null) {
      try {
        existing = await repo.read(editId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
        }
        return;
      }
    }
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AgentForm(tier: tier, existing: existing)),
    );
    if (ok == true) _reload();
  }

  /// Deleting an agent is leaf-only AND needs an authenticator code, so this
  /// opens the same clear-out sheet the hierarchy tree uses instead of a local
  /// confirm dialog.
  ///
  /// The dialog this replaced called `delete(id)` with no code at all, which the
  /// server refuses for every tier — the button could not delete anything for a
  /// 2FA-enrolled admin, and it also gave an agent still holding sub-agents and
  /// shops a bare "leaf-only" refusal with nothing to act on. The sheet lists
  /// everything attached, deletes each item with its own confirmation code, and
  /// unlocks the account once it is empty.
  Future<void> _confirmDelete(EntitySummaryRow row) async {
    // True when ANYTHING went — the account itself, or any child cleared out on
    // the way there — which is exactly when this list is stale.
    final changed = await showDeleteAgentSheet(
      context,
      ref,
      entityId: row.id,
      entityName: row.label,
    );
    if (changed && mounted) _reload();
  }

  /// UX-103: which voucher SKUs this agent — and everything under it — may see
  /// and sell. The control existed but had exactly ONE entry point in the app: a
  /// menu item on a hierarchy-tree row. Deciding what a partner is allowed to
  /// sell is agent administration, so it belongs on the agent directory too;
  /// nothing about it suggested it lived inside the tree.
  Future<void> _openVisibleProducts(EntitySummaryRow row) async {
    await showVisibleProductsSheet(
      context,
      entityId: row.id,
      entityName: row.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AgentStrings.of(context, tier);
    final authState = ref.watch(authStateProvider).valueOrNull;
    final canManage = authState is AuthAuthenticated && authState.can({Capability.MANAGE_AGENTS});
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: s.pageEyebrow,
            title: s.pageTitle,
            subtitle: s.pageSubtitle,
            trailing: canManage
                ? FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.newAgent),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: s.searchHint,
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody(s, canManage: canManage)),
        ],
      ),
    );
  }

  Widget _buildBody(AgentStrings s, {required bool canManage}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _reload);
    if (_items.isEmpty) {
      return EmptyState(message: '${s.empty}\n${s.emptyHint}', actionLabel: s.newAgent, onAction: () => _openForm());
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(onPressed: _loadMore, child: Text(s.loadMore)),
              ),
            );
          }
          return _AgentCard(
            row: _items[i],
            s: s,
            tier: tier,
            canManage: canManage,
            slots: _slots[_items[i].id],
            slotsReady: _slotsReady,
            unpriced: _unpriced[_items[i].id] ?? 0,
            pricingReady: _pricingReady,
            onEdit: () => _openForm(editId: _items[i].id),
            onDelete: () => _confirmDelete(_items[i]),
            onVisibleProducts: () => _openVisibleProducts(_items[i]),
          );
        },
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final EntitySummaryRow row;
  final AgentStrings s;
  final AgentTier tier;
  final bool canManage;
  final PosNetworkRow? slots;
  final bool slotsReady;
  final int unpriced;
  final bool pricingReady;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onVisibleProducts;
  const _AgentCard({
    required this.row,
    required this.s,
    required this.tier,
    required this.canManage,
    required this.slots,
    required this.slotsReady,
    required this.unpriced,
    required this.pricingReady,
    required this.onEdit,
    required this.onDelete,
    required this.onVisibleProducts,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = s.ar ? 'ar' : 'en';
    return InkCard(
      ruleColor: context.tones.brand,
      padding: const EdgeInsets.all(16),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IntesharType.sans(17, color: cs.onSurface, w: FontWeight.w800)),
                    const SizedBox(height: 3),
                    SelectableText(row.id,
                        style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.3)),
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'edit' => onEdit(),
                    'visible_products' => onVisibleProducts(),
                    _ => onDelete(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(s.edit)),
                    PopupMenuItem(
                        value: 'visible_products',
                        child: Text(s.visibleProducts)),
                    PopupMenuItem(value: 'delete', child: Text(s.delete)),
                  ],
                ),
            ],
          ),
          if (row.parentName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.north_east, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(row.parentName, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(s.coverage, style: IntesharType.overline(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (row.governorates.isEmpty)
            Text(s.noRegions, style: IntesharType.sans(12.5, color: cs.onSurfaceVariant))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: row.governorates
                  .map((c) => StampPill(label: governorateLabel(c, locale), color: context.tones.brand, filled: false))
                  .toList(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.group_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(s.usersCount(row.userCount), style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
              const SizedBox(width: 16),
              Icon(Icons.account_tree_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(s.childrenCount(row.childrenCount), style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 14),
          const Hairline(),
          const SizedBox(height: 10),
          Text(s.setupTitle, style: IntesharType.overline(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          _readinessStrip(context),
        ],
      ),
    );
  }

  /// UX-02: the remaining onboarding steps, each saying where it stands and —
  /// where a screen exists for it — going straight there.
  ///
  /// Pricing has no HQ-side screen to link to (that is UX-01), so it reports its
  /// state and stops rather than pretending to be actionable from here.
  Widget _readinessStrip(BuildContext context) {
    final main = tier == AgentTier.main;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Cards on hand. Only a Main Agent ever holds stock — below that tier
        // vouchers are drawn at print time, so the step does not exist.
        if (main)
          _ReadyChip(
            icon: Icons.style_outlined,
            label: s.setupCards,
            value: row.productsCount > 0
                ? s.setupCardsSome(row.productsCount)
                : s.setupCardsNone,
            done: row.productsCount > 0,
            onTap: canManage ? () => context.push('/hq/batch') : null,
          ),
        _ReadyChip(
          icon: Icons.point_of_sale_outlined,
          label: s.setupSlots,
          value: !slotsReady
              ? s.setupUnknown
              : (slots?.total ?? 0) > 0
                  ? s.setupSlotsSome(slots?.available ?? 0, slots?.total ?? 0)
                  : s.setupSlotsNone,
          done: slotsReady && (slots?.total ?? 0) > 0,
          unknown: !slotsReady,
          onTap: canManage ? () => context.push('/hq/pos-users') : null,
        ),
        if (main)
          _ReadyChip(
            icon: Icons.sell_outlined,
            label: s.setupPrices,
            value: !pricingReady
                ? s.setupUnknown
                : unpriced > 0
                    ? s.setupPricesMissing(unpriced)
                    : s.setupPricesOk,
            done: pricingReady && unpriced == 0,
            unknown: !pricingReady,
          ),
        _ReadyChip(
          icon: Icons.inventory_2_outlined,
          label: s.setupProducts,
          value: s.setupProductsAction,
          // No bulk source for "which SKUs are visible", so this is an entry
          // point rather than a verdict — it must not claim either state.
          unknown: true,
          onTap: canManage ? onVisibleProducts : null,
        ),
      ],
    );
  }
}

/// One onboarding step: what it is, where it stands, and (when a screen exists)
/// a tap that goes there.
class _ReadyChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool done;
  final bool unknown;
  final VoidCallback? onTap;

  const _ReadyChip({
    required this.icon,
    required this.label,
    required this.value,
    this.done = false,
    this.unknown = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = unknown
        ? IntesharColors.lichen
        : done
            ? IntesharColors.sage
            : IntesharColors.warn;
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            unknown
                ? icon
                : done
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
            size: 15,
            color: tone,
          ),
          const SizedBox(width: 6),
          // Bounded so a long localized value ellipsizes inside its own chip
          // instead of overflowing the card on a phone.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(11,
                        color: cs.onSurfaceVariant, w: FontWeight.w600)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(12.5,
                        color: cs.onSurface, w: FontWeight.w700)),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            // Direction-neutral on purpose: a chevron would point the wrong way
            // in the Arabic layout this app is primarily read in.
            Icon(Icons.open_in_new, size: 14, color: cs.onSurfaceVariant),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IntesharRadii.sm),
      child: chip,
    );
  }
}
