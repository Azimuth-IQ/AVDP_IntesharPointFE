import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_form.dart';
import 'package:inteshar/features/agents/presentation/agent_strings.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/entity_row_actions.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_network.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_search_field.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/min_tap_target.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

// ─── UX-15 / UX-93: one directory for one kind of object ─────────────────────
//
// HQ listed the same `Entity` objects on four surfaces. UX-93's first pass made
// the ACTIONS identical everywhere (`entity_row_actions.dart`), which fixed
// "this menu can do things that menu cannot" — but it left four DOORS, and the
// question "where do I change X?" still had four answers.
//
// This page is the answer. It is the hierarchy tree and the two tier
// directories, merged:
//
//   * ONE feed. `GET /api/entity/search` with an empty query is the browse
//     list; the same call with a query is the search; the same call with
//     `type=` is what `/hq/main-agents` and `/hq/sub-agents` used to be. The
//     server scopes every one of them to the caller's own subtree.
//   * ONE search box, shared by both view modes.
//   * TREE IS A VIEW MODE, not a place. The toggle swaps the flat list for the
//     lazily-expanded org chart over the same rows and the same action menu.
//   * ONE action set — the canonical [EntityRowActionsButton], unchanged.
//
// `/hq/main-agents` and `/hq/sub-agents` are retired to redirects onto this
// page with `?type=` preselected, so an existing bookmark still lands on the
// rows it named. Nothing they could do is gone: creating an agent is the header
// action here, and the per-agent onboarding checklist they carried lives — in a
// fuller form, with the real slot figures and a pricing link — on the agent's
// own page, one tap from any row.

/// Per-level indent (UX-114). A phone steps half as far: four levels at 24dp is
/// 96dp of a 360dp screen consumed before the name even starts, and the tree is
/// four levels deep by design.
double _indentStep(bool wide) => wide ? 24.0 : 12.0;

/// Avatar-badge initial matching the CURRENT role names (B-080): HQ, Main Agent,
/// Sub Agent, POS/Store — was the stale G/D (Governorate/Distributor).
String _typeInitial(EntityType t) {
  switch (t) {
    case EntityType.INTESHAR:
      return 'H';
    case EntityType.AGENT1:
      return 'M';
    case EntityType.AGENT2:
      return 'S';
    case EntityType.STORE:
      return 'P';
  }
}

/// How the one directory is drawn. Both modes list the same rows, carry the same
/// search and offer the same actions — only the arrangement differs.
enum EntityViewMode {
  /// Flat, server-paged, type-filterable. The findable view, and the default:
  /// reaching one shop among hundreds must not require expanding three levels.
  list,

  /// The org chart, expanded lazily one node at a time. The view that shows
  /// WHERE an account sits, which a flat list can only hint at with a breadcrumb.
  tree,
}

/// The tiers a "new agent" header action can create, in menu order.
const List<AgentTier> _creatableTiers = [AgentTier.main, AgentTier.sub];

// ─── Page ────────────────────────────────────────────────────────────────────

class EntityDirectoryPage extends ConsumerStatefulWidget {
  /// Preselected type filter, from `?type=` on the route. The retired
  /// `/hq/main-agents` and `/hq/sub-agents` redirect here carrying it, so those
  /// links still land on exactly the rows they used to name.
  final EntityType? initialType;

  /// Which view opens first. Defaults to [EntityViewMode.list].
  final EntityViewMode initialMode;

  const EntityDirectoryPage({
    super.key,
    this.initialType,
    this.initialMode = EntityViewMode.list,
  });

  @override
  ConsumerState<EntityDirectoryPage> createState() => _EntityDirectoryPageState();
}

class _EntityDirectoryPageState extends ConsumerState<EntityDirectoryPage> {
  // ── View state ─────────────────────────────────────────────────────────────
  late EntityViewMode _mode = widget.initialMode;
  late EntityType? _typeFilter = widget.initialType;

  // ── Tree state ─────────────────────────────────────────────────────────────
  EntitySummaryRow? _root;
  Object? _treeError;
  bool _treeLoading = false;

  /// Ids currently expanded in the tree. Root is expanded by default.
  final Set<String> _expanded = {};

  // Lazy children cache (B-023): one `GET /api/entity/children` page per
  // expanded node instead of downloading the whole forest up front.
  final Map<String, List<EntitySummaryRow>> _children = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, int> _page = {};
  final Set<String> _loadingNodes = {};

  // ── List state ─────────────────────────────────────────────────────────────
  static const int _listPageSize = 50;
  List<EntitySummaryRow> _items = const [];
  int _listPage = 0;
  bool _listMore = false;
  bool _listLoading = true;
  bool _listLoadingMore = false;
  Object? _listError;

  // ─── UX-19: the figures beside a name ──────────────────────────────────────
  //
  // The only two data columns were children-count and vouchers-count, and under
  // draw-on-print BOTH are structurally zero below a Main Agent: no AGENT2 and
  // no STORE ever owns a `Product`, and a shop has no children. So a Sub Agent's
  // network page was a list of names beside two columns of zeros — on the one
  // screen they open to ask "how is my network doing".
  //
  // Balance and recent sales are the figures that actually move, and both
  // already exist server-side. They are fetched ONCE per load (not per row) and
  // are OMITTED — header and cells together — whenever the server won't hand
  // them over, because a confident zero is worse than a missing column.
  static const int _soldWindowDays = 30;
  static const int _rosterPageSize = 200;
  static const int _rosterMaxPages = 5;

  Map<String, num> _balances = {};
  Map<String, int> _sold = {};
  bool _balancesReady = false;
  bool _soldReady = false;

  // ─── UX-02 readiness, carried over from the retired agent directories ──────
  //
  // "Which agent has the fewest POS points?" was answerable only on
  // `/hq/main-agents`, by scanning its chip strip. Both feeds are bulk (one call
  // for the whole network, not one per agent), HQ-only, and each may fail on its
  // own — a step whose source we could not read simply does not render, rather
  // than inventing a green tick or a red flag.
  static const int _readinessMaxPages = 5;
  Map<String, PosNetworkRow> _slots = const {};
  Map<String, int> _unpriced = const {};
  bool _slotsReady = false;
  bool _pricingReady = false;

  // ── Search ─────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';

  EntityRepository get _repo => EntityRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    if (_mode == EntityViewMode.tree) {
      _loadTree();
    } else {
      _loadList();
    }
    // The figure columns and the readiness signals are shared by both views, so
    // they are fetched once here rather than per view switch.
    unawaited(_loadMetrics());
    unawaited(_loadReadiness());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── The one feed (list mode + every search) ───────────────────────────────

  /// Server-side, paged, tenancy-scoped listing of the caller's own network.
  ///
  /// An empty [_query] with no [_typeFilter] is the plain directory; a query
  /// narrows it; a type narrows it the way the retired tier pages did. It is the
  /// same endpoint in all three cases, so a hit and a browse row are literally
  /// the same object with the same actions.
  Future<void> _loadList({bool more = false}) async {
    if (more && (_listLoadingMore || !_listMore)) return;
    setState(() {
      if (more) {
        _listLoadingMore = true;
      } else {
        _listLoading = true;
        _listError = null;
      }
    });
    try {
      final next = more ? _listPage + 1 : 0;
      final res = await _repo.search(
        q: _query,
        types: _typeFilter == null ? null : [_typeFilter!],
        page: next,
        size: _listPageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = more ? [..._items, ...res.items] : res.items;
        _listPage = next;
        _listMore = res.hasMore;
        _listLoading = false;
        _listLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _listLoading = false;
        _listLoadingMore = false;
        if (!more) {
          _items = const [];
          _listError = e;
        }
      });
    }
  }

  // ─── Tree ──────────────────────────────────────────────────────────────────

  /// Reloads the tree.
  ///
  /// [keepOpen] re-fetches the branches the operator had expanded instead of
  /// collapsing everything back to the root. A refresh usually follows an action
  /// taken deep in the tree — deleting a shop three levels down — and dropping
  /// the operator back at the root to re-drill hides the very result they asked
  /// for. Cached rows are always discarded; only the SET of open branches is
  /// kept, so nothing stale survives.
  Future<void> _loadTree({bool keepOpen = false}) async {
    final reopen = keepOpen ? Set<String>.from(_expanded) : <String>{};
    setState(() {
      _treeLoading = true;
      _treeError = null;
      _expanded.clear();
      _children.clear();
      _hasMore.clear();
      _page.clear();
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

      // The root row comes from the full entity read (cheap: one document).
      final me = await _repo.read(entityId);
      final root = EntitySummaryRow(
        id: me.id,
        name: me.meta.name,
        type: me.type,
        childrenCount: me.childrenIds.length,
        productsCount: me.productsIds.length,
      );
      if (!mounted) return;
      setState(() {
        _root = root;
        _expanded.add(root.id); // root expanded by default
      });
      await _loadChildren(root.id);

      // Re-open what was open. Quietly: a branch whose parent was just deleted
      // will fail here, and that is the expected case rather than something to
      // report — it simply stops being expanded.
      for (final id in reopen) {
        if (id == root.id || !mounted) continue;
        final ok = await _loadChildren(id, quiet: true);
        if (!mounted) return;
        if (ok) {
          setState(() => _expanded.add(id));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _treeError = e);
    } finally {
      if (mounted) setState(() => _treeLoading = false);
    }
  }

  /// Returns false when the fetch failed, so a caller restoring expansion can
  /// drop a branch that no longer exists.
  Future<bool> _loadChildren(String parentId,
      {bool more = false, bool quiet = false}) async {
    if (_loadingNodes.contains(parentId)) return false;
    setState(() => _loadingNodes.add(parentId));
    try {
      final nextPage = more ? (_page[parentId] ?? 0) + 1 : 0;
      final res = await _repo.children(parentId, page: nextPage);
      if (!mounted) return false;
      setState(() {
        final current = more ? (_children[parentId] ?? const []) : const <EntitySummaryRow>[];
        _children[parentId] = [...current, ...res.items];
        _hasMore[parentId] = res.hasMore;
        _page[parentId] = nextPage;
      });
      return true;
    } catch (e) {
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
      return false;
    } finally {
      if (mounted) setState(() => _loadingNodes.remove(parentId));
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
    if (_expanded.contains(id) && !_children.containsKey(id)) {
      _loadChildren(id);
    }
  }

  // ─── Metrics (UX-19) ───────────────────────────────────────────────────────

  /// Fetches the two figures shown beside a name, for the whole subtree at once.
  ///
  /// Both feeds are section-gated server-side (HQ can hide reporting for an
  /// agent and everything under it), so each is allowed to fail on its own and
  /// simply takes its column with it. Nothing here ever falls back to `0`.
  Future<void> _loadMetrics() async {
    if (!mounted) return;

    // Asking without the capability would only earn a 403 per feed; skip it and
    // show a directory with no figure columns at all.
    final viewer = ref.read(authStateProvider).valueOrNull;
    if (viewer is! AuthAuthenticated || !viewer.can({Capability.VIEW_REPORTS})) {
      return;
    }
    final rootId = viewer.entity.id;
    if (rootId.isEmpty) return;

    setState(() {
      _balances = const {};
      _sold = const {};
      _balancesReady = false;
      _soldReady = false;
    });
    final reports = ReportsRepository(ref.read(apiClientProvider));

    // Balance: one roster for the subtree, keyed by entity id — exact at every
    // tier (inventory-backed for HQ/Main Agent, wallet points below). Capped, so
    // a very large tree leaves the tail without a figure rather than stalling.
    try {
      final acc = <String, num>{};
      for (var p = 0; p < _rosterMaxPages; p++) {
        final res = await reports.balancesRoster(
            rootId: rootId, page: p, size: _rosterPageSize);
        for (final r in res.items) {
          if (r.entityId.isNotEmpty) acc[r.entityId] = r.available;
        }
        if (!res.hasMore) break;
      }
      if (mounted) {
        setState(() {
          _balances = acc;
          _balancesReady = true;
        });
      }
    } catch (_) {
      // Column omitted. Deliberately silent: the directory itself still works.
    }

    // Sales: aggregated per shop over the window. Only shops ever sell, so this
    // map is keyed by store id and rolled up for agents in [_soldFor].
    try {
      final now = DateTime.now();
      final rows = await reports.sales(
        rootId: rootId,
        from: Formatters.date(
            now.subtract(const Duration(days: _soldWindowDays - 1))),
        to: Formatters.date(now),
      );
      final acc = <String, int>{};
      for (final r in rows) {
        if (r.storeId.isEmpty) continue;
        acc[r.storeId] = (acc[r.storeId] ?? 0) + r.count;
      }
      if (mounted) {
        setState(() {
          _sold = acc;
          _soldReady = true;
        });
      }
    } catch (_) {
      // Column omitted.
    }
  }

  /// The two onboarding signals that exist in bulk (UX-02). Both feeds are
  /// HQ-only and every chip they draw links to an HQ route, so this is fetched
  /// for exactly the viewer who could see the retired `/hq/main-agents` strip —
  /// HQ holding MANAGE_AGENTS. Failure is silent and simply drops the chip
  /// rather than reporting a state nobody confirmed.
  Future<void> _loadReadiness() async {
    if (!viewerCanManageEntities(ref)) return;
    final api = ref.read(apiClientProvider);

    // POS points: the whole network table (entityId → total/available), both
    // tiers in one paged sweep.
    try {
      final acc = <String, PosNetworkRow>{};
      for (var page = 0; page < _readinessMaxPages; page++) {
        // 100 is the server's hard cap; asking for more just gets 100 back while
        // `page` still steps by 100, so state it here.
        final res = await PosAdminRepository(api).network(page: page, size: 100);
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
    } catch (_) {/* chip omitted */}

    // Prices: Main Agents only — a sub agent inherits its main agent's prices and
    // has no pricing screen, so the step does not exist there.
    try {
      final rows = await PricingRepository(api).unpricedAgents();
      if (mounted) {
        setState(() {
          _unpriced = {for (final r in rows) r.entityId: r.unpricedCount};
          _pricingReady = true;
        });
      }
    } catch (_) {/* chip omitted */}
  }

  /// Cards sold in the window for [row]: its own for a shop, otherwise the sum
  /// over its descendants — and only when every branch below it has actually
  /// been loaded.
  ///
  /// A partial sum understates a network while reading as a real total, so an
  /// unloaded (or truncated) branch yields null and the cell stays blank.
  int? _soldFor(EntitySummaryRow row, [Set<String>? seen]) {
    if (!_soldReady) return null;
    if (row.type == EntityType.STORE) return _sold[row.id] ?? 0;
    final path = seen ?? <String>{};
    if (!path.add(row.id)) return null; // cycle guard, same as the render pass
    final kids = _children[row.id];
    if (kids == null) return row.childrenCount == 0 ? 0 : null;
    if (_hasMore[row.id] == true) return null;
    var total = 0;
    for (final k in kids) {
      final n = _soldFor(k, path);
      if (n == null) return null;
      total += n;
    }
    return total;
  }

  _NetworkFigures get _figures => _NetworkFigures(
        balances: _balances,
        balancesReady: _balancesReady,
        soldReady: _soldReady,
        soldWindowDays: _soldWindowDays,
        soldFor: _soldFor,
      );

  _Readiness get _readiness => _Readiness(
        slots: _slots,
        slotsReady: _slotsReady,
        unpriced: _unpriced,
        pricingReady: _pricingReady,
      );

  // ─── Search + mode ─────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final q = value.trim();
    if (q == _query) return;
    // A query is a LIST question — the tree cannot answer it, so the toggle
    // visibly moves rather than the tree silently turning into a flat list, the
    // way it used to.
    setState(() {
      _query = q;
      _mode = EntityViewMode.list;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _loadList();
    });
  }

  void _setMode(EntityViewMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      if (mode == EntityViewMode.tree) {
        // The tree shows everything under the caller; carrying a filter into it
        // would silently hide branches and make the org chart a lie.
        _query = '';
        _searchCtrl.clear();
      }
    });
    if (mode == EntityViewMode.tree) {
      if (_root == null) _loadTree();
    } else {
      _loadList();
    }
  }

  void _setTypeFilter(EntityType? type) {
    setState(() {
      _typeFilter = type;
      _mode = EntityViewMode.list;
    });
    _loadList();
  }

  /// What to re-fetch after a row action: whichever view the operator acted in,
  /// so they keep the screen they were looking at.
  Future<void> _afterMutation() async {
    unawaited(_loadMetrics());
    unawaited(_loadReadiness());
    if (_mode == EntityViewMode.tree) {
      await _loadTree(keepOpen: true);
    } else {
      await _loadList();
    }
  }

  // ─── Create (carried over from the retired tier directories) ───────────────

  Future<void> _createAgent(AgentTier tier) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AgentForm(tier: tier)),
    );
    if (ok == true) await _afterMutation();
  }

  /// The header action cluster. Creating an entity is HQ-only and additionally
  /// needs MANAGE_AGENTS — the same gate the row menu's mutating items use, and
  /// the one `CallerService` enforces server-side.
  PageActions? _headerActions() {
    if (!viewerCanManageEntities(ref)) return null;
    // With a tier already selected there is only one sensible thing to create,
    // so the button says which — exactly what `/hq/main-agents` used to offer.
    final tiers = switch (_typeFilter) {
      EntityType.AGENT1 => [AgentTier.main],
      EntityType.AGENT2 => [AgentTier.sub],
      _ => _creatableTiers,
    };
    PageAction actionFor(AgentTier t) => PageAction(
          label: AgentStrings.of(context, t).newAgent,
          icon: Icons.add,
          onPressed: () => _createAgent(t),
        );
    return PageActions(
      primary: actionFor(tiers.first),
      secondary: [for (final t in tiers.skip(1)) actionFor(t)],
    );
  }

  /// The type pills offered to this viewer: its own tier and everything below.
  /// An AGENT2 has no INTESHAR or AGENT1 in scope, so offering those pills would
  /// only ever produce an empty list.
  List<EntityType> _pillTypes() {
    final viewer = ref.read(authStateProvider).valueOrNull;
    final own = viewer is AuthAuthenticated ? viewer.entity.type : EntityType.STORE;
    return [
      for (final t in EntityType.values)
        if (t.index >= own.index) t,
    ];
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ar = Localizations.localeOf(context).languageCode == 'ar';

    return MaxWidthBox.wide(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            eyebrow: ar ? 'الشبكة' : 'Network',
            title: l.navHierarchy,
            subtitle: ar
                ? 'كل الحسابات التابعة لك — قائمة قابلة للبحث، أو شجرة تُظهر موقع كل حساب.'
                : 'Every account under you — as a searchable list, or as the tree that shows where each one sits.',
            actions: _headerActions(),
          ),
          AppSearchField(
            controller: _searchCtrl,
            hintText: ar
                ? 'ابحث بالاسم أو المعرّف في شبكتك'
                : 'Search your network by name or id',
            clearTooltip: ar ? 'مسح البحث' : 'Clear search',
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _loadList(),
            // Only once the whole hit list is in hand: while a page is still
            // outstanding this would count the page, not the matches.
            resultCount: (_mode == EntityViewMode.tree ||
                    _query.isEmpty ||
                    _listMore ||
                    _listLoading)
                ? null
                : _items.length,
          ),
          _Toolbar(
            mode: _mode,
            onModeChanged: _setMode,
            types: _pillTypes(),
            selectedType: _typeFilter,
            onTypeChanged: _setTypeFilter,
            ar: ar,
          ),
          Expanded(
            child: _mode == EntityViewMode.tree
                ? _treeBody(l, ar)
                : _listBody(l, ar),
          ),
        ],
      ),
    );
  }

  /// Width under which a row folds its figures onto a second line (UX-114).
  static const double _wideBreakpoint = 600;

  // ── List mode ──────────────────────────────────────────────────────────────

  Widget _listBody(AppLocalizations l, bool ar) {
    if (_listLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_listError != null && _items.isEmpty) {
      return ErrorState(error: _listError!, onRetry: _loadList);
    }
    if (_items.isEmpty) {
      return EmptyState(
        message: _query.isEmpty
            ? l.entityTreeNoChildren
            : (ar
                ? 'لا توجد حسابات مطابقة لـ "$_query"'
                : 'No accounts match "$_query"'),
        actionLabel: l.entityTreeRefresh,
        onAction: _loadList,
      );
    }

    final figures = _figures;
    final readiness = _readiness;
    return RefreshIndicator(
      onRefresh: _afterMutation,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= _wideBreakpoint;
              return InkCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (wide) ...[
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                        child: _TableHeader(l: l, figures: figures),
                      ),
                      const Hairline(),
                    ],
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const Hairline(),
                      // Depth 0 and never expandable: a flat directory is the
                      // point. The row still carries the full action menu, which
                      // is what made the tree worth reaching in the first place.
                      _EntityRowTile(
                        entity: _items[i],
                        depth: 0,
                        isLeaf: true,
                        isExpanded: false,
                        onToggle: () {},
                        onRefresh: _afterMutation,
                        figures: figures,
                        readiness: readiness,
                        wide: wide,
                        listMode: true,
                        breadcrumb: _items[i].parentName,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (_listMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _listLoadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () => _loadList(more: true),
                        child: Text(ar ? 'تحميل المزيد' : 'Load more'),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Tree mode ──────────────────────────────────────────────────────────────

  Widget _treeBody(AppLocalizations l, bool ar) {
    if (_treeLoading && _root == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_treeError != null) {
      return ErrorState(error: _treeError!, onRetry: _loadTree);
    }
    final root = _root;
    if (root == null) {
      return EmptyState(
        message: l.entityTreeNoChildren,
        actionLabel: l.entityTreeRefresh,
        onAction: _loadTree,
      );
    }

    final figures = _figures;
    final readiness = _readiness;
    return RefreshIndicator(
      onRefresh: _afterMutation,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // UX-114: below this, the fixed chrome (indent + expander +
              // avatar + figure columns + menu) leaves the NAME about two
              // characters wide at depth 3 — and agents open this on a phone in
              // the field. Narrow rows drop the figures onto a second line
              // instead, the pattern the reports surface uses.
              final wide = c.maxWidth >= _wideBreakpoint;
              return InkCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (wide) ...[
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                        child: _TableHeader(l: l, figures: figures),
                      ),
                      const Hairline(),
                    ],
                    _TreeSubtree(
                      node: root,
                      depth: 0,
                      expanded: _expanded,
                      childrenOf: _children,
                      hasMore: _hasMore,
                      loadingNodes: _loadingNodes,
                      onToggle: _toggle,
                      onLoadMore: (id) => _loadChildren(id, more: true),
                      onRefresh: _afterMutation,
                      visitedIds: {root.id},
                      figures: figures,
                      readiness: readiness,
                      wide: wide,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Toolbar: the view toggle + the type pills ───────────────────────────────

class _Toolbar extends StatelessWidget {
  final EntityViewMode mode;
  final ValueChanged<EntityViewMode> onModeChanged;
  final List<EntityType> types;
  final EntityType? selectedType;
  final ValueChanged<EntityType?> onTypeChanged;
  final bool ar;

  const _Toolbar({
    required this.mode,
    required this.onModeChanged,
    required this.types,
    required this.selectedType,
    required this.onTypeChanged,
    required this.ar,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SegmentedButton<EntityViewMode>(
              key: const ValueKey('entity-view-mode'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: EntityViewMode.list,
                  icon: const Icon(Icons.view_list_outlined, size: 16),
                  label: Text(ar ? 'قائمة' : 'List'),
                ),
                ButtonSegment(
                  value: EntityViewMode.tree,
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: Text(ar ? 'شجرة' : 'Tree'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onModeChanged(s.first),
            ),
          ),
          // Filtering a hierarchy by type would cut branches out of the middle
          // and leave an org chart that lies, so the pills belong to list mode.
          if (mode == EntityViewMode.list) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterPill(
                    key: const ValueKey('entity-type-pill-ALL'),
                    label: l.inventoryFilterAll,
                    selected: selectedType == null,
                    onTap: () => onTypeChanged(null),
                  ),
                  for (final t in types) ...[
                    const SizedBox(width: 8),
                    _FilterPill(
                      key: ValueKey('entity-type-pill-${t.name}'),
                      label: localizedEntityTypeLabel(t, l),
                      tint: RoleBadge.colorFor(context, t),
                      selected: selectedType == t,
                      onTap: () => onTypeChanged(selectedType == t ? null : t),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Same pill the System Activity Entities tab uses, so the two surfaces that
/// still list entities filter with one control rather than two lookalikes.
class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tint;
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = tint ?? cs.primary;
    final bg = selected ? accent.withValues(alpha: 0.16) : cs.surfaceContainerHighest;
    final fg = selected ? accent : cs.onSurfaceVariant;
    // UX-119: these sit 8px apart in a horizontal strip and each one re-queries
    // the server, so a mis-tap costs a round trip and a changed result set.
    return MinTapTarget(
      minSize: const Size(0, 48),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: IntesharSpacing.md, vertical: IntesharSpacing.sm),
            child: Text(
              label,
              style: IntesharType.sans(12,
                  color: fg,
                  w: selected ? FontWeight.w800 : IntesharWeight.semibold),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Figures shown beside a name (UX-19) ─────────────────────────────────────

/// The per-row figures and, just as importantly, whether they exist at all.
///
/// Each column is dropped — header and cells together — when its feed was
/// refused or failed. A blank cell means "not known here"; there is deliberately
/// no path that renders a zero the server never confirmed.
class _NetworkFigures {
  final Map<String, num> balances;
  final bool balancesReady;
  final bool soldReady;
  final int soldWindowDays;
  final int? Function(EntitySummaryRow row, [Set<String>? seen]) soldFor;

  const _NetworkFigures({
    required this.balances,
    required this.balancesReady,
    required this.soldReady,
    required this.soldWindowDays,
    required this.soldFor,
  });

  bool get showBalance => balancesReady;
  bool get showSold => soldReady;

  /// Cards on hand. Only HQ and Main Agents ever own a `Product` under
  /// draw-on-print, so below that tier the count is structurally zero and the
  /// cell is left blank rather than reporting an empty warehouse.
  static bool stockApplies(EntityType t) =>
      t == EntityType.INTESHAR || t == EntityType.AGENT1;

  String balanceText(EntitySummaryRow row) {
    final v = balances[row.id];
    return v == null ? '' : Formatters.money(v);
  }

  String stockText(EntitySummaryRow row) =>
      stockApplies(row.type) ? Formatters.money(row.productsCount) : '';

  String soldText(EntitySummaryRow row) {
    final n = soldFor(row, null);
    return n == null ? '' : Formatters.money(n);
  }

  String balanceLabel(bool ar) => ar ? 'الرصيد' : 'Balance';
  String stockLabel(bool ar) => ar ? 'الكروت' : 'Cards';
  String soldLabel(bool ar) =>
      ar ? 'مبيعات $soldWindowDays يوم' : 'Sold ${soldWindowDays}d';

  /// The (label, value) pairs to show for [row], skipping anything blank —
  /// what the narrow layout puts on its second line.
  List<(String, String)> metaFor(EntitySummaryRow row, bool ar) => [
        if (showBalance && balanceText(row).isNotEmpty)
          (balanceLabel(ar), balanceText(row)),
        if (stockText(row).isNotEmpty) (stockLabel(ar), stockText(row)),
        if (showSold && soldText(row).isNotEmpty)
          (soldLabel(ar), soldText(row)),
      ];
}

// ─── Onboarding readiness (UX-02) ────────────────────────────────────────────

/// The two bulk onboarding signals the retired tier directories showed as a chip
/// strip, and whether they were readable at all. A signal with no source renders
/// nothing — the old strip said "not checked", which on a row this dense reads
/// as a verdict.
class _Readiness {
  final Map<String, PosNetworkRow> slots;
  final bool slotsReady;
  final Map<String, int> unpriced;
  final bool pricingReady;

  const _Readiness({
    required this.slots,
    required this.slotsReady,
    required this.unpriced,
    required this.pricingReady,
  });

  bool appliesTo(EntityType t) =>
      t == EntityType.AGENT1 || t == EntityType.AGENT2;
}

// ─── Table header ─────────────────────────────────────────────────────────────

/// Column widths shared by the header and every wide row, so the two cannot
/// drift apart.
const double _colBalance = 82;
const double _colStock = 62;
const double _colSold = 74;

class _TableHeader extends StatelessWidget {
  final AppLocalizations l;
  final _NetworkFigures figures;
  const _TableHeader({required this.l, required this.figures});

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final style = IntesharType.sans(11,
        color: IntesharColors.lichen, w: FontWeight.w700);
    Widget col(double w, String label) => SizedBox(
          width: w,
          child: Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style),
        );
    return Row(
      children: [
        // Expander (20) + gap (8) + avatar (30) + gap (10)
        const SizedBox(width: 68),
        Expanded(child: Text(l.entityTreeColEntity, style: style)),
        // A column exists only while its feed does — see [_NetworkFigures].
        if (figures.showBalance) col(_colBalance, figures.balanceLabel(ar)),
        col(_colStock, figures.stockLabel(ar)),
        if (figures.showSold) col(_colSold, figures.soldLabel(ar)),
        // Actions button placeholder width
        const SizedBox(width: 40),
      ],
    );
  }
}

// ─── Recursive subtree ───────────────────────────────────────────────────────

/// Renders a node and — if expanded — its lazily-fetched children (B-023):
/// the first expand triggers `GET /api/entity/children` for that node; a
/// spinner row shows while the page loads and a "load more" row appears for
/// nodes with more children than one page.
class _TreeSubtree extends ConsumerWidget {
  final EntitySummaryRow node;
  final int depth;
  final Set<String> expanded;
  final Map<String, List<EntitySummaryRow>> childrenOf;
  final Map<String, bool> hasMore;
  final Set<String> loadingNodes;
  final void Function(String id) onToggle;
  final void Function(String id) onLoadMore;
  final VoidCallback onRefresh;
  // Cycle guard: ids already rendered on the current root-to-leaf path.
  final Set<String> visitedIds;
  final _NetworkFigures figures;
  final _Readiness readiness;
  final bool wide;

  const _TreeSubtree({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.childrenOf,
    required this.hasMore,
    required this.loadingNodes,
    required this.onToggle,
    required this.onLoadMore,
    required this.onRefresh,
    required this.visitedIds,
    required this.figures,
    required this.readiness,
    required this.wide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = childrenOf[node.id];
    // Leaf: stores never expand; other tiers rely on the server-computed count
    // (or, once loaded, the actual children list).
    final isLeaf = node.type == EntityType.STORE ||
        (loaded == null ? node.childrenCount == 0 : loaded.isEmpty);
    final isExpanded = expanded.contains(node.id);
    final isLoading = loadingNodes.contains(node.id);

    final rows = <Widget>[];

    // Node row
    rows.add(_EntityRowTile(
      entity: node,
      depth: depth,
      isLeaf: isLeaf,
      isExpanded: isExpanded,
      onToggle: () => onToggle(node.id),
      onRefresh: onRefresh,
      figures: figures,
      readiness: readiness,
      wide: wide,
    ));

    // Children (only when expanded and not a leaf)
    if (!isLeaf && isExpanded) {
      if (loaded == null) {
        // First fetch for this node still in flight.
        rows.add(const Hairline());
        rows.add(Padding(
          padding: EdgeInsetsDirectional.only(start: 44.0 + depth * _indentStep(wide), top: 10, bottom: 10),
          child: const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ));
      } else {
        for (final child in loaded) {
          // Cycle guard
          if (visitedIds.contains(child.id)) continue;
          rows.add(const Hairline());
          rows.add(_TreeSubtree(
            node: child,
            depth: depth + 1,
            expanded: expanded,
            childrenOf: childrenOf,
            hasMore: hasMore,
            loadingNodes: loadingNodes,
            onToggle: onToggle,
            onLoadMore: onLoadMore,
            onRefresh: onRefresh,
            visitedIds: {...visitedIds, child.id},
            figures: figures,
            readiness: readiness,
            wide: wide,
          ));
        }
        if (hasMore[node.id] == true) {
          rows.add(const Hairline());
          rows.add(Padding(
            padding: EdgeInsetsDirectional.only(start: 44.0 + depth * _indentStep(wide)),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton.icon(
                      onPressed: () => onLoadMore(node.id),
                      icon: const Icon(Icons.expand_more, size: 16),
                      label: Text(
                          Localizations.localeOf(context).languageCode == 'ar'
                              ? 'تحميل المزيد'
                              : 'Load more'),
                    ),
            ),
          ));
        }
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

// ─── One row, in either view mode ────────────────────────────────────────────

class _EntityRowTile extends ConsumerWidget {
  final EntitySummaryRow entity;
  final int depth;
  final bool isLeaf;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;
  final _NetworkFigures figures;
  final _Readiness readiness;
  final bool wide;

  /// List mode: the row is flat, tapping it opens the account rather than
  /// expanding it, and the onboarding signals are shown (the tree conveys
  /// structure instead, and would go ragged carrying chips at four depths).
  final bool listMode;

  /// Parent name, shown on list rows so a bare shop name still says where in the
  /// network it sits (the tree conveys that by position; a flat list can't).
  final String breadcrumb;

  const _EntityRowTile({
    required this.entity,
    required this.depth,
    required this.isLeaf,
    required this.isExpanded,
    required this.onToggle,
    required this.onRefresh,
    required this.figures,
    required this.readiness,
    required this.wide,
    this.listMode = false,
    this.breadcrumb = '',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final roleColor = RoleBadge.colorFor(context, entity.type);

    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final startPad = 12.0 + depth * _indentStep(wide);
    final meta = figures.metaFor(entity, ar);
    // In list mode the row IS the directory entry, so tapping it opens the
    // account — the gesture the retired agent cards used. In tree mode the tap
    // still expands, because that is what the chevron promises.
    final canOpen = entityHasDetailPage(entity.type);
    final onTap = listMode
        ? (canOpen
            ? () => openAgentDetail(context, entity.id, entity.label,
                onChanged: onRefresh)
            : null)
        : (isLeaf ? null : onToggle);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: startPad,
          end: 4,
          top: 10,
          bottom: 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Expander chevron or blank spacer
                SizedBox(
                  width: 20,
                  height: 20,
                  child: (isLeaf || listMode)
                      ? null
                      : AnimatedRotation(
                          duration: const Duration(milliseconds: 200),
                          turns: isExpanded ? 0.25 : 0,
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                // Type avatar (30 × 30 rounded square)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(IntesharRadii.xs),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _typeInitial(entity.type),
                    // UX-127/135: was 13px at radius 7, neither of which is on a
                    // scale. One glyph in a 30dp box — the step up cannot overflow.
                    style: IntesharType.sans(
                      IntesharScale.bodyLg,
                      color: roleColor,
                      w: IntesharWeight.black,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Name + type label (+ the figures, folded in below on a phone)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entity.label,
                        style: IntesharType.sans(14,
                            color: cs.onSurface, w: FontWeight.w700),
                        maxLines: wide ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _subtitle(l, ar),
                        style: IntesharType.sans(11, color: IntesharColors.lichen),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // UX-114: on a narrow screen the figure columns move here,
                      // each carrying its own label — an unlabelled number under
                      // a header the phone never renders would be unreadable.
                      if (!wide && meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          [for (final (label, value) in meta) '$label: $value']
                              .join(' · '),
                          style: IntesharType.mono(11, color: cs.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Figures — each column present only while its feed is (UX-19).
                if (wide) ...[
                  if (figures.showBalance)
                    _figureCell(cs, _colBalance, figures.balanceText(entity)),
                  _figureCell(cs, _colStock, figures.stockText(entity)),
                  if (figures.showSold)
                    _figureCell(cs, _colSold, figures.soldText(entity)),
                ],
                // The canonical action set (UX-93) — the same menu, with the same
                // capability gating, that the agent detail page and the System
                // Activity Entities tab render. It renders nothing at all when
                // this viewer has no action on this row.
                EntityRowActionsButton(row: entity, onChanged: onRefresh),
              ],
            ),
            if (listMode) _readinessStrip(context, ref, ar),
          ],
        ),
      ),
    );
  }

  /// `type · parent · users · governorates` — the identity line the retired
  /// agent cards carried, folded into the row that replaced them.
  String _subtitle(AppLocalizations l, bool ar) {
    final locale = ar ? 'ar' : 'en';
    final parts = <String>[localizedEntityTypeLabel(entity.type, l)];
    if (breadcrumb.isNotEmpty) parts.add(breadcrumb);
    if (listMode) {
      if (entity.userCount > 0) {
        parts.add(ar ? '${entity.userCount} مستخدم' : '${entity.userCount} users');
      }
      if (entity.governorates.isNotEmpty) {
        parts.add(entity.governorates
            .map((c) => governorateLabel(c, locale))
            .join('، '));
      }
    }
    return parts.join(' · ');
  }

  /// UX-02, carried over from `/hq/main-agents`: what is still missing before
  /// this agent can sell. Only the signals that have a bulk source, and only
  /// where one was actually readable — a chip is never rendered to say "unknown".
  ///
  /// Gated on the viewer, not just the row: every chip here opens an HQ route,
  /// and a Main Agent's own row appears in its own directory. Rendering the strip
  /// for that viewer would offer a shop-floor agent three destinations the role
  /// guard bounces them straight back out of.
  Widget _readinessStrip(BuildContext context, WidgetRef ref, bool ar) {
    if (!readiness.appliesTo(entity.type)) return const SizedBox.shrink();
    if (!viewerCanManageEntities(ref)) return const SizedBox.shrink();
    final s = AgentStrings.of(context, agentTierOf(entity.type) ?? AgentTier.main);
    final main = entity.type == EntityType.AGENT1;
    final slots = readiness.slots[entity.id];
    final unpriced = readiness.unpriced[entity.id] ?? 0;

    final chips = <Widget>[
      if (main)
        _ReadyChip(
          label: s.setupCards,
          value: entity.productsCount > 0
              ? s.setupCardsSome(entity.productsCount)
              : s.setupCardsNone,
          done: entity.productsCount > 0,
          onTap: () => context.push('/hq/batch'),
        ),
      if (readiness.slotsReady)
        _ReadyChip(
          label: s.setupSlots,
          value: (slots?.total ?? 0) > 0
              ? s.setupSlotsSome(slots?.available ?? 0, slots?.total ?? 0)
              : s.setupSlotsNone,
          done: (slots?.total ?? 0) > 0,
          onTap: () => context.push('/hq/pos-users'),
        ),
      if (main && readiness.pricingReady)
        _ReadyChip(
          label: s.setupPrices,
          value: unpriced > 0 ? s.setupPricesMissing(unpriced) : s.setupPricesOk,
          done: unpriced == 0,
          onTap: () => context.push('/hq/pricing'),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      key: ValueKey('readiness-${entity.id}'),
      // Clears the expander + avatar gutter so the chips line up under the name.
      padding: const EdgeInsetsDirectional.only(start: 68, top: 8, end: 4),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  /// One wide-layout figure. An empty [text] renders as an em-dash: the figure
  /// does not apply to this tier (or is not known), which is a different thing
  /// from a zero and must not read like one.
  Widget _figureCell(ColorScheme cs, double width, String text) => SizedBox(
        width: width,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            text.isEmpty ? '—' : text,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: IntesharType.mono(12,
                color: text.isEmpty ? cs.onSurfaceVariant : cs.onSurface),
          ),
        ),
      );
}

/// One onboarding signal: what it is, where it stands, and a tap that goes to
/// the screen that fixes it.
class _ReadyChip extends StatelessWidget {
  final String label;
  final String value;
  final bool done;
  final VoidCallback onTap;

  const _ReadyChip({
    required this.label,
    required this.value,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = done ? context.status.success : context.status.warn;
    return MinTapTarget(
      minSize: const Size(0, 48),
      child: Material(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IntesharRadii.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: IntesharSpacing.sm2, vertical: IntesharSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(IntesharRadii.sm),
              border: Border.all(color: tone.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.check_circle_outline : Icons.error_outline,
                  size: 15,
                  color: tone,
                ),
                const SizedBox(width: 6),
                // Bounded so a long localized value ellipsizes inside its own
                // chip instead of overflowing the row on a phone.
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
                              color: cs.onSurfaceVariant,
                              w: IntesharWeight.semibold)),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IntesharType.sans(12,
                              color: cs.onSurface, w: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Direction-neutral on purpose: a chevron would point the wrong
                // way in the Arabic layout this app is primarily read in.
                Icon(Icons.open_in_new, size: 14, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
