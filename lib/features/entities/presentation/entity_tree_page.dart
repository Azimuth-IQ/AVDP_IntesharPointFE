
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_form.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/delete_agent_sheet.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/features/entities/presentation/visible_products_sheet.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
import 'package:inteshar/shared/widgets/color_hex_field.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Inventory drill-in route prefix for the signed-in viewer, or null when the
/// role cannot browse another entity's inventory (only HQ + Distributor can).
String? _inventoryRoutePrefix(WidgetRef ref) {
  final viewer = ref.read(authStateProvider).valueOrNull;
  if (viewer is! AuthAuthenticated) return null;
  return switch (viewer.entity.type) {
    EntityType.INTESHAR => '/hq',
    EntityType.AGENT1 => '/agent1', // Main Agent browses descendant inventory (BRD)
    EntityType.AGENT2 => '/agent2',
    _ => null,
  };
}

/// Whether the signed-in viewer is HQ (INTESHAR). Creating and deleting entities
/// is HQ-only per the BRD (enforced server-side too), so non-HQ viewers don't see
/// those actions.
bool _viewerIsHq(WidgetRef ref) {
  final viewer = ref.read(authStateProvider).valueOrNull;
  return viewer is AuthAuthenticated && viewer.entity.type == EntityType.INTESHAR;
}

/// Whether the viewer may MUTATE entities from this tree: HQ **and** holding
/// [Capability.MANAGE_AGENTS].
///
/// Being HQ is necessary but not sufficient. The nav item that leads here is
/// gated on `VIEW_REPORTS`, so an HQ supervisor holding only that capability
/// reaches this page while the Main/Sub Agent admin pages (`MANAGE_AGENTS`) stay
/// hidden from them. Gating the row menu on entity TYPE alone then handed that
/// same supervisor edit, manage-users, visible-products, add-child and delete —
/// the capability model bypassed by a type check, with the most destructive
/// action in the app as the escape route.
///
/// The server enforces this independently; the point here is not to offer an
/// action the backend will refuse, and above all not to offer destruction to
/// someone the capability model deliberately excluded.
bool _viewerCanManageEntities(WidgetRef ref) {
  final viewer = ref.read(authStateProvider).valueOrNull;
  return viewer is AuthAuthenticated &&
      viewer.entity.type == EntityType.INTESHAR &&
      viewer.can({Capability.MANAGE_AGENTS});
}

String _localizedEntityTypeLabel(EntityType t, AppLocalizations l) {
  switch (t) {
    case EntityType.INTESHAR:
      return l.entityTypeInteshar;
    case EntityType.AGENT1:
      return l.entityTypeAgent1;
    case EntityType.AGENT2:
      return l.entityTypeAgent2;
    case EntityType.STORE:
      return l.entityTypeStore;
  }
}

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

    // Resolved once: every mutating menu item hangs off canManage, and the menu
    // itself is dropped when neither gate lets anything through.
    final canManage = _viewerCanManageEntities(ref);
    final canDrillIn =
        _inventoryRoutePrefix(ref) != null && entity.type.inventoryBacked;

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
                        ? _localizedEntityTypeLabel(entity.type, l)
                        : '${_localizedEntityTypeLabel(entity.type, l)} · $breadcrumb',
                    style: IntesharType.sans(11,
                        color: IntesharColors.lichen),
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
            // Actions menu — omitted entirely when this viewer has nothing to do
            // on this row, rather than left as a button that opens onto nothing.
            if (canManage || canDrillIn)
              PopupMenuButton<String>(
                tooltip: l.entityTreeActions,
                icon: Icon(Icons.more_horiz, size: 18, color: cs.onSurfaceVariant),
                onSelected: (action) =>
                    _handleAction(context, ref, action),
                itemBuilder: (_) => [
                  // Every MUTATING item below is gated on canManage: HQ (BRD: only
                  // the platform admin creates/assigns accounts) AND the
                  // MANAGE_AGENTS capability. Being HQ alone is not enough — see
                  // _viewerCanManageEntities. Enforced server-side; mirrored here so
                  // a viewer without the capability gets a read-only hierarchy and
                  // never hits a 403.
                  if (canManage)
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: Text(l.entityTreeEdit),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (canManage)
                    PopupMenuItem(
                      value: 'manage_users',
                      child: ListTile(
                        leading: const Icon(Icons.manage_accounts_outlined),
                        title: Text(l.entityTreeManageUsers),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  // B-081: HQ picks which voucher definitions this account (and its
                  // whole subtree) can see & sell. Not for the root itself.
                  if (canManage && entity.type != EntityType.INTESHAR)
                    PopupMenuItem(
                      value: 'visible_products',
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(Localizations.localeOf(context).languageCode == 'ar'
                            ? 'المنتجات المتاحة'
                            : 'Visible products'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  // Only offer "View inventory" on nodes that actually hold stock
                  // (HQ→Main Agent). Sub Agents and Stores draw-on-print and hold no
                  // cards, so the drill-in would always be empty (B-068).
                  if (canDrillIn)
                    PopupMenuItem(
                      value: 'view_inventory',
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(l.navInventory),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  // Creating accounts / assigning agents is HQ-only (BRD); enforced
                  // server-side, mirrored here so viewers don't see dead actions.
                  if (canManage && entity.type != EntityType.STORE)
                    PopupMenuItem(
                      value: 'add_child',
                      child: ListTile(
                        leading: const Icon(Icons.add),
                        title: Text(l.entityTreeAddChild),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (canManage)
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        title: Text(l.entityTreeDelete,
                            style: const TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              )
            else
              // Keeps the row aligned with the table header, which reserves the
              // same 40px for the actions column.
              const SizedBox(width: 40),
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

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    if (action == 'edit') {
      await _showEditSheet(context, ref);
    } else if (action == 'manage_users') {
      await _showManageUsersSheet(context, ref);
    } else if (action == 'view_inventory') {
      _viewInventory(context, ref);
    } else if (action == 'visible_products') {
      await showVisibleProductsSheet(context, entityId: entity.id, entityName: entity.name);
    } else if (action == 'add_child') {
      await _addChild(context, ref);
    } else if (action == 'delete') {
      await _confirmDelete(context, ref);
    }
  }

  void _viewInventory(BuildContext context, WidgetRef ref) {
    final prefix = _inventoryRoutePrefix(ref);
    if (prefix == null) return;
    context.push(
      '$prefix/entities/${entity.id}/inventory?name=${Uri.encodeComponent(entity.name)}',
    );
  }

  Future<void> _showEditSheet(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    // The tree rows are light projections — fetch the full document only when
    // an edit actually starts (B-023).
    final Entity full;
    try {
      full = await EntityRepository(ref.read(apiClientProvider)).read(entity.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.entityTreeErrorSaving)));
      }
      return;
    }
    if (!context.mounted) return;

    // UX-03: an agent has ONE editor. This sheet and [AgentForm] both edited the
    // same account with disjoint field sets — the form owned governorates,
    // working hours, KYC and the capability ceiling; this sheet owned slogan,
    // description, low-stock and the bulk limits — and neither mentioned the
    // other. Those five have moved into the form, so Main/Sub Agents open it
    // here too and the whole account is editable from one place.
    //
    // HQ itself and shops have no agent form (a shop is onboarded through the
    // POS quota flow), so they keep this sheet.
    final tier = switch (full.type) {
      EntityType.AGENT1 => AgentTier.main,
      EntityType.AGENT2 => AgentTier.sub,
      EntityType.INTESHAR || EntityType.STORE => null,
    };
    if (tier != null) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => AgentForm(tier: tier, existing: full)),
      );
      if (saved == true) onRefresh();
      return;
    }

    final nameCtrl = TextEditingController(text: full.meta.name);
    final sloganCtrl = TextEditingController(text: full.meta.slogan);
    final descCtrl = TextEditingController(text: full.meta.description);
    final logoCtrl = TextEditingController(text: full.meta.logoUrl);
    final backgroundCtrl =
        TextEditingController(text: full.meta.backgroundUrl);
    final primaryCtrl = TextEditingController(text: full.meta.primaryColor);
    final secondaryCtrl =
        TextEditingController(text: full.meta.secondaryColor);
    final thresholdCtrl = TextEditingController(
        text: full.meta.lowStockThreshold > 0
            ? full.meta.lowStockThreshold.toString()
            : '');
    // B-086: per-request bulk card limit + whether this account may manage limits.
    final bulkCtrl = TextEditingController(
        text: full.meta.maxBulkPrint > 0 ? full.meta.maxBulkPrint.toString() : '');
    var bulkLocked = full.meta.bulkLimitLocked;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EntityFormSheet(
        title: l.entityTreeAmendTitle(
            _localizedEntityTypeLabel(entity.type, l)),
        nameCtrl: nameCtrl,
        sloganCtrl: sloganCtrl,
        descCtrl: descCtrl,
        logoCtrl: logoCtrl,
        backgroundCtrl: backgroundCtrl,
        primaryCtrl: primaryCtrl,
        secondaryCtrl: secondaryCtrl,
        thresholdCtrl: thresholdCtrl,
        bulkCtrl: bulkCtrl,
        // Only HQ may delegate/revoke limit management (server-enforced too).
        showBulkLock: _viewerIsHq(ref),
        bulkLocked: bulkLocked,
        onBulkLockChanged: (v) => bulkLocked = v,
        onSave: () async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);
          final updated = full.copyWith(
            meta: full.meta.copyWith(
              name: nameCtrl.text.trim(),
              slogan: sloganCtrl.text.trim(),
              description: descCtrl.text.trim(),
              logoUrl: logoCtrl.text.trim(),
              backgroundUrl: backgroundCtrl.text.trim(),
              primaryColor: primaryCtrl.text.trim(),
              secondaryColor: secondaryCtrl.text.trim(),
              lowStockThreshold: int.tryParse(thresholdCtrl.text.trim()) ?? 0,
              maxBulkPrint: int.tryParse(bulkCtrl.text.trim()) ?? 0,
              bulkLimitLocked: bulkLocked,
            ),
          );
          await repo.updateWithUsers(updated);
          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  Future<void> _showManageUsersSheet(
      BuildContext context, WidgetRef ref) async {
    // Users live on the full document, not the projected row (B-023).
    final Entity full;
    try {
      full = await EntityRepository(ref.read(apiClientProvider)).read(entity.id);
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ManageUsersSheet(
        entity: full,
        onResetPassword: (phone, newPass) async {
          await EntityRepository(ref.read(apiClientProvider))
              .resetPassword(entity.id, phone, newPass);
        },
        onResetTotp: (phone) async {
          await EntityRepository(ref.read(apiClientProvider)).resetUserTotp(phone);
        },
        onSave: (updatedUsers) async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);

          // Fine-grained diff: avoids the full-entity PUT that clears
          // childrenIds on the backend (EntityHelper.updateEntity bug).
          final originalByPhone = {for (final u in full.users) u.phone: u};
          final updatedByPhone = {for (final u in updatedUsers) u.phone: u};

          // Remove users dropped from the sheet.
          for (final phone in originalByPhone.keys) {
            if (!updatedByPhone.containsKey(phone)) {
              await repo.removeUser(entity.id, phone);
            }
          }

          // Add new users; update existing ones whose role/capabilities changed.
          for (final u in updatedUsers) {
            final orig = originalByPhone[u.phone];
            if (orig == null) {
              // New user — ManageUsersSheet populates u.password from the form.
              await repo.addUser(
                entityId: entity.id,
                phone: u.phone,
                password: u.password,
                role: u.role,
                capabilities: u.capabilities,
              );
            } else if (orig.role != u.role ||
                orig.capabilities.length != u.capabilities.length ||
                !orig.capabilities.containsAll(u.capabilities)) {
              // Role or capabilities changed; password is not re-sent here
              // so the backend does not re-hash an already-hashed value.
              await repo.updateUser(
                phone: u.phone,
                role: u.role,
                capabilities: u.capabilities,
              );
            }
          }

          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  /// Routes "Add child" to the proper validated onboarding form for the child
  /// tier. AGENT1/AGENT2 → the two-step [AgentForm]. POS shops are NOT created
  /// here (B-052): onboarding a POS consumes a quota slot via the نقاط البيع
  /// screen, so the STORE case is intentionally absent.
  Future<void> _addChild(BuildContext context, WidgetRef ref) async {
    final childType = _childType(entity.type);
    if (childType == null) return;

    Widget page;
    switch (childType) {
      case EntityType.AGENT1:
        page = const AgentForm(tier: AgentTier.main);
      case EntityType.AGENT2:
        page = const AgentForm(tier: AgentTier.sub);
      case EntityType.STORE:
      case EntityType.INTESHAR:
        return;
    }

    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => page),
    );
    if (ok == true) onRefresh();
  }

  EntityType? _childType(EntityType parent) {
    return switch (parent) {
      EntityType.INTESHAR => EntityType.AGENT1,
      EntityType.AGENT1 => EntityType.AGENT2,
      // POS shops are quota-onboarded from the نقاط البيع screen, not the tree.
      EntityType.AGENT2 => null,
      EntityType.STORE => null,
    };
  }

  /// Deleting is leaf-only, so this opens the clear-out sheet rather than a
  /// confirm dialog: it shows what is still attached, deletes each item on the
  /// spot (each confirmed with an authenticator code), and unlocks the account
  /// itself once nothing is left. A plain refusal would leave the operator to
  /// work out what is attached and where it lives.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final deleted = await showDeleteAgentSheet(
      context,
      ref,
      entityId: entity.id,
      entityName: entity.label,
    );
    if (deleted) onRefresh();
  }
}

// ─── Slider gallery ──────────────────────────────────────────────────────────


// ─── Entity form sheet ───────────────────────────────────────────────────────

class _EntityFormSheet extends StatefulWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController sloganCtrl;
  final TextEditingController descCtrl;
  final TextEditingController logoCtrl;
  final TextEditingController backgroundCtrl;
  final TextEditingController primaryCtrl;
  final TextEditingController secondaryCtrl;
  final TextEditingController thresholdCtrl;
  final TextEditingController bulkCtrl;
  final bool showBulkLock;
  final bool bulkLocked;
  final ValueChanged<bool> onBulkLockChanged;
  final Future<void> Function() onSave;

  const _EntityFormSheet({
    required this.title,
    required this.nameCtrl,
    required this.sloganCtrl,
    required this.descCtrl,
    required this.logoCtrl,
    required this.backgroundCtrl,
    required this.primaryCtrl,
    required this.secondaryCtrl,
    required this.thresholdCtrl,
    required this.bulkCtrl,
    this.showBulkLock = false,
    this.bulkLocked = true,
    required this.onBulkLockChanged,
    required this.onSave,
  });

  @override
  State<_EntityFormSheet> createState() => _EntityFormSheetState();
}

class _EntityFormSheetState extends State<_EntityFormSheet> {
  bool _saving = false;
  String? _nameError;
  String? _thresholdError;

  /// Validate before persisting: a blank name would leave the entity showing its
  /// raw id everywhere, and a non-numeric/negative threshold is meaningless (B-073).
  bool _validate(bool ar) {
    String? nameErr;
    String? thErr;
    if (widget.nameCtrl.text.trim().isEmpty) {
      nameErr = ar ? 'الاسم مطلوب' : 'Name is required';
    }
    final th = widget.thresholdCtrl.text.trim();
    if (th.isNotEmpty) {
      final n = int.tryParse(th);
      if (n == null || n < 0) thErr = ar ? 'أدخل رقمًا صحيحًا' : 'Enter a valid number';
    }
    setState(() {
      _nameError = nameErr;
      _thresholdError = thErr;
    });
    return nameErr == null && thErr == null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel(l.entityTreeSectionLabel),
            Text(widget.title,
                style: IntesharType.display(28, color: cs.onSurface)),
            const SizedBox(height: 20),

            // ── Core fields ──────────────────────────────────────────────
            TextField(
              controller: widget.nameCtrl,
              decoration: InputDecoration(
                labelText: l.entityTreeFieldName,
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.sloganCtrl,
              decoration:
                  InputDecoration(labelText: l.entityTreeFieldSlogan),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: l.entityTreeFieldDescription),
            ),
            const SizedBox(height: 12),

            // ── New brand fields ─────────────────────────────────────────
            ImageUploadField(
              value: widget.logoCtrl.text.isEmpty ? null : widget.logoCtrl.text,
              // Not the ARB "Logo URL": this is an upload button and a
              // thumbnail, so a URL label sends the operator hunting for a link.
              label: Localizations.localeOf(context).languageCode == 'ar'
                  ? 'الشعار'
                  : 'Logo',
              kind: 'agent-branding',
              onChanged: (u) => setState(() => widget.logoCtrl.text = u),
            ),
            const SizedBox(height: 12),
            ImageUploadField(
              value: widget.backgroundCtrl.text.isEmpty
                  ? null
                  : widget.backgroundCtrl.text,
              label: Localizations.localeOf(context).languageCode == 'ar'
                  ? 'صورة الخلفية'
                  : 'Background Image',
              kind: 'agent-branding',
              onChanged: (u) =>
                  setState(() => widget.backgroundCtrl.text = u),
            ),
            const SizedBox(height: 12),
            ColorHexField(
              controller: widget.primaryCtrl,
              label: l.entityFieldPrimaryColor,
            ),
            const SizedBox(height: 12),
            ColorHexField(
              controller: widget.secondaryCtrl,
              label: l.entityFieldSecondaryColor,
            ),
            const SizedBox(height: 12),
            // B-086: how many cards this account may sell in one bulk request. Blank =
            // inherit. The server resolves the EFFECTIVE value as the minimum over the
            // chain, so this can only ever tighten what an ancestor already allows.
            TextField(
              controller: widget.bulkCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: ar ? 'حد البيع بالجملة (بطاقات/عملية)' : 'Bulk sale limit (cards per sale)',
                hintText: '10',
                helperText: ar
                    ? 'اتركه فارغًا للتوريث. 1 يعطّل البيع بالجملة.'
                    : 'Blank inherits. 1 disables bulk selling.',
              ),
            ),
            // Only HQ may delegate or revoke limit management (server-enforced).
            if (widget.showBulkLock)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: !widget.bulkLocked,
                onChanged: (v) => setState(() => widget.onBulkLockChanged(!v)),
                title: Text(
                  ar ? 'السماح للوكيل بتعديل الحد' : 'Let this agent edit the limit',
                  style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w600),
                ),
                subtitle: Text(
                  ar
                      ? 'عند التعطيل، الإدارة وحدها تحدد الحد لهذا الحساب وكل ما تحته.'
                      : 'When off, only HQ sets the limit for this account and everything under it.',
                  style: IntesharType.sans(11, color: cs.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.entityFieldLowStockThreshold,
                hintText: EntityMeta.defaultLowStockThreshold.toString(),
                helperText: l.entityFieldLowStockThresholdHelp,
                errorText: _thresholdError,
              ),
              onChanged: (_) {
                if (_thresholdError != null) setState(() => _thresholdError = null);
              },
            ),
            const SizedBox(height: 20),

            // ── Action buttons ───────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
                    child: Text(l.entityTreeCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            if (!_validate(ar)) return;
                            setState(() => _saving = true);
                            try {
                              await widget.onSave();
                            } catch (e) {
                              if (mounted) {
                                // ignore: use_build_context_synchronously
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text(l.entityTreeErrorSaving)),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : Text(l.entityTreeSave),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
