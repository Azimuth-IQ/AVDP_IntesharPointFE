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
import 'package:inteshar/features/entities/presentation/entity_row_actions.dart';
import 'package:inteshar/features/system_activity/data/system_activity_repository.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/features/system_activity/domain/log_phrase.dart';
import 'package:inteshar/features/system_activity/domain/operation_log.dart';
import 'package:inteshar/features/system_activity/domain/system_overview.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/min_tap_target.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';
import 'package:inteshar/shared/widgets/sheet_frame.dart';

const double _hPad = 16;

/// Tab indices. `/hq/home` is the HQ landing page, so tab 0 is the health
/// summary — "is anything wrong?" — and the raw request log is a tab, not the
/// front door (UX-16).
const int _tHealth = 0;
const int _tActivity = 1;
const int _tTxn = 2;
const int _tEntity = 3;
const int _tUser = 4;

/// Which KPI tile was tapped. Every tile focuses the feed that explains it
/// (UX-16: the strip used to be six numbers with no click-through).
enum _Kpi { entities, stores, users, transactions, failedTransactions, events, warnings, errors }

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

  int _tab = _tHealth;

  // Activity filters (server-side).
  String? _level;
  bool _failuresOnly = false;
  final _pathCtrl = TextEditingController();
  Timer? _pathDebounce;

  // UX-08: an entity focus for the activity feed, set by tapping a user row, an
  // entity sheet or the entity id in a log detail — the investigation→action hop
  // the oversight screen was missing.
  String? _logEntityId;
  String _logEntityLabel = '';

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
          entityId: _logEntityId,
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

    _loadOverview(); // the health tab is the landing tab; feeds load on demand
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
      case _tActivity:
        if (!_logsFeed.started) _reload(_logsFeed);
      case _tTxn:
        if (!_txnFeed.started) _reload(_txnFeed);
      case _tEntity:
        if (!_entityFeed.started) _reload(_entityFeed);
      case _tUser:
        if (!_usersFeed.started) _reload(_usersFeed);
    }
  }

  /// A KPI tile is a question; this is its answer. Every tile switches to the
  /// feed that explains the number AND applies the filter the number describes,
  /// so "Failed: 5" lands on those five rows rather than on all 18,432 (UX-16).
  void _focusKpi(_Kpi k) {
    switch (k) {
      case _Kpi.entities:
        _entityType = null;
        _entitySearchCtrl.clear();
        _go(_tEntity, _entityFeed);
      case _Kpi.stores:
        _entityType = EntityType.STORE;
        _entitySearchCtrl.clear();
        _go(_tEntity, _entityFeed);
      case _Kpi.users:
        _userSearchCtrl.clear();
        _go(_tUser, _usersFeed);
      case _Kpi.transactions:
        _txnStatus = null;
        _go(_tTxn, _txnFeed);
      case _Kpi.failedTransactions:
        _txnStatus = TransactionStatus.FAILED;
        _go(_tTxn, _txnFeed);
      case _Kpi.events:
        _clearActivityFilters();
        _go(_tActivity, _logsFeed);
      case _Kpi.warnings:
        _clearActivityFilters();
        _level = 'WARN';
        _go(_tActivity, _logsFeed);
      case _Kpi.errors:
        _clearActivityFilters();
        _level = 'ERROR';
        _go(_tActivity, _logsFeed);
    }
  }

  /// Switch to [tab] and refetch [feed] with the filters just applied. Marks the
  /// feed started first so `_onTab`'s lazy load doesn't fire the same request a
  /// second time.
  void _go<T>(int tab, _PagedFeed<T> feed) {
    feed.started = true;
    _onTab(tab);
    _reload(feed);
  }

  void _clearActivityFilters() {
    _level = null;
    _failuresOnly = false;
    _pathCtrl.clear();
    _logEntityId = null;
    _logEntityLabel = '';
  }

  /// UX-08: jump from a user / entity / log row to that account's own activity.
  void _focusEntityActivity(String entityId, String label) {
    if (entityId.isEmpty) return;
    setState(() {
      _clearActivityFilters();
      _logEntityId = entityId;
      _logEntityLabel = label.isNotEmpty ? label : entityId;
      _tab = _tActivity;
    });
    _logsFeed.started = true;
    _reload(_logsFeed);
  }

  /// UX-08: jump from a user row (or an unpriced-agent chip) to the entity it
  /// names, with the entities feed searched down to it.
  void _focusEntitySearch(String label) {
    if (label.isEmpty) return;
    setState(() {
      _entityType = null;
      _entitySearchCtrl.text = label;
      _tab = _tEntity;
    });
    _entityFeed.started = true;
    _reload(_entityFeed);
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
      case _tActivity:
        _reload(_logsFeed);
      case _tTxn:
        _reload(_txnFeed);
      case _tEntity:
        _reload(_entityFeed);
      case _tUser:
        _reload(_usersFeed);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  bool get _activityFiltered =>
      _level != null ||
      _failuresOnly ||
      _pathCtrl.text.trim().isNotEmpty ||
      _logEntityId != null;

  /// UX-38: the four badges used to mean two different things — Activity counted
  /// the rows you happened to have paged in, the rest were server totals — and
  /// none of them noticed the active filter, so twelve visible STORE cards sat
  /// under a badge reading 412.
  ///
  /// One rule now: show the SERVER total when the overview can answer the
  /// current filter exactly, otherwise show what is loaded, marked `+` while
  /// more pages exist. Every badge carries a tooltip saying which it is.
  _TabSpec _badge<T>({
    required IconData icon,
    required String label,
    required _PagedFeed<T> feed,
    required bool filtered,
    int? serverTotal,
    required bool ar,
  }) {
    if (!filtered && serverTotal != null) {
      return _TabSpec(icon, label, serverTotal, false,
          hint: ar ? 'الإجمالي على الخادم' : 'total on the server');
    }
    if (serverTotal != null) {
      return _TabSpec(icon, label, serverTotal, false,
          hint: ar ? 'المطابق للفلتر الحالي' : 'matching the current filter');
    }
    return _TabSpec(icon, label, feed.items.length, feed.hasMore,
        hint: ar
            ? 'المحمَّل حتى الآن${feed.hasMore ? ' — هناك المزيد' : ''}'
            : 'loaded so far${feed.hasMore ? ' — more exist' : ''}');
  }

  /// Everything currently wrong, worst first. Empty = the all-clear state.
  List<_Exception> _exceptions(bool ar) {
    final o = _overview;
    final out = <_Exception>[];
    if (o == null) return out;
    final failed = o.failedTxnCount;
    if (failed > 0) {
      out.add(_Exception(
        icon: Icons.error_outline,
        color: context.status.danger,
        title: ar
            ? '$failed معاملة فاشلة'
            : '$failed failed transaction${failed == 1 ? '' : 's'}',
        subtitle: ar ? 'الإجمالي — كل الفترات' : 'all time',
        onTap: () => _focusKpi(_Kpi.failedTransactions),
      ));
    }
    final errors = o.activityErrors ?? 0;
    if (errors > 0) {
      out.add(_Exception(
        icon: Icons.report_gmailerrorred_outlined,
        color: context.status.danger,
        title: ar ? '$errors خطأ في السجل' : '$errors error${errors == 1 ? '' : 's'} in the log',
        subtitle: _windowLabel(o.activityWindowHours, ar),
        onTap: () => _focusKpi(_Kpi.errors),
      ));
    }
    if (_unpriced.isNotEmpty) {
      out.add(_Exception(
        icon: Icons.price_change_outlined,
        color: context.status.warn,
        title: ar
            ? '${_unpriced.length} وكيل رئيسي لديه بطاقات غير مسعّرة'
            : '${_unpriced.length} main agent(s) with unpriced cards',
        subtitle: ar
            ? 'البطاقات غير المسعّرة لا تُباع بالسعر الصحيح'
            : 'unpriced cards do not sell at the right price',
        onTap: null, // the card below lists them, each agent tappable
      ));
    }
    final warns = o.activityWarnings ?? 0;
    if (warns > 0) {
      out.add(_Exception(
        icon: Icons.warning_amber_rounded,
        color: context.status.warn,
        title: ar ? '$warns تحذير' : '$warns warning${warns == 1 ? '' : 's'}',
        subtitle: _windowLabel(o.activityWindowHours, ar),
        onTap: () => _focusKpi(_Kpi.warnings),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final o = _overview;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final exceptions = _exceptions(ar);

    // A status filter the overview can answer exactly; an empty byStatus map
    // (an older backend) falls back to the loaded count rather than lying "0".
    final txnTotal = _txnStatus == null
        ? o?.txnTotal
        : (o == null || o.txnByStatus.isEmpty ? null : (o.txnByStatus[_txnStatus!.name] ?? 0));
    final entitySearching = _entitySearchCtrl.text.trim().isNotEmpty;
    final entityTotal = entitySearching
        ? null
        : _entityType == null
            ? o?.entityTotal
            : (o == null || o.entityByType.isEmpty ? null : (o.entityByType[_entityType!.name] ?? 0));
    final userTotal = _userSearchCtrl.text.trim().isNotEmpty ? null : o?.userTotal;

    // UX-13: five paged feeds of logs, transactions, entities and users —
    // scanned and compared down a column, never read as prose. The prose cap
    // was throwing away ~360dp of a 1080p console on the one screen whose job
    // is to show a lot of rows at once.
    return MaxWidthBox.wide(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            eyebrow: l.navSystemActivity,
            title: l.navSystemActivity,
            // UX-105: this screen and Reports both sit in Oversight and both
            // show transfers, entities and users, and neither said which to
            // open. The division is: ACTIVITY answers "what just happened" —
            // individual events, as they land; REPORTS answers "how much, over
            // a period" — totals you can export. The subtitle states the first
            // half; `_reportsCrossLink` names the second and links to it.
            subtitle: ar
                ? 'ما حدث للتو — الأحداث والمعاملات والكيانات والمستخدمون، حدثاً بحدث.'
                : 'What just happened — events, transactions, entities and users, one at a time.',
            trailing: IconButton.filledTonal(
              tooltip: l.inventoryRefresh,
              onPressed: _refreshVisible,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ),
          _StatStrip(
            overview: o,
            loading: _overviewLoading,
            l: l,
            onFocus: _focusKpi,
          ),
          const SizedBox(height: 12),
          _TabBar(
            current: _tab,
            onSelect: _onTab,
            items: [
              _TabSpec(
                exceptions.isEmpty ? Icons.check_circle_outline : Icons.health_and_safety_outlined,
                ar ? 'الحالة' : 'Health',
                exceptions.length,
                false,
                hint: ar ? 'أمور تحتاج إلى إجراء' : 'things needing action',
              ),
              _badge(
                icon: Icons.bolt_outlined,
                label: l.sysActActivity,
                feed: _logsFeed,
                filtered: _activityFiltered,
                ar: ar,
              ),
              _badge(
                icon: Icons.swap_horiz,
                label: l.navTransactions,
                feed: _txnFeed,
                filtered: _txnStatus != null,
                serverTotal: txnTotal,
                ar: ar,
              ),
              _badge(
                icon: Icons.account_tree_outlined,
                label: l.sysActEntities,
                feed: _entityFeed,
                filtered: _entityType != null || entitySearching,
                serverTotal: entityTotal,
                ar: ar,
              ),
              _badge(
                icon: Icons.people_alt_outlined,
                label: l.sysActUsers,
                feed: _usersFeed,
                filtered: userTotal == null,
                serverTotal: userTotal,
                ar: ar,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _buildHealthTab(l, ar, exceptions),
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

  // ── Health tab (the landing tab) ────────────────────────────────────────────

  Widget _buildHealthTab(AppLocalizations l, bool ar, List<_Exception> exceptions) {
    return RefreshIndicator(
      onRefresh: _loadOverview,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(_hPad, 2, _hPad, 32),
        children: [
          if (_overviewLoading && _overview == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          // Never claim "all clear" on the strength of a load that failed — the
          // KPI payload is the only thing that knows whether anything is wrong.
          else if (_overview == null)
            _NoticeState(
              icon: Icons.cloud_off_outlined,
              message: ar
                  ? 'تعذّر تحميل حالة النظام.'
                  : "Couldn't load the system health summary.",
              actionLabel: l.inventoryRefresh,
              onAction: _loadOverview,
            )
          else if (exceptions.isEmpty)
            _AllClearCard(ar: ar, windowLabel: _windowLabel(_overview?.activityWindowHours, ar))
          else
            _ExceptionsCard(rows: exceptions, ar: ar),
          if (_unpriced.isNotEmpty) ...[
            const SizedBox(height: 12),
            _UnpricedAgentsCard(rows: _unpriced, onTapAgent: _focusEntitySearch),
          ],
          const SizedBox(height: 12),
          _HealthHint(ar: ar),
          const SizedBox(height: 16),
          // UX-105: the other half of the Oversight pair, named and linked
          // rather than left to be discovered by opening both and comparing.
          _SiblingSectionLink(
            icon: Icons.summarize_outlined,
            title: ar ? 'التقارير' : 'Reports',
            body: ar
                ? 'المجاميع على مدة زمنية — الأرصدة والتحويلات والمبيعات والمخزون، قابلة للتصدير. هذه الشاشة تعرض الأحداث المفردة؛ التقارير تجمعها.'
                : 'Totals over a period — balances, transfers, sales and stock, exportable. This screen shows individual events; Reports adds them up.',
            onTap: () => context.go('/hq/reports'),
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
              // UX-08: the account this feed is scoped to, and the way back out.
              if (_logEntityId != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: InputChip(
                    avatar: const Icon(Icons.person_search_outlined, size: 16),
                    label: Text(
                      Localizations.localeOf(context).languageCode == 'ar'
                          ? 'نشاط: $_logEntityLabel'
                          : 'Activity of: $_logEntityLabel',
                      style: IntesharType.sans(12),
                    ),
                    onDeleted: () {
                      setState(() {
                        _logEntityId = null;
                        _logEntityLabel = '';
                      });
                      _reload(_logsFeed);
                    },
                  ),
                ),
              ],
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
                      tint: context.status.inFlight,
                      selected: _level == 'INFO',
                      onTap: () => _setLevel('INFO'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l.sysActLevelWarn,
                      tint: context.tones.brandInk,
                      selected: _level == 'WARN',
                      onTap: () => _setLevel('WARN'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l.sysActLevelError,
                      tint: context.status.danger,
                      selected: _level == 'ERROR',
                      onTap: () => _setLevel('ERROR'),
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: l.sysActFailuresOnly,
                      tint: context.status.danger,
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
      builder: (sheetCtx) => _LogDetailSheet(
        light: row,
        future: _repo().logDetail(row.id),
        // UX-08: a monospace entity id is a dead end. Tapping it scopes the feed
        // to that account.
        onEntity: (id) {
          Navigator.pop(sheetCtx);
          _focusEntityActivity(id, id);
        },
      ),
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
                    tint: _txnStatusColor(context, s),
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
        // UX-15: this tab and the network directory both list entities, and
        // saying which is for what — here, where the reader already is — is the
        // whole reason "where do I change X?" now has one answer. Oversight
        // answers "what is this account and what has it been doing"; the
        // directory is where it is administered.
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 0, _hPad, 10),
          child: _SiblingSectionLink(
            icon: Icons.account_tree_outlined,
            title: l.navHierarchy,
            body: Localizations.localeOf(context).languageCode == 'ar'
                ? 'دليل الشبكة — نفس الحسابات كقائمة أو شجرة، مع الإنشاء والتعديل والحذف. هذه الشاشة للمتابعة؛ الإدارة تتم هناك.'
                : 'The network directory — the same accounts as a list or a tree, with create, edit and delete. This screen is for watching; that is where accounts are administered.',
            onTap: () => context.go('/hq/entities'),
          ),
        ),
        Expanded(
          child: _feedList<EntitySummaryRow>(
            feed: _entityFeed,
            l: l,
            emptyMessage: l.sysActNoEntities,
            onRefresh: () => _refreshWithOverview(_entityFeed),
            itemBuilder: (row) =>
                _EntityRow(
                  row: row,
                  l: l,
                  onTap: () => _showEntityDetail(row, l),
                  onChanged: () => _refreshWithOverview(_entityFeed),
                ),
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
      builder: (sheetCtx) => _EntityDetailSheet(
        row: row,
        usersFuture: usersFuture,
        l: l,
        // UX-08: a read-only sheet ends the investigation. This continues it.
        onViewActivity: () {
          Navigator.pop(sheetCtx);
          _focusEntityActivity(row.id, row.label);
        },
        // UX-93: and this leaves oversight for the one place that account is
        // actually administered, instead of naming a screen and stopping.
        onOpenAgent: entityHasDetailPage(row.type)
            ? () {
                Navigator.pop(sheetCtx);
                openAgentDetail(context, row.id, row.label,
                    onChanged: () => _refreshWithOverview(_entityFeed));
              }
            : null,
      ),
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
            itemBuilder: (row) =>
                _UserRow(row: row, l: l, onTap: () => _showUserActions(row, l)),
          ),
        ),
      ],
    );
  }

  /// UX-08: a user row used to be a dead end — a phone number and a role, with
  /// the shop it belongs to spelled out but unreachable. Two hops out of it now.
  void _showUserActions(AdminUserRow row, AppLocalizations l) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => _SheetFrame(
        title: row.phone,
        titleTrailing: _roleChip(sheetCtx, row.roleEnum, l),
        children: [
          _kv(sheetCtx, l.sysActFieldUser, row.phone, mono: true),
          _kv(sheetCtx, l.manageUsersRole, row.role),
          _kv(sheetCtx, l.sysActFieldEntity, row.entityLabel),
          if (row.entityType.isNotEmpty) _kv(sheetCtx, l.sysActEntities, row.entityType),
          const SizedBox(height: 6),
          if (row.entityId.isNotEmpty)
            Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  _focusEntityActivity(row.entityId, row.entityLabel);
                },
                icon: const Icon(Icons.bolt_outlined, size: 18),
                label: Text(ar ? 'نشاط هذا الحساب' : "This account's activity"),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetCtx);
                  _focusEntitySearch(row.entityLabel);
                },
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: Text(ar ? 'فتح الحساب' : 'Open the account'),
              ),
            ]),
        ],
      ),
    );
  }
}

// ─── Health tab pieces (UX-16) ─────────────────────────────────────────────────

String _windowLabel(int? hours, bool ar) {
  if (hours == null || hours <= 0) return ar ? 'نافذة السجل' : 'log window';
  return ar ? 'آخر $hours ساعة' : 'last ${hours}h';
}

class _Exception {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _Exception({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
}

/// The state the landing page never had: nothing is wrong, and it says so.
class _AllClearCard extends StatelessWidget {
  final bool ar;
  final String windowLabel;
  const _AllClearCard({required this.ar, required this.windowLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(IntesharSpacing.lg),
      decoration: BoxDecoration(
        color: context.status.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: context.status.success.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.status.success.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(21),
          ),
          child: Icon(Icons.check_circle_outline_rounded, size: 22, color: context.status.success),
        ),
        const SizedBox(width: IntesharSpacing.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ar ? 'كل شيء يعمل بشكل سليم' : 'Everything is running clean',
                style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              ar
                  ? 'لا توجد معاملات فاشلة ولا أخطاء في $windowLabel.'
                  : 'No failed transactions and no errors in the $windowLabel.',
              style: IntesharType.sans(12, color: cs.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The ranked exceptions, worst first — each one a way into the rows behind it.
class _ExceptionsCard extends StatelessWidget {
  final List<_Exception> rows;
  final bool ar;
  const _ExceptionsCard({required this.rows, required this.ar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              IntesharSpacing.lg, IntesharSpacing.md, IntesharSpacing.lg, IntesharSpacing.md),
          child: Text(
            ar ? 'يحتاج إلى إجراء' : 'Needs your attention',
            style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w800),
          ),
        ),
        const Hairline(),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Hairline(),
          InkWell(
            onTap: rows[i].onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  IntesharSpacing.lg, IntesharSpacing.md, IntesharSpacing.md, IntesharSpacing.md),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rows[i].color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(rows[i].icon, size: 18, color: rows[i].color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(rows[i].title,
                        style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(rows[i].subtitle,
                        style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
                  ]),
                ),
                if (rows[i].onTap != null)
                  Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Says where the raw feed went — the log used to BE this screen, so an admin
/// who knew it by sight needs one line telling them it is a tab now.
class _HealthHint extends StatelessWidget {
  final bool ar;
  const _HealthHint({required this.ar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(Icons.info_outline, size: 15, color: cs.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          ar
              ? 'الأرقام أعلاه قابلة للنقر: كل بطاقة تفتح القائمة التي تشرحها. السجل الكامل في تبويب "النشاط".'
              : 'The numbers above are tappable — each opens the list behind it. The full request log is in the Activity tab.',
          style: IntesharType.sans(12, color: cs.onSurfaceVariant),
        ),
      ),
    ]);
  }
}

/// UX-105: a link to the OTHER Oversight screen, with the division of labour
/// spelled out on it.
///
/// Reports and System Activity answer different questions over largely the same
/// data (transfers, entities and users appear on both), and neither said which
/// to open — so the same fact was looked up in two places on two different
/// bases. Stating the split where the reader already is beats renaming a nav
/// item they have already learned.
class _SiblingSectionLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  const _SiblingSectionLink({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      bordered: true,
      elevated: false,
      onTap: onTap,
      density: CardDensity.dense,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: context.tones.brandInk),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: IntesharType.sans(14,
                    color: cs.onSurface, w: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(body,
                style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
      ]),
    );
  }
}

// ─── Stat strip ────────────────────────────────────────────────────────────────

/// UX-37: five of these tiles are all-time totals and the sixth was windowed,
/// side by side with nothing saying so — "Errors 4" next to "Transactions
/// 18,432" reads as the same period. Every tile now states its period, and the
/// window's own numbers (events / warnings), which were parsed off the payload
/// and rendered nowhere, are on screen. Values use the app-wide thousands
/// grouping instead of a bare `toString()`.
class _StatStrip extends StatelessWidget {
  final SystemOverview? overview;
  final bool loading;
  final AppLocalizations l;
  final void Function(_Kpi) onFocus;
  const _StatStrip({
    required this.overview,
    required this.loading,
    required this.l,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    String v(int? n) => n == null ? '—' : Formatters.money(n);
    final allTime = ar ? 'الإجمالي' : 'all time';
    final window = _windowLabel(o?.activityWindowHours, ar);

    final tiles = <Widget>[
      _StatTile(
        icon: Icons.account_tree_outlined,
        tint: context.tones.brand,
        value: v(o?.entityTotal),
        label: l.sysActEntities,
        period: allTime,
        onTap: () => onFocus(_Kpi.entities),
      ),
      _StatTile(
        icon: Icons.people_alt_outlined,
        tint: context.status.inFlight,
        value: v(o?.userTotal),
        label: l.sysActUsers,
        period: allTime,
        onTap: () => onFocus(_Kpi.users),
      ),
      _StatTile(
        icon: Icons.swap_horiz,
        tint: context.status.success,
        value: v(o?.txnTotal),
        label: l.navTransactions,
        period: allTime,
        onTap: () => onFocus(_Kpi.transactions),
      ),
      _StatTile(
        icon: Icons.storefront_outlined,
        tint: context.tones.brandInk,
        value: v(o?.storeCount),
        label: l.sysActStores,
        period: allTime,
        onTap: () => onFocus(_Kpi.stores),
      ),
      _StatTile(
        icon: Icons.error_outline,
        tint: context.status.danger,
        value: v(o?.failedTxnCount),
        // "Failed" alone said nothing about WHAT failed.
        label: ar ? 'معاملات فاشلة' : 'Failed transactions',
        period: allTime,
        onTap: () => onFocus(_Kpi.failedTransactions),
      ),
      if (o != null && o.hasActivity) ...[
        _StatTile(
          icon: Icons.bolt_outlined,
          tint: context.status.inFlight,
          value: v(o.activityEvents),
          label: ar ? 'أحداث' : 'Events',
          period: window,
          onTap: () => onFocus(_Kpi.events),
        ),
        _StatTile(
          icon: Icons.warning_amber_rounded,
          tint: context.status.warn,
          value: v(o.activityWarnings),
          label: l.sysActLevelWarn,
          period: window,
          onTap: () => onFocus(_Kpi.warnings),
        ),
        _StatTile(
          icon: Icons.report_gmailerrorred_outlined,
          tint: context.status.danger,
          value: v(o.activityErrors),
          label: l.sysActLevelError,
          period: window,
          onTap: () => onFocus(_Kpi.errors),
        ),
      ],
    ];

    return LayoutBuilder(builder: (ctx, c) {
      // Three windowed tiles joined the five all-time ones, which on a phone
      // would have been four stacked rows of KPI above the feed. Narrow widths
      // scroll the strip sideways instead — the same pattern as the filter
      // pills — so the list below keeps its room.
      if (c.maxWidth < 560) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 4, _hPad, 0),
          child: Row(children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              SizedBox(width: 176, child: tiles[i]),
            ],
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(_hPad, 4, _hPad, 0),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final t in tiles) SizedBox(width: 176, child: t)],
        ),
      );
    });
  }
}

/// UX-130: deliberately **not** a [FigureBlock].
///
/// FigureBlock is a figure on paper — a dot, a label, a numeral, an optional
/// note, stacked, inert. This is a horizontal navigation control: a 38dp tinted
/// icon square that carries the KPI's semantic colour, a numeral, a label, a
/// *period* line ("all time" vs "last 24h" — the thing that stops a windowed
/// count reading like an all-time one), and an `onTap` that focuses the feed
/// below on that KPI. Four of those six have no FigureBlock equivalent, and
/// adding them would turn the shared widget into a kitchen sink for the sake of
/// one caller. The tile keeps its own class; only its type/spacing tokens were
/// brought onto the scale.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String value;
  final String label;

  /// The period the number covers — the thing whose absence made a windowed
  /// count sit beside five all-time counts and read the same (UX-37).
  final String period;
  final VoidCallback? onTap;
  const _StatTile({
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    required this.period,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      density: CardDensity.dense,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(IntesharRadii.sm),
            ),
            child: Icon(icon, size: 20, color: tint),
          ),
          const SizedBox(width: IntesharSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // UX-127: was an off-scale 22. The figure shares a 176dp tile
                // with a 38dp icon square, so it snaps DOWN to the 20 step —
                // `IntesharScale.snap` would tie upward to 24 and a
                // money-formatted count has ~98dp of column to live in.
                Text(value,
                    style: IntesharType.display(IntesharScale.titleLg,
                        color: cs.onSurface, w: IntesharWeight.black)),
                const SizedBox(height: 1),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharText.caption(color: context.status.neutral)),
                const SizedBox(height: 2),
                Text(period,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharText.caption(
                        color: cs.onSurfaceVariant, w: IntesharWeight.regular)),
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

  /// What the badge is counting — a server total, the filtered total, or just
  /// the rows paged in so far (UX-38).
  final String hint;
  const _TabSpec(this.icon, this.label, this.count, this.approxCount, {this.hint = ''});
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
    // UX-119: the page's primary navigation, hand-built from a raw InkWell — so
    // it shipped whatever height the padding happened to give it (~37dp) with
    // none of the `MaterialTapTargetSize.padded` floor a real chip would carry.
    // MinTapTarget floors the HIT box at 48 without repainting the pill, so the
    // strip keeps its slim look.
    return MinTapTarget(
      minSize: const Size(0, 48),
      child: Material(
        color: active ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: IntesharSpacing.md, vertical: IntesharSpacing.sm2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(spec.icon, size: 16, color: fg),
                const SizedBox(width: 7),
                Text(spec.label,
                    style: IntesharType.sans(14,
                        color: fg, w: active ? FontWeight.w800 : IntesharWeight.semibold)),
                const SizedBox(width: 7),
                Tooltip(
                  message: spec.hint,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: active
                          ? cs.onSurface.withValues(alpha: 0.12)
                          : cs.onSurfaceVariant.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                        spec.approxCount
                            ? '${Formatters.money(spec.count)}+'
                            : Formatters.money(spec.count),
                        style: IntesharType.mono(11, color: fg, w: FontWeight.w700)),
                  ),
                ),
              ],
            ),
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
    // UX-119: same raw-InkWell problem as _TabChip, one step smaller (~32dp).
    // These sit 8px apart in a horizontal strip and each one re-queries the
    // server, so a mis-tap costs a round trip and a changed result set.
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: IntesharType.sans(12,
                        color: fg, w: selected ? FontWeight.w800 : IntesharWeight.semibold)),
              ],
            ),
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
            // UX-150: a bare x inside a search box.
            : IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClear),
      ),
    );
  }
}

// ─── Shared formatting helpers ─────────────────────────────────────────────────

({IconData icon, Color color}) _logVisual(BuildContext context, OperationLog log) {
  final t = context.status;
  if (log.isError) return (icon: Icons.error_outline, color: t.danger);
  if (log.isWarn) return (icon: Icons.warning_amber_rounded, color: t.warn);
  if (!log.success) return (icon: Icons.info_outline, color: t.inFlight);
  return (icon: Icons.check_circle_outline, color: t.success);
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

Widget _logStatusPill(BuildContext context, OperationLog log) {
  if (log.httpStatus != null) {
    return StampPill(
      label: '${log.httpStatus}',
      color: log.success ? context.status.success : context.status.danger,
    );
  }
  // UX-154: `_logVisual` computes an icon AND a colour, and this dropped the
  // icon on the floor — so error/warn/info were told apart by hue alone, on the
  // one screen an admin opens when something has gone wrong. StampPill already
  // takes an icon; the shape is the cue that survives colour blindness and a
  // sunlit handheld screen.
  final visual = _logVisual(context, log);
  return StampPill(
      label: log.level, color: visual.color, icon: visual.icon);
}

/// B-108: the headline is a sentence, not a route. `POST /api/auth/login` next
/// to a phone number made an admin read the API to read their own audit trail.
/// Method/path/action are untouched in the tap-through detail sheet.
String _logPrimaryLine(OperationLog log, bool ar) =>
    logPhrase(log, ar: ar).title;

// ─── Activity row ────────────────────────────────────────────────────────────

class _LogRow extends StatelessWidget {
  final OperationLog log;
  final VoidCallback onTap;
  const _LogRow({required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _logVisual(context, log);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final phrase = logPhrase(log, ar: ar);
    final meta = <String>[
      if (phrase.by != null) phrase.by!,
      if (log.surface.isNotEmpty) log.surface else log.source,
      if (log.clientPlatform.isNotEmpty) log.clientPlatform,
      _fmtCompact(log.timestamp),
    ].where((p) => p.isNotEmpty).join(' · ');

    return InkCard(
      density: CardDensity.dense,
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
                Text(_logPrimaryLine(log, ar),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(12, color: context.status.neutral)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _logStatusPill(context, log),
              if (log.durationMs != null) ...[
                const SizedBox(height: 5),
                _ltr(Text('${log.durationMs}ms',
                    style: IntesharType.mono(11, color: IntesharColors.lichen))),
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
  final ValueChanged<String>? onEntity;
  const _LogDetailSheet({required this.light, required this.future, this.onEntity});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final v = _logVisual(context, light);

    return _SheetFrame(
      title: l.sysActDetailTitle,
      titleTrailing: _logStatusPill(context, light),
      children: [
        Row(
          children: [
            Icon(v.icon, size: 18, color: v.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _logPrimaryLine(light, Localizations.localeOf(context).languageCode == 'ar'),
                style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700),
              ),
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
                ..._logKv(ctx, l, log, onEntity: onEntity),
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

List<Widget> _logKv(BuildContext context, AppLocalizations l, OperationLog log,
    {ValueChanged<String>? onEntity}) {
  final cs = Theme.of(context).colorScheme;
  final ar = Localizations.localeOf(context).languageCode == 'ar';
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
    // UX-08: the id above identifies an account nobody could reach from here.
    if (log.entityId.isNotEmpty && onEntity != null)
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => onEntity(log.entityId),
            icon: const Icon(Icons.bolt_outlined, size: 16),
            label: Text(ar ? 'نشاط هذا الحساب' : "This account's activity"),
          ),
        ),
      ),
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

Color _txnStatusColor(BuildContext context, TransactionStatus s) => switch (s) {
      TransactionStatus.COMPLETED => context.status.success,
      TransactionStatus.FAILED => context.status.danger,
      _ => context.status.warn,
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
      density: CardDensity.dense,
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
                    style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
                const SizedBox(height: 3),
                _ltr(Text('#$shortId · ${row.date} ${row.time}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.mono(11, color: context.status.neutral))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StampPill(label: _txnStatusLabel(l, row.statusEnum), color: _txnStatusColor(context, row.statusEnum)),
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
      titleTrailing: StampPill(label: _txnStatusLabel(l, row.statusEnum), color: _txnStatusColor(context, row.statusEnum)),
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
                    style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
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
                        Expanded(child: _ltr(Text(ln.sku, style: IntesharType.mono(12, color: cs.onSurface, w: FontWeight.w600)))),
                        Text('×${Formatters.money(ln.amount)}', style: IntesharType.sans(12, color: context.status.neutral)),
                        const SizedBox(width: 14),
                        Text(Formatters.iqd(ln.lineTotal), style: IntesharType.mono(12, color: cs.onSurface, w: FontWeight.w700)),
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
          padding: const EdgeInsets.all(IntesharSpacing.md),
          decoration: BoxDecoration(
            color: context.tones.brand.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(IntesharRadii.md),
          ),
          child: Row(
            children: [
              Text(l.newTxnGrandTotal, style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
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

/// UX-93: this tab was the FOURTH surface listing the same entity objects, and
/// the only one from which nothing could be done — an admin who spotted a
/// problem here had to remember which of the other three screens carried the
/// fix. It now renders the canonical row menu, which gates itself exactly as it
/// does in the hierarchy and the agent directories: a viewer without
/// MANAGE_AGENTS still sees a read-only list.
class _EntityRow extends ConsumerWidget {
  final EntitySummaryRow row;
  final AppLocalizations l;
  final VoidCallback onTap;
  final VoidCallback onChanged;
  const _EntityRow({
    required this.row,
    required this.l,
    required this.onTap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final meta = <String>[
      l.entityTreeChildrenCount(row.childrenCount),
      l.entityTreeProductsCount(row.productsCount),
      l.sysActUsersCount(row.userCount),
    ].join(' · ');

    return InkCard(
      density: CardDensity.dense,
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
                    style: IntesharType.sans(12, color: context.status.neutral)),
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
          const SizedBox(width: 4),
          EntityRowActionsButton(row: row, onChanged: onChanged, iconSize: 17),
        ],
      ),
    );
  }
}

class _EntityDetailSheet extends StatelessWidget {
  final EntitySummaryRow row;
  final Future<Paged<AdminUserRow>> usersFuture;
  final AppLocalizations l;
  final VoidCallback? onViewActivity;
  final VoidCallback? onOpenAgent;
  const _EntityDetailSheet({
    required this.row,
    required this.usersFuture,
    required this.l,
    this.onViewActivity,
    this.onOpenAgent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return _SheetFrame(
      title: row.label,
      titleTrailing: RoleBadge(type: row.type),
      children: [
        if (onViewActivity != null || onOpenAgent != null) ...[
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (onViewActivity != null)
              OutlinedButton.icon(
                onPressed: onViewActivity,
                icon: const Icon(Icons.bolt_outlined, size: 18),
                label: Text(ar ? 'نشاط هذا الحساب' : "This account's activity"),
              ),
            if (onOpenAgent != null)
              OutlinedButton.icon(
                onPressed: onOpenAgent,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(ar ? 'فتح ملف الوكيل' : 'Open agent'),
              ),
          ]),
          const SizedBox(height: 14),
        ],
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
                child: Text(l.manageUsersEmpty, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
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
                        Expanded(child: _ltr(Text(u.phone, style: IntesharType.mono(12)))),
                        _roleChip(context, u.roleEnum, l),
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

Widget _roleChip(BuildContext context, UserRole role, AppLocalizations l) => StampPill(
      label: role == UserRole.ADMIN ? l.sysActRoleAdmin : l.entityTypeUser,
      color: role == UserRole.ADMIN ? context.tones.brandInk : context.status.neutral,
    );

class _UserRow extends StatelessWidget {
  final AdminUserRow row;
  final AppLocalizations l;
  final VoidCallback? onTap;
  const _UserRow({required this.row, required this.l, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final type = row.entityTypeEnum;
    return InkCard(
      density: CardDensity.dense,
      onTap: onTap,
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
                _ltr(Text(row.phone, style: IntesharType.mono(14, color: cs.onSurface, w: FontWeight.w600))),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(row.entityLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IntesharType.sans(12, color: context.status.neutral)),
                    ),
                    if (type != null) ...[const SizedBox(width: 6), _MiniTypeTag(type: type)],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _roleChip(context, row.roleEnum, l),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
          ],
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
      child: Text(type.label,
          style: IntesharType.sans(IntesharScale.caption, color: c, w: FontWeight.w700)),
    );
  }
}

// ─── Shared sheet primitives ───────────────────────────────────────────────────

/// UX-131: the three detail sheets on this page used to share a *local* frame
/// that re-decided the height cap, the title size (an off-scale 22) and the
/// brand rule, and forgot the keyboard inset entirely. This is the shared
/// [SheetFrame] with the same call shape, so the three call sites are untouched.
///
/// `handle: false` because every one of the four `showModalBottomSheet` calls on
/// this page already passes `showDragHandle: true` — the framework draws the
/// grab pill, and letting SheetFrame draw a second one is the affordance lie in
/// the other direction.
class _SheetFrame extends StatelessWidget {
  final String title;
  final Widget? titleTrailing;
  final List<Widget> children;
  const _SheetFrame({required this.title, this.titleTrailing, required this.children});

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      handle: false,
      title: title,
      trailing: titleTrailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

Widget _kv(BuildContext context, String label, String value, {bool mono = false}) {
  final cs = Theme.of(context).colorScheme;
  final valueWidget = SelectableText(
    value,
    style: mono
        ? IntesharType.mono(12, color: cs.onSurface)
        : IntesharType.sans(14, color: cs.onSurface, w: IntesharWeight.regular),
  );
  return Padding(
    padding: const EdgeInsets.only(bottom: IntesharSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: IntesharType.sans(12, color: context.status.neutral, w: IntesharWeight.semibold)),
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
                style: IntesharType.sans(14, color: cs.onSurfaceVariant, w: IntesharWeight.semibold),
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
        Text(label, style: IntesharType.sans(12, color: tint ?? context.status.neutral, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(IntesharRadii.md),
            border: Border.all(color: cs.outline),
          ),
          child: _ltr(SelectableText(text, style: IntesharType.mono(12, color: cs.onSurface).copyWith(height: 1.45))),
        ),
      ],
    );
  }
}

/// B-060: an HQ oversight card listing Main Agents holding stock in unpriced
/// categories ("اظهار تنبيه بأي وكيل لم يتم تسعير الكروت له"). Always current.
class _UnpricedAgentsCard extends StatelessWidget {
  const _UnpricedAgentsCard({required this.rows, this.onTapAgent});
  final List<UnpricedAgent> rows;

  /// UX-16: the one genuinely useful alert on the landing page rendered its
  /// agents as inert `Chip`s. Tapping one now opens that agent in the entities
  /// feed instead of leaving the reader to go find it by name.
  final ValueChanged<String>? onTapAgent;

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(IntesharSpacing.md),
      decoration: BoxDecoration(
        color: context.tones.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: context.tones.brandInk.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.price_change_outlined, size: 18, color: context.tones.brandInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ar
                  ? '${rows.length} وكيل رئيسي لديه بطاقات غير مسعّرة'
                  : '${rows.length} main agent(s) with unpriced cards',
              style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          // UX-119: `compact` dropped these below the 48dp floor, and they are
          // laid out in a Wrap so neighbours sit 8px apart in both axes — the
          // worst case for a shrunken target. Each one navigates to a different
          // agent, so a mis-tap opens the wrong account.
          for (final r in rows)
            ActionChip(
              avatar: onTapAgent == null
                  ? null
                  : Icon(Icons.open_in_new, size: 14, color: cs.onSurfaceVariant),
              label: Text('${r.name.isNotEmpty ? r.name : r.entityId} · ${r.unpricedCount}',
                  style: IntesharType.sans(12, color: cs.onSurface)),
              onPressed: onTapAgent == null
                  ? null
                  : () => onTapAgent!(r.name.isNotEmpty ? r.name : r.entityId),
            ),
        ]),
      ]),
    );
  }
}
