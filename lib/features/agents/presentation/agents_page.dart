import 'dart:async';

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
import 'package:inteshar/features/entities/presentation/entity_row_actions.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_network.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/shared/widgets/app_search_field.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

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

  /// Creating a NEW agent. Editing an existing one goes through the canonical
  /// row action set (UX-93) — the same editor, from the same menu, as the
  /// hierarchy tree and the oversight tab.
  Future<void> _openForm() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AgentForm(tier: tier)),
    );
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = AgentStrings.of(context, tier);
    final authState = ref.watch(authStateProvider).valueOrNull;
    final canManage = authState is AuthAuthenticated && authState.can({Capability.MANAGE_AGENTS});
    // UX-13: a roster is scanned, not read, so it takes the data cap
    // (1600) rather than the prose one (1280).
    return MaxWidthBox.wide(
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
          // UX-93/UX-133: the same search box the hierarchy uses — this one had
          // no clear button at all, so backing out of a query on a phone meant
          // fifteen backspaces under the keyboard.
          AppSearchField(
            controller: _searchCtrl,
            hintText: s.searchHint,
            clearTooltip: s.ar ? 'مسح البحث' : 'Clear search',
            // UX-12: this directory's whole job is finding one agent among
            // hundreds, and it is an HQ-console screen. On the web admin the
            // caret starts here; on a handheld it never does.
            autofocus: desktopSearchAutofocus(context),
            onChanged: _onSearchChanged,
            // Only when the list is complete — otherwise this counts the page.
            resultCount: (_loading || _hasMore || _searchCtrl.text.trim().isEmpty)
                ? null
                : _items.length,
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
    // UX-13: one narrow column of tall cards wasted ~360dp of a 1080p browser
    // and showed about five agents at once — so "which agent has the fewest POS
    // points?" needed scrolling, and a comparison you scroll for is one you
    // cannot make. `AdaptiveColumns` deals the cards across up to three columns
    // and collapses back to one on a phone.
    //
    // The list is still lazily PAGED (`_hasMore` / `_loadMore`), so the set
    // built here is one page, not the whole roster — which is why building the
    // children together rather than through an itemBuilder is affordable.
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        children: [
          AdaptiveColumns(
            children: [
              for (final row in _items)
                _AgentCard(
                  row: row,
                  s: s,
                  tier: tier,
                  canManage: canManage,
                  slots: _slots[row.id],
                  slotsReady: _slotsReady,
                  unpriced: _unpriced[row.id] ?? 0,
                  pricingReady: _pricingReady,
                  onChanged: _reload,
                ),
            ],
          ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(onPressed: _loadMore, child: Text(s.loadMore)),
              ),
            ),
        ],
      ),
    );
  }
}

/// One agent in the directory.
///
/// UX-93: the identity block and the readiness strip are this page's own, but
/// every ACTION on the row is the canonical set — the same menu, with the same
/// capability gating, as the hierarchy tree and the oversight tab. Tapping the
/// card opens the agent's own page rather than dropping straight into the edit
/// form, so "look at this agent" and "change this agent" stop being the same
/// gesture.
class _AgentCard extends ConsumerWidget {
  final EntitySummaryRow row;
  final AgentStrings s;
  final AgentTier tier;
  final bool canManage;
  final PosNetworkRow? slots;
  final bool slotsReady;
  final int unpriced;
  final bool pricingReady;
  final VoidCallback onChanged;
  const _AgentCard({
    required this.row,
    required this.s,
    required this.tier,
    required this.canManage,
    required this.slots,
    required this.slotsReady,
    required this.unpriced,
    required this.pricingReady,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final locale = s.ar ? 'ar' : 'en';
    return InkCard(
      ruleColor: context.tones.brand,
      padding: const EdgeInsets.all(16),
      onTap: () => openAgentDetail(context, row.id, row.label, onChanged: onChanged),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(row.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: IntesharType.sans(16,
                                  color: cs.onSurface, w: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        // UX-93: the same object wore a different face on every
                        // surface — a role badge in the oversight tab, a colour-
                        // coded avatar in the hierarchy, and nothing at all
                        // here. This is the shared badge.
                        RoleBadge(type: row.type),
                      ],
                    ),
                    const SizedBox(height: 3),
                    SelectableText(row.id,
                        style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.3)),
                  ],
                ),
              ),
              // Tapping the card already opens the agent, so the menu does not
              // repeat that hop.
              EntityRowActionsButton(row: row, onChanged: onChanged, showOpen: false),
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
            Text(s.noRegions, style: IntesharType.sans(12, color: cs.onSurfaceVariant))
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
              Text(s.usersCount(row.userCount), style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
              const SizedBox(width: 16),
              Icon(Icons.account_tree_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(s.childrenCount(row.childrenCount), style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 14),
          const Hairline(),
          const SizedBox(height: 10),
          Text(s.setupTitle, style: IntesharType.overline(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          _readinessStrip(context, ref),
        ],
      ),
    );
  }

  /// UX-02: the remaining onboarding steps, each saying where it stands and —
  /// where a screen exists for it — going straight there.
  ///
  /// Pricing has no HQ-side screen to link to (that is UX-01), so it reports its
  /// state and stops rather than pretending to be actionable from here.
  Widget _readinessStrip(BuildContext context, WidgetRef ref) {
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
          onTap: canManage
              ? () => runEntityRowAction(
                    context, ref, EntityRowAction.visibleProducts, row,
                    onChanged: onChanged)
              : null,
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
        ? context.status.neutral
        : done
            ? context.status.success
            : context.status.warn;
    final chip = Container(
      // UX-119: three of these four chips are the only route to their setup
      // screen, and the two-line body left them ~44dp tall — under the 48dp
      // minimum, on a control an admin taps on a phone. Applied to all four so
      // the strip does not go ragged.
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(
          horizontal: IntesharSpacing.sm2, vertical: IntesharSpacing.sm),
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
                        color: cs.onSurfaceVariant, w: IntesharWeight.semibold)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(12,
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
