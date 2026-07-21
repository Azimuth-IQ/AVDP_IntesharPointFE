import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/system_activity/data/system_activity_repository.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/features/system_activity/domain/operation_log.dart';
import 'package:inteshar/features/system_activity/domain/system_overview.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

const double _hPad = 16;

/// Holds the mutable paging state for one server-backed feed. The [fetch]
/// closure reads the page's current filter fields at call time, so changing a
/// filter is just `_reload(feed)`.
class _PagedFeed<T> {
  final Future<Paged<T>> Function(int page) fetch;
  List<T> items = const [];
  int page = 0;
  bool hasMore = false;
  bool loading = true;
  bool loadingMore = false;
  bool started = false;
  Object? error;
  _PagedFeed(this.fetch);
}

// ─── Page ────────────────────────────────────────────────────────────────────

class SystemActivityPage extends ConsumerStatefulWidget {
  const SystemActivityPage({super.key});

  @override
  ConsumerState<SystemActivityPage> createState() => _SystemActivityPageState();
}

class _SystemActivityPageState extends ConsumerState<SystemActivityPage> {
  // KPI strip + tab counts.
  SystemOverview? _overview;
  bool _overviewLoading = true;
  List<UnpricedAgent> _unpriced = const []; // B-060 no-price oversight

  // The four server-paged feeds.
  late final _PagedFeed<OperationLog> _logsFeed;
  late final _PagedFeed<TransactionFeedRow> _txnFeed;
  late final _PagedFeed<EntitySummaryRow> _entityFeed;
  late final _PagedFeed<AdminUserRow> _usersFeed;

  int _tab = 0;

  // Activity filters (server-side).
  String? _level;
  bool _failuresOnly = false;
  final _pathCtrl = TextEditingController();
  Timer? _pathDebounce;

  // Transactions filter (server-side).
  TransactionStatus? _txnStatus;

  // Entities filters (server-side).
  EntityType? _entityType;
  final _entitySearchCtrl = TextEditingController();
  Timer? _entityDebounce;

  // Users filter (server-side).
  final _userSearchCtrl = TextEditingController();
  Timer? _userDebounce;

  SystemActivityRepository _repo() =>
      SystemActivityRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _logsFeed = _PagedFeed<OperationLog>((p) => _repo().logs(
          level: _level,
          success: _failuresOnly ? false : null,
          path: _pathCtrl.text.trim(),
          page: p,
        ));
    _txnFeed = _PagedFeed<TransactionFeedRow>(
        (p) => _repo().transactions(status: _txnStatus?.name, page: p));
    _entityFeed = _PagedFeed<EntitySummaryRow>((p) => _repo().entities(
          type: _entityType?.name,
          search: _entitySearchCtrl.text.trim(),
          page: p,
        ));
    _usersFeed = _PagedFeed<AdminUserRow>(
        (p) => _repo().users(phone: _userSearchCtrl.text.trim(), page: p));

    _loadOverview();
    _reload(_logsFeed); // first tab
  }

  @override
  void dispose() {
    _pathDebounce?.cancel();
    _entityDebounce?.cancel();
    _userDebounce?.cancel();
    _pathCtrl.dispose();
    _entitySearchCtrl.dispose();
    _userSearchCtrl.dispose();
    super.dispose();
  }

  // ── Loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadOverview() async {
    setState(() => _overviewLoading = true);
    try {
      final o = await _repo().overview();
      List<UnpricedAgent> unpriced = const [];
      try {
        unpriced = await PricingRepository(ref.read(apiClientProvider)).unpricedAgents();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _overview = o;
        _unpriced = unpriced;
        _overviewLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // The KPI strip degrades to "—"; the feeds carry their own errors.
      setState(() => _overviewLoading = false);
    }
  }

  Future<void> _reload<T>(_PagedFeed<T> feed) async {
    feed.started = true;
    setState(() {
      feed.loading = true;
      feed.error = null;
    });
    try {
      final res = await feed.fetch(0);
      if (!mounted) return;
      setState(() {
        feed.items = res.items;
        feed.page = 0;
        feed.hasMore = res.hasMore;
        feed.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        feed.error = e;
        feed.loading = false;
      });
    }
  }

  Future<void> _loadMore<T>(_PagedFeed<T> feed) async {
    if (feed.loadingMore || !feed.hasMore) return;
    setState(() => feed.loadingMore = true);
    try {
      final next = feed.page + 1;
      final res = await feed.fetch(next);
      if (!mounted) return;
      setState(() {
        feed.items = [...feed.items, ...res.items];
        feed.page = next;
        feed.hasMore = res.hasMore;
        feed.loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => feed.loadingMore = false);
    }
  }

  void _onTab(int i) {
    setState(() => _tab = i);
    // Lazy-load a feed the first time its tab is opened.
    switch (i) {
      case 1:
        if (!_txnFeed.started) _reload(_txnFeed);
      case 2:
        if (!_entityFeed.started) _reload(_entityFeed);
      case 3:
        if (!_usersFeed.started) _reload(_usersFeed);
    }
  }

  /// This screen is ADMIN-only and the backend serves expired/anonymous tokens
  /// as 403 (not 401), so the global 401 handler can't auto-recover. Offer an
  /// explicit re-login from the forbidden state.
  Future<void> _reauth() async {
    await ref.read(authStateProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  void _refreshVisible() {
    _loadOverview();
    switch (_tab) {
      case 0:
        _reload(_logsFeed);
      case 1:
        _reload(_txnFeed);
      case 2:
        _reload(_entityFeed);
      case 3:
        _reload(_usersFeed);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final o = _overview;

    return MaxWidthBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            eyebrow: l.navSystemActivity,
            title: l.navSystemActivity,
            subtitle: l.sysActSubtitle,
            trailing: IconButton.filledTonal(
              tooltip: l.inventoryRefresh,
              onPressed: _refreshVisible,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ),
          _StatStrip(overview: o, loading: _overviewLoading, l: l),
          if (_unpriced.isNotEmpty) ...[
            const SizedBox(height: 12),
            _UnpricedAgentsCard(rows: _unpriced),
          ],
          const SizedBox(height: 12),
          _TabBar(
            current: _tab,
            onSelect: _onTab,
            items: [
              _TabSpec(Icons.bolt_outlined, l.sysActActivity, _logsFeed.items.length, _logsFeed.hasMore),
              _TabSpec(Icons.swap_horiz, l.navTransactions, o?.txnTotal ?? 0, false),
              _TabSpec(Icons.account_tree_outlined, l.sysActEntities, o?.entityTotal ?? 0, false),
              _TabSpec(Icons.people_alt_outlined, l.sysActUsers, o?.userTotal ?? 0, false),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _buildActivityTab(l),
                _buildTransactionsTab(l),
                _buildEntitiesTab(l),
                _buildUsersTab(l),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Shared list scaffold: spinner / error / empty / list-with-load-more.
  Widget _feedList<T>({
    required _PagedFeed<T> feed,
    required String emptyMessage,
    required Widget Function(T) itemBuilder,
    required Future<void> Function() onRefresh,
    required AppLocalizations l,
  }) {
    if (feed.loading && feed.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.error != null && feed.items.isEmpty) {
      if (_isForbidden(feed.error)) {
        return _NoticeState(
          icon: Icons.lock_outline,
          message: l.sysActAdminOnly,
          actionLabel: l.sysActReauth,
          onAction: _reauth,
        );
      }
      return ErrorState(error: feed.error!, onRetry: () => _reload(feed));
    }
    if (feed.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [SizedBox(height: 360, child: EmptyState(message: emptyMessage))],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(_hPad, 2, _hPad, 32),
        itemCount: feed.items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == feed.items.length) return _loadMoreTile(feed, l);
          return itemBuilder(feed.items[i]);
        },
      ),
    );
  }

  Widget _loadMoreTile<T>(_PagedFeed<T> feed, AppLocalizations l) {
    if (!feed.hasMore) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Center(
        child: feed.loadingMore
            ? const SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
            : OutlinedButton.icon(
                onPressed: () => _loadMore(feed),
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(l.inventoryLoadMore),
              ),
      ),
    );
  }

  Future<void> _refreshWithOverview<T>(_PagedFeed<T> feed) async {
    await Future.wait([_loadOverview(), _reload(feed)]);
  }

  // ── Activity tab ───────────────────────────────────────────────────────────

  Widget _buildActivityTab(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 0, _hPad, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(
                controller: _pathCtrl,
                hint: l.sysActSearchPath,
                onChanged: (_) {
                  setState(() {});
                  _pathDebounce?.cancel();
                  _pathDebounce = Timer(const Duration(milliseconds: 350),
                      () => mounted ? _reload(_logsFeed) : null);
                },
                onClear: () {
                  _pathCtrl.clear();
                  _reload(_logsFeed);
                },
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterPill(
                      label: l.inventoryFilterAll,
                      selected: _level == null && !_failuresOnly,
                      onTap: () => setState(() {
                        _level = null;
                        _failuresOnly = false;
                        _reload(_logsFeed);
                      }),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l.sysActLevelInfo,
                      tint: const Color(0xFF2563EB),
                      selected: _level == 'INFO',
                      onTap: () => _setLevel('INFO'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l.sysActLevelWarn,
                      tint: IntesharColors.saffronDeep,
                      selected: _level == 'WARN',
                      onTap: () => _setLevel('WARN'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l.sysActLevelError,
                      tint: IntesharColors.oxblood,
                      selected: _level == 'ERROR',
                      onTap: () => _setLevel('ERROR'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l.sysActFailuresOnly,
                      tint: IntesharColors.oxblood,
                      icon: Icons.report_gmailerrorred_outlined,
                      selected: _failuresOnly,
                      onTap: () => setState(() {
                        _failuresOnly = !_failuresOnly;
                        _reload(_logsFeed);
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _feedList<OperationLog>(
            feed: _logsFeed,
            l: l,
            emptyMessage: l.sysActNoEvents,
            onRefresh: () => _refreshWithOverview(_logsFeed),
            itemBuilder: (log) => _LogRow(log: log, onTap: () => _showLogDetail(log)),
          ),
        ),
      ],
    );
  }

  void _setLevel(String level) => setState(() {
        _level = _level == level ? null : level;
        _reload(_logsFeed);
      });

  void _showLogDetail(OperationLog row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LogDetailSheet(light: row, future: _repo().logDetail(row.id)),
    );
  }

  // ── Transactions tab ─────────────────────────────────────────────────────────

  Widget _buildTransactionsTab(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 0, _hPad, 10),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  label: l.inventoryFilterAll,
                  selected: _txnStatus == null,
                  onTap: () => setState(() {
                    _txnStatus = null;
                    _reload(_txnFeed);
                  }),
                ),
                for (final s in TransactionStatus.values) ...[
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: _txnStatusLabel(l, s),
                    tint: _txnStatusColor(s),
                    selected: _txnStatus == s,
                    onTap: () => setState(() {
                      _txnStatus = _txnStatus == s ? null : s;
                      _reload(_txnFeed);
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: _feedList<TransactionFeedRow>(
            feed: _txnFeed,
            l: l,
            emptyMessage: l.dashNoTransactions,
            onRefresh: () => _refreshWithOverview(_txnFeed),
            itemBuilder: (row) =>
                _TxnRow(row: row, l: l, onTap: () => _showTxnDetail(row, l)),
          ),
        ),
      ],
    );
  }

  void _showTxnDetail(TransactionFeedRow row, AppLocalizations l) {
    final future = TransactionRepository(ref.read(apiClientProvider)).read(row.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TxnDetailSheet(row: row, future: future, l: l),
    );
  }

  // ── Entities tab ─────────────────────────────────────────────────────────────

  Widget _buildEntitiesTab(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 0, _hPad, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(
                controller: _entitySearchCtrl,
                hint: l.sysActSearchEntities,
                onChanged: (_) {
                  setState(() {});
                  _entityDebounce?.cancel();
                  _entityDebounce = Timer(const Duration(milliseconds: 350),
                      () => mounted ? _reload(_entityFeed) : null);
                },
                onClear: () {
                  _entitySearchCtrl.clear();
                  _reload(_entityFeed);
                },
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterPill(
                      label: l.inventoryFilterAll,
                      selected: _entityType == null,
                      onTap: () => setState(() {
                        _entityType = null;
                        _reload(_entityFeed);
                      }),
                    ),
                    for (final t in EntityType.values) ...[
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: _entityTypeLabel(l, t),
                        tint: RoleBadge.colorFor(context, t),
                        selected: _entityType == t,
                        onTap: () => setState(() {
                          _entityType = _entityType == t ? null : t;
                          _reload(_entityFeed);
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _feedList<EntitySummaryRow>(
            feed: _entityFeed,
            l: l,
            emptyMessage: l.sysActNoEntities,
            onRefresh: () => _refreshWithOverview(_entityFeed),
            itemBuilder: (row) =>
                _EntityRow(row: row, l: l, onTap: () => _showEntityDetail(row, l)),
          ),
        ),
      ],
    );
  }

  void _showEntityDetail(EntitySummaryRow row, AppLocalizations l) {
    final usersFuture = _repo().users(entityId: row.id, size: 200);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntityDetailSheet(row: row, usersFuture: usersFuture, l: l),
    );
  }

  // ── Users tab ────────────────────────────────────────────────────────────────

  Widget _buildUsersTab(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 0, _hPad, 10),
          child: _SearchField(
            controller: _userSearchCtrl,
            hint: l.sysActSearchUsers,
            onChanged: (_) {
              setState(() {});
              _userDebounce?.cancel();
              _userDebounce = Timer(const Duration(milliseconds: 350),
                  () => mounted ? _reload(_usersFeed) : null);
            },
            onClear: () {
              _userSearchCtrl.clear();
              _reload(_usersFeed);
            },
          ),
        ),
        Expanded(
          child: _feedList<AdminUserRow>(
            feed: _usersFeed,
            l: l,
            emptyMessage: l.sysActNoUsers,
            onRefresh: () => _refreshWithOverview(_usersFeed),
            itemBuilder: (row) => _UserRow(row: row, l: l),
          ),
        ),
      ],
    );
  }
}

// ─── Stat strip ────────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final SystemOverview? overview;
  final bool loading;
  final AppLocalizations l;
  const _StatStrip({required this.overview, required this.loading, required this.l});

  @override
  Widget build(BuildContext context) {
    final o = overview;
    String v(int? n) => n == null ? '—' : n.toString();

    final tiles = <Widget>[
      _StatTile(icon: Icons.account_tree_outlined, tint: IntesharColors.saffron, value: v(o?.entityTotal), label: l.sysActEntities),
      _StatTile(icon: Icons.people_alt_outlined, tint: const Color(0xFF2563EB), value: v(o?.userTotal), label: l.sysActUsers),
      _StatTile(icon: Icons.swap_horiz, tint: IntesharColors.sage, value: v(o?.txnTotal), label: l.navTransactions),
      _StatTile(icon: Icons.storefront_outlined, tint: IntesharColors.saffronDeep, value: v(o?.storeCount), label: l.sysActStores),
      _StatTile(icon: Icons.error_outline, tint: IntesharColors.oxblood, value: v(o?.failedTxnCount), label: l.sysActFailed),
      if (o != null && o.hasActivity)
        _StatTile(icon: Icons.warning_amber_rounded, tint: IntesharColors.oxblood, value: v(o.activityErrors), label: l.sysActLevelError),
    ];

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 4, _hPad, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final t in tiles) SizedBox(width: 168, child: t)],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String value;
  final String label;
  const _StatTile({required this.icon, required this.tint, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 14, 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: IntesharType.display(22, color: cs.onSurface, w: FontWeight.w900)),
                const SizedBox(height: 1),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(11, color: IntesharColors.inkSoft, w: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab bar ───────────────────────────────────────────────────────────────────

class _TabSpec {
  final IconData icon;
  final String label;
  final int count;
  final bool approxCount;
  const _TabSpec(this.icon, this.label, this.count, this.approxCount);
}

class _TabBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onSelect;
  final List<_TabSpec> items;
  const _TabBar({required this.current, required this.onSelect, required this.items});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 0, _hPad, 0),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _TabChip(spec: items[i], active: i == current, onTap: () => onSelect(i)),
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final _TabSpec spec;
  final bool active;
  final VoidCallback onTap;
  const _TabChip({required this.spec, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.onSurface : cs.onSurfaceVariant;
    return Material(
      color: active ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(spec.icon, size: 16, color: fg),
              const SizedBox(width: 7),
              Text(spec.label,
                  style: IntesharType.sans(13, color: fg, w: active ? FontWeight.w800 : FontWeight.w600)),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? cs.onSurface.withValues(alpha: 0.12)
                      : cs.onSurfaceVariant.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(spec.approxCount ? '${spec.count}+' : '${spec.count}',
                    style: IntesharType.mono(10, color: fg, w: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Filter pill ─────────────────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? tint;
  final IconData? icon;
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tint,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = tint ?? cs.primary;
    final bg = selected ? accent.withValues(alpha: 0.16) : cs.surfaceContainerHighest;
    final fg = selected ? accent : cs.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
              Text(label,
                  style: IntesharType.sans(12.5, color: fg, w: selected ? FontWeight.w800 : FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Search field ────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear),
      ),
    );
  }
}

// ─── Shared formatting helpers ─────────────────────────────────────────────────

({IconData icon, Color color}) _logVisual(OperationLog log) {
  if (log.isError) return (icon: Icons.error_outline, color: IntesharColors.oxblood);
  if (log.isWarn) return (icon: Icons.warning_amber_rounded, color: IntesharColors.saffronDeep);
  if (!log.success) return (icon: Icons.info_outline, color: const Color(0xFF2563EB));
  return (icon: Icons.check_circle_outline, color: IntesharColors.sage);
}

/// True when an error is an HTTP 403 — the screen + feeds are ADMIN-only, so a
/// non-admin session gets a clean "admin required" notice instead of a raw error.
bool _isForbidden(Object? e) {
  if (e is DioException) {
    if (e.response?.statusCode == 403) return true;
    final inner = e.error;
    if (inner is ApiException) return inner.statusCode == 403;
  }
  if (e is ApiException) return e.statusCode == 403;
  return false;
}

String _fmtCompact(DateTime? d) => d == null ? '—' : DateFormat('MM-dd HH:mm').format(d);
String _fmtFull(DateTime? d) => d == null ? '—' : DateFormat('yyyy-MM-dd HH:mm:ss').format(d);

/// Forces LTR for technical strings (paths, ids, phones, IPs) so they read
/// correctly inside the RTL Arabic layout.
Widget _ltr(Widget child) => Directionality(textDirection: TextDirection.ltr, child: child);

Widget _logStatusPill(OperationLog log) {
  if (log.httpStatus != null) {
    return StampPill(
      label: '${log.httpStatus}',
      color: log.success ? IntesharColors.sage : IntesharColors.oxblood,
      fontSize: 10,
    );
  }
  return StampPill(label: log.level, color: _logVisual(log).color, fontSize: 10);
}

String _logPrimaryLine(OperationLog log) {
  final m = log.method.isNotEmpty ? '${log.method} ' : '';
  if (log.path.isNotEmpty) return '$m${log.path}';
  if (log.action.isNotEmpty) return log.action;
  if (log.errorType.isNotEmpty) return log.errorType;
  return '—';
}

// ─── Activity row ────────────────────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final OperationLog log;
  final VoidCallback onTap;
  const _LogRow({required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _logVisual(log);
    final meta = <String>[
      if (log.surface.isNotEmpty) log.surface else log.source,
      if (log.clientPlatform.isNotEmpty) log.clientPlatform,
      if (log.userPhone.isNotEmpty) log.userPhone,
      _fmtCompact(log.timestamp),
    ].where((p) => p.isNotEmpty).join(' · ');

    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: v.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(v.icon, size: 18, color: v.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ltr(Text(_logPrimaryLine(log),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w600))),
                const SizedBox(height: 4),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(11.5, color: IntesharColors.inkSoft)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _logStatusPill(log),
              if (log.durationMs != null) ...[
                const SizedBox(height: 5),
                _ltr(Text('${log.durationMs}ms',
                    style: IntesharType.mono(10, color: IntesharColors.lichen))),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Log detail sheet (fetches the full document) ──────────────────────────────

class _LogDetailSheet extends StatelessWidget {
  final OperationLog light;
  final Future<OperationLog> future;
  const _LogDetailSheet({required this.light, required this.future});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final v = _logVisual(light);

    return _SheetFrame(
      title: l.sysActDetailTitle,
      titleTrailing: _logStatusPill(light),
      children: [
        Row(
          children: [
            Icon(v.icon, size: 18, color: v.color),
            const SizedBox(width: 8),
            Expanded(
              child: _ltr(Text(_logPrimaryLine(light),
                  style: IntesharType.mono(13, color: cs.onSurface, w: FontWeight.w600))),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<OperationLog>(
          future: future,
          builder: (ctx, snap) {
            final log = snap.data ?? light;
            final loading = snap.connectionState != ConnectionState.done;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._logKv(ctx, l, log),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

List<Widget> _logKv(BuildContext context, AppLocalizations l, OperationLog log) {
  final cs = Theme.of(context).colorScheme;
  return [
    _kv(context, l.sysActFieldTime, _fmtFull(log.timestamp)),
    _kv(context, l.sysActFieldSource, log.source == 'client' ? l.sysActSourceClient : l.sysActSourceServer),
    _kv(context, l.sysActFieldLevel, log.level),
    if (log.httpStatus != null) _kv(context, l.dashColStatus, '${log.httpStatus}'),
    if (log.method.isNotEmpty) _kv(context, l.sysActFieldMethod, log.method, mono: true),
    if (log.path.isNotEmpty) _kv(context, l.sysActFieldPath, log.path, mono: true),
    if (log.action.isNotEmpty) _kv(context, l.sysActFieldAction, log.action, mono: true),
    if (log.durationMs != null) _kv(context, l.sysActFieldDuration, l.sysActDurationMs(log.durationMs!)),
    if (log.userPhone.isNotEmpty) _kv(context, l.sysActFieldUser, log.userPhone, mono: true),
    if (log.userRole.isNotEmpty) _kv(context, l.manageUsersRole, log.userRole),
    if (log.entityId.isNotEmpty) _kv(context, l.sysActFieldEntity, log.entityId, mono: true),
    if (log.surface.isNotEmpty) _kv(context, l.sysActFieldSurface, log.surface),
    if (log.clientPlatform.isNotEmpty) _kv(context, l.sysActFieldPlatform, log.clientPlatform),
    if (log.deviceModel.isNotEmpty || log.osVersion.isNotEmpty)
      _kv(context, l.sysActFieldDevice,
          [log.deviceModel, log.osVersion].where((s) => s.isNotEmpty).join(' · ')),
    if (log.appVersion.isNotEmpty) _kv(context, l.sysActFieldAppVersion, log.appVersion, mono: true),
    if (log.ip.isNotEmpty) _kv(context, l.sysActFieldIp, log.ip, mono: true),
    if (log.correlationId.isNotEmpty) _kv(context, l.sysActFieldCorrelation, log.correlationId, mono: true),
    if (log.errorMessage.isNotEmpty) ...[
      const SizedBox(height: 8),
      _CodeBlock(label: l.sysActFieldError, text: log.errorMessage, tint: cs.error),
    ],
    if (log.stackTrace.isNotEmpty) ...[
      const SizedBox(height: 8),
      _CodeBlock(label: l.sysActFieldStack, text: log.stackTrace),
    ],
  ];
}

// ─── Transaction row + detail ────────────────────────────────────────────────

String _txnStatusLabel(AppLocalizations l, TransactionStatus s) => switch (s) {
      TransactionStatus.COMPLETED => l.txnStatusComplete,
      TransactionStatus.PENDING => l.txnStatusPending,
      TransactionStatus.PROCESSING => l.txnStatusProcessing,
      TransactionStatus.FAILED => l.txnStatusFailed,
    };

Color _txnStatusColor(TransactionStatus s) => switch (s) {
      TransactionStatus.COMPLETED => IntesharColors.sage,
      TransactionStatus.FAILED => IntesharColors.oxblood,
      _ => IntesharColors.saffronDeep,
    };

class _TxnRow extends StatelessWidget {
  final TransactionFeedRow row;
  final AppLocalizations l;
  final VoidCallback onTap;
  const _TxnRow({required this.row, required this.l, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shortId = row.id.length > 8 ? row.id.substring(0, 8) : row.id;
    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row.sourceLabel}  →  ${row.destinationLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(13.5, color: cs.onSurface, w: FontWeight.w700)),
                const SizedBox(height: 3),
                _ltr(Text('#$shortId · ${row.date} ${row.time}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.mono(10.5, color: IntesharColors.inkSoft))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StampPill(label: _txnStatusLabel(l, row.statusEnum), color: _txnStatusColor(row.statusEnum), fontSize: 10),
              const SizedBox(height: 5),
              Text(Formatters.iqd(row.totalAmount),
                  style: IntesharType.mono(12, color: cs.onSurface, w: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TxnDetailSheet extends StatelessWidget {
  final TransactionFeedRow row;
  final Future<AppTransaction> future;
  final AppLocalizations l;
  const _TxnDetailSheet({required this.row, required this.future, required this.l});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SheetFrame(
      title: l.txnsDetailTitle,
      titleTrailing: StampPill(label: _txnStatusLabel(l, row.statusEnum), color: _txnStatusColor(row.statusEnum)),
      children: [
        _kv(context, l.txnsFrom, row.sourceLabel),
        _kv(context, l.txnsTo, row.destinationLabel),
        _kv(context, l.txnsMetaReference, row.id, mono: true),
        _kv(context, l.txnsMetaIssued, '${row.date} ${row.time}', mono: true),
        const SizedBox(height: 12),
        SectionLabel(l.txnsLineItems, padding: const EdgeInsets.only(bottom: 10)),
        FutureBuilder<AppTransaction>(
          future: future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
              );
            }
            if (snap.hasError || snap.data == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.inventoryLoadCodesFailed,
                    style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
              );
            }
            final tx = snap.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final ln in tx.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: _ltr(Text(ln.sku, style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w600)))),
                        Text('×${Formatters.money(ln.amount)}', style: IntesharType.sans(12.5, color: IntesharColors.inkSoft)),
                        const SizedBox(width: 14),
                        Text(Formatters.iqd(ln.lineTotal), style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700)),
                      ],
                    ),
                  ),
                if (tx.processMessage.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _kv(context, l.txnsMetaNote, tx.processMessage),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: IntesharColors.saffron.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(IntesharRadii.md),
          ),
          child: Row(
            children: [
              Text(l.newTxnGrandTotal, style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w700)),
              const Spacer(),
              Text(Formatters.iqd(row.totalAmount), style: IntesharType.display(20, color: cs.onSurface, w: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Entity row + detail ─────────────────────────────────────────────────────

String _entityTypeLabel(AppLocalizations l, EntityType t) => switch (t) {
      EntityType.INTESHAR => l.entityTypeInteshar,
      EntityType.AGENT1 => l.entityTypeAgent1,
      EntityType.AGENT2 => l.entityTypeAgent2,
      EntityType.STORE => l.entityTypeStore,
    };

class _EntityRow extends StatelessWidget {
  final EntitySummaryRow row;
  final AppLocalizations l;
  final VoidCallback onTap;
  const _EntityRow({required this.row, required this.l, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = <String>[
      l.entityTreeChildrenCount(row.childrenCount),
      l.entityTreeProductsCount(row.productsCount),
      l.sysActUsersCount(row.userCount),
    ].join(' · ');

    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                          style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    RoleBadge(type: row.type),
                  ],
                ),
                const SizedBox(height: 4),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(11.5, color: IntesharColors.inkSoft)),
                if (row.parentName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('${l.entityTreeParentLabel}: ${row.parentName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.sans(11, color: IntesharColors.lichen)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

class _EntityDetailSheet extends StatelessWidget {
  final EntitySummaryRow row;
  final Future<Paged<AdminUserRow>> usersFuture;
  final AppLocalizations l;
  const _EntityDetailSheet({required this.row, required this.usersFuture, required this.l});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SheetFrame(
      title: row.label,
      titleTrailing: RoleBadge(type: row.type),
      children: [
        _kv(context, l.entityTreeIdent, row.id, mono: true),
        if (row.parentName.isNotEmpty) _kv(context, l.entityTreeParentLabel, row.parentName),
        if (row.slogan.isNotEmpty) _kv(context, l.entityTreeFieldSlogan, row.slogan),
        _kv(context, l.navChildren, '${row.childrenCount}'),
        _kv(context, l.dashboardProducts, '${row.productsCount}'),
        _kv(context, l.sysActUsers, '${row.userCount}'),
        const SizedBox(height: 12),
        SectionLabel(l.sysActUsers, padding: const EdgeInsets.only(bottom: 10)),
        FutureBuilder<Paged<AdminUserRow>>(
          future: usersFuture,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
              );
            }
            final users = snap.data?.items ?? const [];
            if (users.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(l.manageUsersEmpty, style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final u in users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(child: _ltr(Text(u.phone, style: IntesharType.mono(12.5)))),
                        _roleChip(u.roleEnum, l),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── User row ────────────────────────────────────────────────────────────────

Widget _roleChip(UserRole role, AppLocalizations l) => StampPill(
      label: role == UserRole.ADMIN ? l.sysActRoleAdmin : l.entityTypeUser,
      color: role == UserRole.ADMIN ? IntesharColors.saffronDeep : IntesharColors.inkSoft,
      fontSize: 10,
    );

class _UserRow extends StatelessWidget {
  final AdminUserRow row;
  final AppLocalizations l;
  const _UserRow({required this.row, required this.l});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = row.entityTypeEnum;
    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(Icons.person_outline, size: 20, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ltr(Text(row.phone, style: IntesharType.mono(13, color: cs.onSurface, w: FontWeight.w600))),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(row.entityLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IntesharType.sans(11.5, color: IntesharColors.inkSoft)),
                    ),
                    if (type != null) ...[const SizedBox(width: 6), _MiniTypeTag(type: type)],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _roleChip(row.roleEnum, l),
        ],
      ),
    );
  }
}

class _MiniTypeTag extends StatelessWidget {
  final EntityType type;
  const _MiniTypeTag({required this.type});

  @override
  Widget build(BuildContext context) {
    final c = RoleBadge.colorFor(context, type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(type.label, style: IntesharType.sans(9.5, color: c, w: FontWeight.w700)),
    );
  }
}

// ─── Shared sheet primitives ───────────────────────────────────────────────────

class _SheetFrame extends StatelessWidget {
  final String title;
  final Widget? titleTrailing;
  final List<Widget> children;
  const _SheetFrame({required this.title, this.titleTrailing, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: IntesharType.display(22, color: cs.onSurface, w: FontWeight.w800))),
                  ?titleTrailing,
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 38,
                height: 3,
                decoration: BoxDecoration(color: IntesharColors.saffron, borderRadius: BorderRadius.circular(2)),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _kv(BuildContext context, String label, String value, {bool mono = false}) {
  final cs = Theme.of(context).colorScheme;
  final valueWidget = SelectableText(
    value,
    style: mono
        ? IntesharType.mono(12.5, color: cs.onSurface)
        : IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w500),
  );
  return Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: IntesharType.sans(11.5, color: IntesharColors.inkSoft, w: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Expanded(child: mono ? _ltr(valueWidget) : valueWidget),
      ],
    ),
  );
}

class _NoticeState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _NoticeState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: cs.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: IntesharType.sans(13.5, color: cs.onSurfaceVariant, w: FontWeight.w600),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String label;
  final String text;
  final Color? tint;
  const _CodeBlock({required this.label, required this.text, this.tint});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: IntesharType.sans(11.5, color: tint ?? IntesharColors.inkSoft, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(IntesharRadii.md),
            border: Border.all(color: cs.outline),
          ),
          child: _ltr(SelectableText(text, style: IntesharType.mono(11.5, color: cs.onSurface).copyWith(height: 1.45))),
        ),
      ],
    );
  }
}

/// B-060: an HQ oversight card listing Main Agents holding stock in unpriced
/// categories ("اظهار تنبيه بأي وكيل لم يتم تسعير الكروت له"). Always current.
class _UnpricedAgentsCard extends StatelessWidget {
  const _UnpricedAgentsCard({required this.rows});
  final List<UnpricedAgent> rows;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: IntesharColors.saffron.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: IntesharColors.saffronDeep.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.price_change_outlined, size: 18, color: IntesharColors.saffronDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ar
                  ? '${rows.length} وكيل رئيسي لديه بطاقات غير مسعّرة'
                  : '${rows.length} main agent(s) with unpriced cards',
              style: IntesharType.sans(13.5, color: cs.onSurface, w: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final r in rows)
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text('${r.name.isNotEmpty ? r.name : r.entityId} · ${r.unpricedCount}',
                  style: IntesharType.sans(12, color: cs.onSurface)),
            ),
        ]),
      ]),
    );
  }
}
