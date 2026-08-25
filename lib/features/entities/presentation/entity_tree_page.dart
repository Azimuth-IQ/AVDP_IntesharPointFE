
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/entity_row_actions.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────
//
// UX-93: the viewer gates, the action set and the edit/users sheets used to live
// here, and the two agent directories each had their own near-copies. They now
// live in `entity_row_actions.dart` and every surface renders the same one.

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

// ─── Page ────────────────────────────────────────────────────────────────────

class EntityTreePage extends ConsumerStatefulWidget {
  const EntityTreePage({super.key});

  @override
  ConsumerState<EntityTreePage> createState() => _EntityTreePageState();
}

class _EntityTreePageState extends ConsumerState<EntityTreePage> {
  EntitySummaryRow? _root;
  Object? _error;
  bool _loading = true;

  /// Ids currently expanded in the tree. Root is expanded by default.
  final Set<String> _expanded = {};

  // Lazy children cache (B-023): one `GET /api/entity/children` page per
  // expanded node instead of downloading the whole forest up front.
  final Map<String, List<EntitySummaryRow>> _children = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, int> _page = {};
  final Set<String> _loadingNodes = {};

  // ─── UX-19: the figures beside a name ──────────────────────────────────────
  //
  // The only two data columns were children-count and vouchers-count, and under
  // draw-on-print BOTH are structurally zero below a Main Agent: no AGENT2 and
  // no STORE ever owns a `Product`, and a shop has no children. So a Sub Agent's
  // network page was a list of names beside two columns of zeros — on the one
  // screen they open to ask "how is my network doing".
  //
  // Balance and recent sales are the figures that actually move, and both
  // already exist server-side. They are fetched ONCE per tree load (not per row)
  // and are OMITTED — header and cells together — whenever the server won't hand
  // them over, because a confident zero is worse than a missing column.
  static const int _soldWindowDays = 30;
  static const int _rosterPageSize = 200;
  static const int _rosterMaxPages = 5;

  Map<String, num> _balances = {};
  Map<String, int> _sold = {};
  bool _balancesReady = false;
  bool _soldReady = false;

  // ─── UX-15: find a shop without expanding three levels by hand ─────────────
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  List<EntitySummaryRow> _results = const [];
  bool _searching = false;
  bool _resultsMore = false;
  int _resultsPage = 0;
  Object? _searchError;

  EntityRepository get _repo => EntityRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Reloads the tree.
  ///
  /// [keepOpen] re-fetches the branches the operator had expanded instead of
  /// collapsing everything back to the root. A refresh usually follows an action
  /// taken deep in the tree — deleting a shop three levels down — and dropping
  /// the operator back at the root to re-drill hides the very result they asked
  /// for. Cached rows are always discarded; only the SET of open branches is
  /// kept, so nothing stale survives.
  Future<void> _load({bool keepOpen = false}) async {
    final reopen = keepOpen ? Set<String>.from(_expanded) : <String>{};
    setState(() {
      _loading = true;
      _error = null;
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
      unawaited(_loadMetrics(root.id));
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
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
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

  /// Fetches the two figures the tree shows, for the whole subtree at once.
  ///
  /// Both feeds are section-gated server-side (HQ can hide reporting for an
  /// agent and everything under it), so each is allowed to fail on its own and
  /// simply takes its column with it. Nothing here ever falls back to `0`.
  Future<void> _loadMetrics(String rootId) async {
    if (!mounted) return;
    setState(() {
      _balances = const {};
      _sold = const {};
      _balancesReady = false;
      _soldReady = false;
    });

    // Asking without the capability would only earn a 403 per feed; skip it and
    // show a tree with no figure columns at all.
    final viewer = ref.read(authStateProvider).valueOrNull;
    if (viewer is! AuthAuthenticated ||
        !viewer.can({Capability.VIEW_REPORTS})) {
      return;
    }
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
      // Column omitted. Deliberately silent: the tree itself still works.
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

  // ─── Search (UX-15) ────────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final q = value.trim();
    setState(() {
      if (q.isEmpty) {
        _query = '';
        _results = const [];
        _searchError = null;
        _searching = false;
      }
    });
    if (q.isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 350), _runSearch);
  }

  /// Server-side search over the caller's own subtree (the backend scopes it),
  /// so reaching one shop among hundreds no longer means expanding HQ → Main
  /// Agent → Sub Agent by hand. Results carry the same row actions as the tree.
  Future<void> _runSearch({bool more = false}) async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _query = q;
      _searching = true;
      if (!more) _searchError = null;
    });
    try {
      final next = more ? _resultsPage + 1 : 0;
      final res = await _repo.search(q: q, page: next);
      if (!mounted) return;
      setState(() {
        _results = more ? [..._results, ...res.items] : res.items;
        _resultsPage = next;
        _resultsMore = res.hasMore;
        _searching = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          if (!more) {
            _results = const [];
            _searchError = e;
          }
        });
      }
    }
  }

  /// What to re-fetch after a row action: the result list while searching, the
  /// tree otherwise. Either way the operator keeps the view they acted in.
  Future<void> _afterMutation() async {
    if (_query.isNotEmpty) {
      unawaited(_loadMetrics(_root?.id ?? ''));
      await _runSearch();
    } else {
      await _load(keepOpen: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading && _root == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final root = _root;
    if (root == null) {
      return EmptyState(
        message: l.entityTreeNoChildren,
        actionLabel: l.entityTreeRefresh,
        onAction: _load,
      );
    }

    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final figures = _figures;

    return MaxWidthBox(
      child: RefreshIndicator(
        onRefresh: _afterMutation,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                eyebrow: l.navHierarchy,
                title: l.navHierarchy,
                subtitle: l.entityTreeSubtitle,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: ar
                        ? 'ابحث بالاسم أو المعرّف في شبكتك'
                        : 'Search your network by name or id',
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: ar ? 'مسح' : 'Clear',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: LayoutBuilder(
                  builder: (context, c) {
                    // UX-114: below this, the fixed chrome (indent + expander +
                    // avatar + figure columns + menu) leaves the NAME about two
                    // characters wide at depth 3 — and agents open this on a
                    // phone in the field. Narrow rows drop the figures onto a
                    // second line instead, the pattern the reports surface uses.
                    final wide = c.maxWidth >= _wideBreakpoint;
                    return InkCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _query.isEmpty
                            ? _treeSlivers(l, figures, wide: wide, root: root)
                            : _searchSlivers(l, figures, wide: wide, ar: ar),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Width under which the row folds its figures onto a second line (UX-114).
  static const double _wideBreakpoint = 600;

  List<Widget> _treeSlivers(
    AppLocalizations l,
    _NetworkFigures figures, {
    required bool wide,
    required EntitySummaryRow root,
  }) =>
      [
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
          wide: wide,
        ),
      ];

  List<Widget> _searchSlivers(
    AppLocalizations l,
    _NetworkFigures figures, {
    required bool wide,
    required bool ar,
  }) {
    if (_searching && _results.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_searchError != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: ErrorState(error: _searchError!, onRetry: _runSearch),
        ),
      ];
    }
    if (_results.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Center(
            child: Text(
              ar
                  ? 'لا توجد حسابات مطابقة لـ "$_query"'
                  : 'No accounts match "$_query"',
              textAlign: TextAlign.center,
              style: IntesharType.sans(13, color: IntesharColors.lichen),
            ),
          ),
        ),
      ];
    }
    return [
      if (wide) ...[
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
          child: _TableHeader(l: l, figures: figures),
        ),
        const Hairline(),
      ],
      for (var i = 0; i < _results.length; i++) ...[
        if (i > 0) const Hairline(),
        // Depth 0 and never expandable: a flat hit list is the point — the row
        // still carries the tree's full action menu, which is what made the
        // tree worth reaching in the first place.
        _TreeNode(
          entity: _results[i],
          depth: 0,
          isLeaf: true,
          isExpanded: false,
          onToggle: () {},
          onRefresh: _afterMutation,
          figures: figures,
          wide: wide,
          breadcrumb: _results[i].parentName,
        ),
      ],
      if (_resultsMore) ...[
        const Hairline(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _searching
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton.icon(
                    onPressed: () => _runSearch(more: true),
                    icon: const Icon(Icons.expand_more, size: 16),
                    label: Text(ar ? 'تحميل المزيد' : 'Load more'),
                  ),
          ),
        ),
      ],
    ];
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
    rows.add(_TreeNode(
      entity: node,
      depth: depth,
      isLeaf: isLeaf,
      isExpanded: isExpanded,
      onToggle: () => onToggle(node.id),
      onRefresh: onRefresh,
      figures: figures,
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

// ─── Single tree row ─────────────────────────────────────────────────────────

class _TreeNode extends ConsumerWidget {
  final EntitySummaryRow entity;
  final int depth;
  final bool isLeaf;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;
  final _NetworkFigures figures;
  final bool wide;

  /// Parent name, shown on search hits so a bare shop name still says where in
  /// the network it sits (the tree conveys that by position; a hit list can't).
  final String breadcrumb;

  const _TreeNode({
    required this.entity,
    required this.depth,
    required this.isLeaf,
    required this.isExpanded,
    required this.onToggle,
    required this.onRefresh,
    required this.figures,
    required this.wide,
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

    return InkWell(
      onTap: isLeaf ? null : onToggle,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: startPad,
          end: 4,
          top: 10,
          bottom: 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Expander chevron or blank spacer
            SizedBox(
              width: 20,
              height: 20,
              child: isLeaf
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
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Text(
                _typeInitial(entity.type),
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: roleColor,
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
                    style: IntesharType.sans(13,
                        color: cs.onSurface, w: FontWeight.w700),
                    maxLines: wide ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    breadcrumb.isEmpty
                        ? localizedEntityTypeLabel(entity.type, l)
                        : '${localizedEntityTypeLabel(entity.type, l)} · $breadcrumb',
                    style: IntesharType.sans(11, color: IntesharColors.lichen),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // UX-114: on a narrow screen the figure columns move here,
                  // each carrying its own label — an unlabelled number under a
                  // header the phone never renders would be unreadable.
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
            // capability gating, that the Main/Sub Agent directories and the
            // System Activity Entities tab render. It renders nothing at all
            // when this viewer has no action on this row.
            EntityRowActionsButton(row: entity, onChanged: onRefresh),
          ],
        ),
      ),
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
