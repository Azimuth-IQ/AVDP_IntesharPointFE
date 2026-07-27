import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/core/files/report_export.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/agents/data/agent_repository.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/features/reports/domain/report_filters.dart';
import 'package:inteshar/features/reports/domain/report_rows.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// The Reports section (client spec `Docs/سستم.xlsx` → التقارير). Phase 1 (Prices #7,
/// Stock #8, Detailed #9) + Phase 2 (POS balances #1, Agent balances #2, Transfers #3).
/// Sales/upload reports (#4-6) + export land in Phase 3-4 — see
/// `Docs/REPORTING-MODULE-BUILD-MAP.md`.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _RS {
  final bool ar;
  const _RS(this.ar);
  factory _RS.of(BuildContext c) => _RS(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('Reports', 'التقارير');
  String get title => p('Reports', 'التقارير');
  String get subtitle => p('Balances, transfers, prices and stock', 'الأرصدة والتحويلات والأسعار والمخزون');
  String get tabPrices => p('Prices', 'الأسعار');
  String get tabStock => p('Stock', 'المخزون');
  String get tabDetailed => p('Detailed', 'مفصّل');
  String get tabPosBalances => p('POS balances', 'أرصدة نقاط البيع');
  String get tabAgentBalances => p('Agent balances', 'أرصدة الوكلاء');
  String get tabTransfers => p('Transfers', 'التحويلات');
  String get viewFor => p('Report for', 'التقرير لـ');
  String get self => p('Me', 'أنا');
  String get company => p('Company', 'الشركة');
  String get category => p('Category', 'الفئة');
  String get base => p('Base', 'الأساسي');
  String get agent => p('Agent', 'الوكيل');
  String get effective => p('Effective', 'الفعلي');
  String get available => p('Available', 'المتوفر');
  String get total => p('Total', 'الكلي');
  String get used => p('Used', 'مُستخدَم');
  String get value => p('Value', 'القيمة');
  String get grandTotal => p('Grand total (transferable balance)', 'المجموع الكلي (الرصيد القابل للتحويل)');
  String get untagged => p('No region', 'بدون محافظة');
  String get uncategorized => p('Uncategorized', 'بدون شركة');
  String get empty => p('Nothing to report yet.', 'لا توجد بيانات للتقرير بعد.');
  String get owner => p('Owner', 'المالك');
  String get phone => p('Phone', 'الهاتف');
  String get balance => p('Balance', 'الرصيد');
  String get spent => p('Spent', 'المصروف');
  String get points => p('POS points', 'نقاط البيع');
  String get mainAgent => p('Main agent', 'الوكيل الرئيسي');
  String get subAgent => p('Sub agent', 'الوكيل الفرعي');
  String get governorate => p('Governorate', 'المحافظة');
  String get transferAmount => p('Transfer', 'التحويل');
  String get balanceAfter => p('After (credits)', 'بعد (إيداعات)');
  String get allDates => p('All dates', 'كل التواريخ');
  String get pickRange => p('Date range', 'المدة');
  String get tabSold => p('Sold cards', 'الكروت المباعة');
  String get tabTotalSold => p('Total sold', 'إجمالي المباع');
  String get tabUploaded => p('Uploaded', 'المرفوعة');
  String get cards => p('Cards', 'الكروت');
  // Align on the canonical store term (متجر), not المكتب (= office) — B-079.
  String get store => p('Store', 'المتجر');
  String get export => p('Export', 'تصدير');
  String get exported => p('Report exported', 'تم تصدير التقرير');
  String get nothingToExport => p('Nothing to export', 'لا توجد بيانات للتصدير');
  String get date => p('Date', 'التاريخ');
  String get time => p('Time', 'الوقت');
  String get from => p('From', 'من');
  String get to => p('To', 'إلى');
  String get address => p('Address', 'العنوان');
  String get source => p('Source', 'المصدر');
  String get destination => p('Destination', 'الوجهة');
  String get user => p('User', 'المستخدم');
  String get currentBalance => p('Current balance', 'الرصيد الحالي');
  String get agentLabel => p('Agent', 'الوكيل');
  String get loadMore => p('Load more', 'تحميل المزيد');
  String get totalMoved => p('Total moved', 'إجمالي المحوَّل');
  String get totalSoldCards => p('Total cards sold', 'إجمالي الكروت المباعة');
  String get totalUploaded => p('Total cards uploaded', 'إجمالي الكروت المرفوعة');
  String get emptyInRange =>
      p('Nothing in this date range.', 'لا توجد بيانات ضمن هذه المدة.');
  String get searchAllDates => p('Search all dates', 'ابحث في كل التواريخ');
  String get searchRoster => p('Search name, owner, phone…', 'ابحث بالاسم أو المالك أو الهاتف…');
  String get allGovernorates => p('All', 'الكل');
  String get familyMoney => p('Money', 'الأموال');
  String get familyStock => p('Stock', 'المخزون');
  String get familyActivity => p('Activity', 'الحركة');
  String get noMatchLoaded => p(
      'No match in the rows loaded so far — try Load more.',
      'لا نتائج ضمن الصفوف المحمّلة — جرّب تحميل المزيد.');
  String get generatedAt => p('Generated', 'تاريخ الإنشاء');
  String get exportTruncated =>
      p('Export stopped at the row cap — the sheet is incomplete',
        'توقّف التصدير عند الحد الأقصى للصفوف — الملف غير مكتمل');
}

/// B-103: the 9 reports are really three families. Flat, they wrapped to FOUR rows
/// of chips (~140px) on a 360dp phone — with the page header, target picker and
/// date bar that was ~325px of chrome before the first data row.
enum _Family { money, stock, activity }

class _Tab {
  final String key;
  final String label;
  final _Family family;
  const _Tab(this.key, this.label, this.family);
}

class _Export {
  final List<String> headers;
  final List<List<String>> rows;
  final String file;
  const _Export(this.headers, this.rows, this.file);
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int _tab = 0;
  String? _targetId; // null = own entity
  DateTime? _from;
  DateTime? _to;

  List<(String, String)> _pickables = const []; // (id, label) for the agent target picker
  /// B-091: sku -> card artwork, for the stock report's image grid. SkuSummary
  /// carries no image, so the catalog is joined client-side (one read at boot).
  Map<String, String> _artBySku = const {};
  final Map<String, Future<dynamic>> _cache = {}; // per-tab futures, cleared on scope/date change
  bool _booting = true;

  ReportsRepository get _repo => ReportsRepository(ref.read(apiClientProvider));
  Entity? get _me => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity;
  bool get _isHq => _me?.type == EntityType.INTESHAR;
  String get _effectiveId => _targetId ?? _me?.id ?? '';

  List<_Tab> _tabsFor(_RS s) => [
        // Money — what each account is worth and what moved between them.
        _Tab('posBalances', s.tabPosBalances, _Family.money),
        // #2 agent balances: admin + main agent only.
        if (_isHq || _me?.type == EntityType.AGENT1)
          _Tab('agentBalances', s.tabAgentBalances, _Family.money),
        _Tab('transfers', s.tabTransfers, _Family.money),
        // Stock & prices — what we hold and what it is worth.
        _Tab('prices', s.tabPrices, _Family.stock),
        // Stock + Detailed (inventory worth) only for tiers that hold cards
        // (HQ / Main Agent). Sub Agents & Stores draw-on-print → always empty (B-068).
        if (_me?.type.inventoryBacked ?? false) _Tab('stock', s.tabStock, _Family.stock),
        if (_me?.type.inventoryBacked ?? false) _Tab('detailed', s.tabDetailed, _Family.stock),
        // Activity — what happened over a window.
        _Tab('sold', s.tabSold, _Family.activity),
        _Tab('totalSold', s.tabTotalSold, _Family.activity),
        // #6 uploaded cards: admin + main agent only.
        if (_isHq || _me?.type == EntityType.AGENT1)
          _Tab('uploaded', s.tabUploaded, _Family.activity),
      ];

  String _familyLabel(_Family f, _RS s) => switch (f) {
        _Family.money => s.familyMoney,
        _Family.stock => s.familyStock,
        _Family.activity => s.familyActivity,
      };

  // sold + totalSold share one /sales fetch; everything else is its own source.
  String _sourceKey(String tab) => (tab == 'sold' || tab == 'totalSold') ? 'sales' : tab;
  bool _isDated(String key) =>
      key == 'transfers' || key == 'sold' || key == 'totalSold' || key == 'uploaded';

  @override
  void initState() {
    super.initState();
    // Default the dated reports to the last 30 days so nothing loads a full history.
    // B-097: clearing the range now sends allDates=true EXPLICITLY — omitting from/to
    // used to fall through to the server's own 30-day default while the bar read
    // "All dates", so the report said "all" and returned a month.
    final now = DateTime.now();
    _to = now;
    _from = now.subtract(const Duration(days: 30));
    _boot();
  }

  /// Label of the entity the report is currently scoped to (the picked agent, or self).
  String get _currentAgentLabel {
    for (final (id, label) in _pickables) {
      if (id == _effectiveId) return label;
    }
    return _me?.meta.name ?? '';
  }

  Future<void> _boot() async {
    // B-091: the spec marks most report sheets "يضاف للكل" with an agent selector —
    // so a Main Agent gets one too, scoped to its OWN subtree (HQ sees everyone).
    final selfLabel = _RS.of(context).self;
    final me = _me;
    if (_isHq) {
      try {
        final repo = AgentRepository(ref.read(apiClientProvider));
        final mains = await repo.listAll('AGENT1');
        final subs = await repo.listAll('AGENT2');
        _pickables = [
          if (me != null) (me.id, '$selfLabel · ${me.meta.name}'),
          ...mains.map((e) => (e.id, e.name)),
          ...subs.map((e) => (e.id, e.name)),
        ];
      } catch (_) {}
    } else if (me != null && me.type == EntityType.AGENT1) {
      try {
        final children = await EntityRepository(ref.read(apiClientProvider))
            .children(me.id, size: 200);
        _pickables = [
          (me.id, '$selfLabel · ${me.meta.name}'),
          ...children.items.map((e) => (e.id, e.label)),
        ];
      } catch (_) {}
    }
    try {
      final defs = await DefinitionRepository(ref.read(apiClientProvider)).readAll();
      _artBySku = {
        for (final d in defs)
          if (d.sku.isNotEmpty && d.imageUrl.isNotEmpty) d.sku: d.imageUrl,
      };
    } catch (_) {
      // Non-fatal — the grid falls back to a neutral placeholder tile.
    }
    if (mounted) setState(() => _booting = false);
  }

  // B-097: the two paged feeds accumulate across pages. The report widgets still
  // take a plain List, so the accumulator IS the future's value and Load-more just
  // republishes it.
  final Map<String, List<dynamic>> _acc = {};
  final Map<String, int> _accPage = {};
  final Map<String, bool> _accMore = {};
  String? _loadingMoreFor;

  /// True when the user cleared the range. B-097: this is now sent EXPLICITLY as
  /// `allDates` — omitting from/to silently meant "last 30 days" on the server
  /// while the bar said "All dates".
  bool get _allDates => _from == null || _to == null;

  /// B-103: the stock report's governorate filter used to live INSIDE its body
  /// while the date range sat in the toolbar — two filters, two places. Hoisted
  /// so both sit in one filter row. '' = every governorate.
  String _stockGov = '';

  void _invalidate() => setState(() {
        _cache.clear();
        _acc.clear();
        _accPage.clear();
        _accMore.clear();
      });

  static const _pageSize = 100;

  /// Loads page 0 of a paged feed into the accumulator and returns its rows.
  Future<List<T>> _firstPage<T>(String src, Future<Paged<T>> Function(int) fetch) async {
    final p = await fetch(0);
    _acc[src] = List<dynamic>.from(p.items);
    _accPage[src] = 0;
    _accMore[src] = p.hasMore;
    return p.items;
  }

  Future<Paged<dynamic>> _fetchPage(String src, int page) {
    final id = _effectiveId;
    switch (src) {
      case 'posBalances':
        return _repo.balancesRoster(rootId: id, type: 'STORE', page: page, size: _pageSize);
      case 'agentBalances':
        return _repo.balancesRoster(rootId: id, page: page, size: _pageSize);
      default:
        return _repo.transfers(
            rootId: id,
            from: _ymd(_from),
            to: _ymd(_to),
            allDates: _allDates,
            page: page,
            size: _pageSize);
    }
  }

  /// Agent-balance rows are filtered client-side, so filter each page as it lands
  /// rather than the page-0 slice only.
  List<dynamic> _filterPage(String src, List<dynamic> items) => src == 'agentBalances'
      ? items.where((r) => r.tier == 'AGENT1' || r.tier == 'AGENT2').toList()
      : items;

  Future<void> _loadMore(String src) async {
    if (_loadingMoreFor != null || !(_accMore[src] ?? false)) return;
    setState(() => _loadingMoreFor = src);
    try {
      final next = await _fetchPage(src, (_accPage[src] ?? 0) + 1);
      if (!mounted) return;
      setState(() {
        _acc[src] = [...?_acc[src], ..._filterPage(src, next.items)];
        _accPage[src] = (_accPage[src] ?? 0) + 1;
        _accMore[src] = next.hasMore;
        _cache[src] = Future.value(List<dynamic>.from(_acc[src]!));
        _loadingMoreFor = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMoreFor = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    }
  }

  /// Pages a feed to EXHAUSTION for export. A sheet that silently stops at page 0
  /// while looking complete is worse than no sheet — so this walks every page, and
  /// the hard cap exists only so a runaway cannot hang the app. [onCapped] fires if
  /// the cap is ever reached, and the caller warns instead of pretending.
  Future<List<dynamic>> _fetchAllPages(String src, {required void Function() onCapped}) async {
    const maxPages = 200; // 20k rows at _pageSize
    final out = <dynamic>[];
    for (var p = 0; p < maxPages; p++) {
      final res = await _fetchPage(src, p);
      out.addAll(_filterPage(src, res.items));
      if (!res.hasMore) return out;
    }
    onCapped();
    return out;
  }

  Future<dynamic> _futureFor(String tab) {
    final src = _sourceKey(tab);
    return _cache.putIfAbsent(src, () {
      final id = _effectiveId;
      switch (src) {
        case 'prices':
        case 'detailed':
          return _repo.priceCatalog(entityId: id);
        case 'stock':
          return _repo.stockSummary(entityId: id);
        case 'posBalances':
        case 'agentBalances':
        case 'transfers':
          return _firstPage(src, (p) => _fetchPage(src, p))
              .then((rows) => _acc[src] = _filterPage(src, rows));
        case 'sales':
          return _repo.sales(
              rootId: id, from: _ymd(_from), to: _ymd(_to), allDates: _allDates);
        case 'uploaded':
          return _repo.uploads(
              rootId: id, from: _ymd(_from), to: _ymd(_to), allDates: _allDates);
        default:
          return Future.value(null);
      }
    });
  }

  /// Filename-safe fragment. Arabic entity names would survive most filesystems but
  /// not every browser download path, so non-ASCII is dropped rather than mangled —
  /// the sheet's own provenance block carries the full name either way.
  String _slug(String v) {
    final ascii = v.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return ascii.length > 24 ? ascii.substring(0, 24) : ascii;
  }

  String? _ymd(DateTime? d) => d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: (_from != null && _to != null) ? DateTimeRange(start: _from!, end: _to!) : null,
    );
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
        _cache.clear(); // date affects transfers + sales + uploads
      });
    }
  }

  Future<void> _export(String key, _RS s) async {
    final loc = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final src = _sourceKey(key);
    final isPaged = src == 'posBalances' || src == 'agentBalances' || src == 'transfers';
    dynamic data;
    var capped = false;
    try {
      // B-097: a paged report must export EVERY page. Exporting only what happens to
      // be on screen produces a sheet that looks complete and silently isn't — which
      // on an audit trail is worse than not exporting at all.
      data = isPaged
          ? await _fetchAllPages(src, onCapped: () => capped = true)
          : await _futureFor(key); // resolves instantly from the cache once loaded
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      return;
    }
    final built = _exportRows(key, data, s, loc);
    if (!mounted) return;
    if (built == null || built.rows.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.nothingToExport)));
      return;
    }
    // B-098: stamp WHAT this sheet is. Without it, January's sales and February's
    // download as the same `sold_cards.xlsx` with nothing inside telling them apart.
    final rangeLabel = _isDated(key)
        ? (_allDates ? s.allDates : '${_ymd(_from)} → ${_ymd(_to)}')
        : '—';
    final now = DateTime.now();
    final stamp = '${_ymd(now)}_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final scope = _currentAgentLabel.isEmpty ? s.self : _currentAgentLabel;
    final fileName = [
      built.file,
      _slug(scope),
      if (_isDated(key)) (_allDates ? 'all' : '${_ymd(_from)}_${_ymd(_to)}'),
      stamp,
    ].where((p) => p.isNotEmpty).join('-');

    try {
      final path = await exportRowsToXlsx(
          fileName: fileName,
          sheetName: built.file,
          headers: built.headers,
          rows: built.rows,
          provenance: [
            (s.title, _tabsFor(s).firstWhere((t) => t.key == key).label),
            (s.viewFor, scope),
            (s.pickRange, rangeLabel),
            (s.generatedAt, '${_ymd(now)} ${now.hour.toString().padLeft(2, '0')}:'
                '${now.minute.toString().padLeft(2, '0')}'),
            // B-100: whoever opens the sheet sees the same headline figure the
            // screen showed, without re-summing a column to check.
            ?_exportTotal(key, data, s),
            if (capped) (s.export, s.exportTruncated),
          ]);
      if (mounted && path != null) {
        // Never let a capped export pass as a complete one.
        messenger.showSnackBar(
            SnackBar(content: Text(capped ? s.exportTruncated : s.exported)));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
  }

  /// The headline total for [key], mirroring the on-screen _TotalStrip. Null for
  /// reports that have no single meaningful total (prices, stock rosters).
  (String, String)? _exportTotal(String key, dynamic data, _RS s) {
    switch (key) {
      case 'detailed':
        final c = data as PricingCatalog?;
        return c == null ? null : (s.grandTotal, Formatters.iqd(c.inventoryWorth.round()));
      case 'transfers':
        final rows = (data as List<TransferRow>?) ?? const [];
        return (s.totalMoved, Formatters.iqd(rows.fold<num>(0, (a, r) => a + r.amount).round()));
      case 'sold':
      case 'totalSold':
        final rows = (data as List<SalesRow>?) ?? const [];
        return (s.totalSoldCards, Formatters.money(rows.fold<int>(0, (a, r) => a + r.count)));
      case 'uploaded':
        final rows = (data as List<UploadsRow>?) ?? const [];
        return (s.totalUploaded, Formatters.money(rows.fold<int>(0, (a, r) => a + r.count)));
      default:
        return null;
    }
  }

  /// Flattens the active tab's loaded data into (headers, rows, filename) for XLSX.
  _Export? _exportRows(String key, dynamic data, _RS s, String loc) {
    String gov(String g) => g.isEmpty ? s.untagged : governorateLabel(g, loc);
    String m(num n) => Formatters.money(n);

    List<(String, num, num?, num)> priceGovs(CategoryPriceRow r) {
      final has = r.governorates.length > 1 ||
          (r.governorates.length == 1 && r.governorates.first.governorate.isNotEmpty);
      if (!has) return [('', r.officialPrice, r.agentPrice, r.effectivePrice)];
      return [for (final g in r.governorates) (g.governorate, g.officialPrice, g.agentPrice, g.effectivePrice)];
    }

    List<(String, int, num, num)> detailGovs(CategoryPriceRow r) {
      final has = r.governorates.length > 1 ||
          (r.governorates.length == 1 && r.governorates.first.governorate.isNotEmpty);
      if (!has) return [('', r.available, r.effectivePrice, r.lineValue)];
      return [for (final g in r.governorates) (g.governorate, g.available, g.effectivePrice, g.lineValue)];
    }

    switch (key) {
      case 'prices':
        final c = data as PricingCatalog?;
        if (c == null) return null;
        final agent = _currentAgentLabel;
        final rows = [
          for (final r in c.rows)
            for (final g in priceGovs(r))
              [agent, r.companyName, r.name, gov(g.$1), m(g.$2), g.$3 == null ? '' : m(g.$3!), m(g.$4)],
        ];
        return _Export([s.agentLabel, s.company, s.category, s.governorate, s.base, s.agent, s.effective], rows, 'prices');
      case 'stock':
        final list = (data as List<SkuSummary>?) ?? const [];
        final rows = <List<String>>[];
        for (final sku in list) {
          final buckets = sku.governorates.isEmpty
              ? [('', sku.available, sku.total, sku.printed)]
              : [for (final g in sku.governorates) (g.governorate, g.available, g.total, g.printed)];
          for (final b in buckets) {
            rows.add([sku.name, gov(b.$1), '${b.$2}', '${b.$3}', '${b.$4}']);
          }
        }
        return _Export([s.category, s.governorate, s.available, s.total, s.used], rows, 'stock');
      case 'detailed':
        final c = data as PricingCatalog?;
        if (c == null) return null;
        final rows = [
          for (final r in c.rows)
            for (final g in detailGovs(r)) [r.name, gov(g.$1), '${g.$2}', m(g.$3), m(g.$4)],
        ];
        rows.add([s.grandTotal, '', '', '', m(c.inventoryWorth)]);
        return _Export([s.category, s.governorate, s.available, s.effective, s.value], rows, 'detailed');
      case 'posBalances':
      case 'agentBalances':
        final list = (data as List<BalanceRosterRow>?) ?? const [];
        final rows = [
          for (final r in list)
            [r.name, r.ownerName, r.userPhone, gov(r.governorate), r.address, r.mainAgentName, r.subAgentName,
              m(r.available), m(r.ordersSpent), '${r.storeCount}'],
        ];
        return _Export(
            [s.tabPosBalances, s.owner, s.phone, s.governorate, s.address, s.mainAgent, s.subAgent, s.balance, s.spent, s.points],
            rows, key);
      case 'transfers':
        final list = (data as List<TransferRow>?) ?? const [];
        final rows = [
          for (final r in list)
            [r.date, r.time, r.sourceName, r.destName, m(r.amount), m(r.balanceAfter), m(r.destAvailable),
              r.destOwnerName, r.destPhone, gov(r.destGovernorate), r.mainAgentName, r.subAgentName],
        ];
        return _Export(
            [s.date, s.time, s.source, s.destination, s.transferAmount, s.balanceAfter, s.currentBalance, s.owner, s.phone, s.governorate, s.mainAgent, s.subAgent],
            rows, 'transfers');
      case 'sold':
        final list = (data as List<SalesRow>?) ?? const [];
        final rows = [
          for (final r in list)
            [r.storeName, r.ownerName, r.userPhone, r.operatorPhone, gov(r.governorate), r.companyName, r.category,
              r.mainAgentName, r.subAgentName, '${r.count}'],
        ];
        return _Export(
            [s.store, s.owner, s.phone, s.user, s.governorate, s.company, s.category, s.mainAgent, s.subAgent, s.cards],
            rows, 'sold_cards');
      case 'totalSold':
        final list = (data as List<SalesRow>?) ?? const [];
        final totals = <String, int>{};
        final meta = <String, SalesRow>{};
        for (final r in list) {
          final k = '${r.mainAgentName}|${r.subAgentName}|${r.governorate}|${r.companyName}|${r.category}';
          totals[k] = (totals[k] ?? 0) + r.count;
          meta.putIfAbsent(k, () => r);
        }
        final rows = [
          for (final k in totals.keys)
            [meta[k]!.mainAgentName, meta[k]!.subAgentName, gov(meta[k]!.governorate),
              meta[k]!.companyName, meta[k]!.category, '${totals[k]}'],
        ];
        return _Export([s.mainAgent, s.subAgent, s.governorate, s.company, s.category, s.cards], rows, 'total_sold');
      case 'uploaded':
        final list = (data as List<UploadsRow>?) ?? const [];
        final rows = [
          for (final r in list)
            [r.agentName, gov(r.governorate), r.companyName, r.category, '${r.count}'],
        ];
        return _Export([s.mainAgent, s.governorate, s.company, s.category, s.cards], rows, 'uploaded');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _RS.of(context);
    final tabs = _tabsFor(s);
    if (_tab >= tabs.length) _tab = 0;
    final key = tabs[_tab].key;
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle),
          if (_pickables.length > 1) _targetPicker(s),
          _familyBar(tabs, s),
          _tabBar(tabs),
          _filterBar(s, key),
          Expanded(child: _booting ? const Center(child: CircularProgressIndicator()) : _body(s, key)),
        ],
      ),
    );
  }

  Widget _targetPicker(_RS s) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(children: [
        Text('${s.viewFor}: ', style: IntesharType.sans(13, color: cs.onSurfaceVariant)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _effectiveId,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final (id, label) in _pickables)
                DropdownMenuItem(value: id, child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _targetId = v);
              _invalidate();
            },
          ),
        ),
      ]),
    );
  }

  /// B-103: the family picker. Three segments instead of nine chips, so the tab
  /// row below it never exceeds ONE line — the flat Wrap took four.
  Widget _familyBar(List<_Tab> tabs, _RS s) {
    final present = [
      for (final f in _Family.values)
        if (tabs.any((t) => t.family == f)) f,
    ];
    if (present.length < 2) return const SizedBox.shrink();
    final current = tabs[_tab].family;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: SegmentedButton<_Family>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final f in present)
            ButtonSegment(value: f, label: Text(_familyLabel(f, s), maxLines: 1)),
        ],
        selected: {current},
        onSelectionChanged: (sel) {
          // Land on the family's first report rather than remembering a per-family
          // position — with 3 reports each, hunting beats recall.
          final first = tabs.indexWhere((t) => t.family == sel.first);
          if (first >= 0) setState(() => _tab = first);
        },
      ),
    );
  }

  /// Reports within the selected family only — at most three, so always one row.
  Widget _tabBar(List<_Tab> tabs) {
    final cs = Theme.of(context).colorScheme;
    final family = tabs[_tab].family;
    final inFamily = [
      for (var i = 0; i < tabs.length; i++)
        if (tabs[i].family == family) i,
    ];
    if (inFamily.length < 2) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final i in inFamily)
            ChoiceChip(
              label: Text(tabs[i].label),
              selected: _tab == i,
              onSelected: (_) => setState(() => _tab = i),
              labelStyle: IntesharType.sans(12.5,
                  color: _tab == i ? cs.onSurface : cs.onSurfaceVariant, w: FontWeight.w700),
            ),
        ],
      ),
    );
  }

  /// B-103: ONE filter row. The date range and the stock report's governorate used
  /// to live in different places (toolbar vs inside the body); export was an
  /// unlabelled icon whose tooltip never appears on a touch device.
  Widget _filterBar(_RS s, String key) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(children: [
        if (_isDated(key))
          Expanded(child: _dateBar(s))
        else if (key == 'stock')
          Expanded(child: _stockGovBar(s))
        else
          const Spacer(),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.download_outlined, size: 16),
          label: Text(s.export),
          onPressed: _booting ? null : () => _export(key, s),
        ),
      ]),
    );
  }

  /// Empty state for a DATED report — says which window returned nothing and
  /// offers to widen it, so "no sales in January" never reads as "no sales ever".
  Widget _emptyDated(_RS s) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        const SizedBox(height: 72),
        Center(child: Icon(Icons.event_busy_outlined, size: 48, color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _allDates ? s.empty : s.emptyInRange,
            textAlign: TextAlign.center,
            style: IntesharType.sans(14, color: cs.onSurfaceVariant),
          ),
        ),
        if (!_allDates) ...[
          const SizedBox(height: 4),
          Center(
            child: Text('${_ymd(_from)} → ${_ymd(_to)}',
                style: IntesharType.mono(12.5, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 16),
          Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(s.pickRange),
                  onPressed: _pickRange,
                ),
                // The single most likely fix, one tap away.
                FilledButton.tonal(
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                    _invalidate();
                  }),
                  child: Text(s.searchAllDates),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dateBar(_RS s) {
    final cs = Theme.of(context).colorScheme;
    final label = (_from != null && _to != null) ? '${_ymd(_from)} → ${_ymd(_to)}' : s.allDates;
    // Sits inside _filterBar's Row now, so it carries no padding of its own.
    return Row(children: [
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range, size: 16),
          label: Text(label),
        ),
        if (_from != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.clear, size: 18, color: cs.onSurfaceVariant),
            // B-097: clearing now genuinely means every date — _allDates flows to
            // the API as an explicit flag. Use _invalidate so the paged accumulators
            // reset too; a stale _acc would show the old window's rows under the
            // new "All dates" label.
            onPressed: () => setState(() {
              _from = null;
              _to = null;
              _invalidate();
            }),
          ),
        ],
      ],
    );
  }

  /// Governorate filter for the stock report — the options come from the loaded
  /// summary, so it only offers regions that actually hold cards.
  Widget _stockGovBar(_RS s) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    final data = _cache['stock'];
    return FutureBuilder<dynamic>(
      future: data,
      builder: (context, snap) {
        final list = (snap.data as List<SkuSummary>?) ?? const [];
        final govs = <String>{
          for (final sku in list)
            for (final g in sku.governorates) g.governorate,
        }.toList()
          ..sort();
        if (govs.isEmpty) return const SizedBox.shrink();
        return Row(children: [
          Text('${s.governorate}: ', style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _stockGov,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                DropdownMenuItem(value: '', child: Text(s.allGovernorates)),
                for (final g in govs)
                  DropdownMenuItem(
                    value: g,
                    child: Text(g.isEmpty ? s.untagged : governorateLabel(g, loc),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _stockGov = v ?? ''),
            ),
          ),
        ]);
      },
    );
  }

  Widget _body(_RS s, String key) {
    return FutureBuilder<dynamic>(
      future: _futureFor(key),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorState(error: snap.error!, onRetry: () => setState(() => _cache.remove(_sourceKey(key))));
        }
        final data = snap.data;
        // B-101: a dated report that comes back empty is USUALLY empty because of
        // the window, not because the agent has no data — and the generic
        // "Nothing to report yet" made those two indistinguishable. Name the range
        // that was searched and offer the fix.
        if (_isDated(key) && data is List && data.isEmpty) {
          return _emptyDated(s);
        }
        final body = RefreshIndicator(
          onRefresh: () async => setState(() => _cache.remove(_sourceKey(key))),
          child: switch (key) {
            'prices' => _PricesReport(catalog: data as PricingCatalog, s: s, agentLabel: _currentAgentLabel),
            'stock' => _StockReport(
                summary: (data as List<SkuSummary>?) ?? const [],
                artBySku: _artBySku,
                gov: _stockGov,
                s: s),
            'detailed' => _DetailedReport(catalog: data as PricingCatalog, s: s),
            'transfers' => _TransfersReport(rows: (data as List<TransferRow>?) ?? const [], s: s),
            'sold' => _SalesReport(rows: (data as List<SalesRow>?) ?? const [], s: s),
            'totalSold' => _TotalSoldReport(rows: (data as List<SalesRow>?) ?? const [], s: s),
            'uploaded' => _UploadsReport(rows: (data as List<UploadsRow>?) ?? const [], s: s),
            _ => _RosterReport(rows: (data as List<BalanceRosterRow>?) ?? const [], s: s),
          },
        );
        // B-097: the paged feeds show the first page with a Load-more tail rather
        // than pulling the whole subtree/ledger up front. Export still walks every
        // page — see _fetchAllPages.
        if (!(_accMore[_sourceKey(key)] ?? false)) return body;
        return Column(children: [
          Expanded(child: body),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _loadingMoreFor == _sourceKey(key)
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    onPressed: () => _loadMore(_sourceKey(key)), child: Text(s.loadMore)),
          ),
        ]);
      },
    );
  }
}

// ── #1/#2 Balances roster ────────────────────────────────────────────────────
class _RosterReport extends StatefulWidget {
  final List<BalanceRosterRow> rows;
  final _RS s;
  const _RosterReport({required this.rows, required this.s});

  @override
  State<_RosterReport> createState() => _RosterReportState();
}

/// B-102: the roster is a flat, now-paged list — finding one shop meant paging
/// until it appeared. Filters the rows ALREADY LOADED (name / owner / phone /
/// governorate); the Load-more tail keeps working, so a search that comes up
/// empty on page 1 is a prompt to load more rather than a dead end.
class _RosterReportState extends State<_RosterReport> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cs = Theme.of(context).colorScheme;
    if (widget.rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    final rows = widget.rows
        .where((r) => rosterMatches(r, _q, govLabel: (g) => governorateLabel(g, loc)))
        .toList();
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: s.searchRoster,
              // Show the effect of the filter, not just that one is applied.
              suffixText: _q.isEmpty ? null : '${rows.length}/${widget.rows.length}',
            ),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(s.noMatchLoaded,
                  textAlign: TextAlign.center,
                  style: IntesharType.sans(13, color: cs.onSurfaceVariant)),
            ),
          ),
        for (final r in rows)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(r.name, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                  Text(Formatters.iqd(r.available.round()),
                      style: IntesharType.mono(15, color: context.tones.brandInk, w: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                if (r.ownerName.isNotEmpty) _kv(cs, s.owner, r.ownerName),
                if (r.userPhone.isNotEmpty) _kv(cs, s.phone, r.userPhone),
                if (r.governorate.isNotEmpty) _kv(cs, s.governorate, governorateLabel(r.governorate, loc)),
                if (r.address.isNotEmpty) _kv(cs, s.address, r.address),
                if (r.mainAgentName.isNotEmpty) _kv(cs, s.mainAgent, r.mainAgentName),
                if (r.subAgentName.isNotEmpty) _kv(cs, s.subAgent, r.subAgentName),
                if (r.tier == 'AGENT1' || r.tier == 'AGENT2') _kv(cs, s.points, '${r.storeCount}'),
                if (r.ordersSpent > 0) _kv(cs, s.spent, Formatters.iqd(r.ordersSpent.round())),
              ],
            ),
          ),
      ],
    );
  }
}

// ── #3 Transfers ─────────────────────────────────────────────────────────────
class _TransfersReport extends StatelessWidget {
  final List<TransferRow> rows;
  final _RS s;
  const _TransfersReport({required this.rows, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    // B-100: "how much moved" is the first question a transfers report is asked.
    final moved = rows.fold<num>(0, (a, r) => a + r.amount);
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        _TotalStrip(
          label: s.totalMoved,
          value: Formatters.iqd(moved.round()),
          subLabel: s.tabTransfers,
          subValue: Formatters.money(rows.length),
        ),
        for (final r in rows)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        '${r.sourceName} ${Directionality.of(context) == TextDirection.rtl ? '←' : '→'} ${r.destName}',
                        style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text('+${Formatters.iqd(r.amount.round())}',
                      style: IntesharType.mono(14, color: IntesharColors.sage, w: FontWeight.w800)),
                ]),
                const SizedBox(height: 2),
                Text('${r.date} · ${r.time}', style: IntesharType.mono(11, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                if (r.destOwnerName.isNotEmpty) _kv(cs, s.owner, r.destOwnerName),
                if (r.destPhone.isNotEmpty) _kv(cs, s.phone, r.destPhone),
                if (r.destGovernorate.isNotEmpty) _kv(cs, s.governorate, governorateLabel(r.destGovernorate, loc)),
                if (r.mainAgentName.isNotEmpty) _kv(cs, s.mainAgent, r.mainAgentName),
                if (r.subAgentName.isNotEmpty) _kv(cs, s.subAgent, r.subAgentName),
                if (r.destAvailable != 0) _kv(cs, s.currentBalance, Formatters.iqd(r.destAvailable.round())),
                _kv(cs, s.balanceAfter, Formatters.iqd(r.balanceAfter.round())),
              ],
            ),
          ),
      ],
    );
  }
}

// ── #4 Sold cards ────────────────────────────────────────────────────────────
class _SalesReport extends StatelessWidget {
  final List<SalesRow> rows;
  final _RS s;
  const _SalesReport({required this.rows, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    // B-100: the headline number a sales report exists to answer.
    final sold = rows.fold<int>(0, (a, r) => a + r.count);
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        _TotalStrip(
          label: s.totalSoldCards,
          value: Formatters.money(sold),
          subLabel: s.store,
          subValue: Formatters.money(rows.map((r) => r.storeName).toSet().length),
        ),
        for (final r in rows)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text([r.companyName, r.category].where((x) => x.isNotEmpty).join(' · '),
                    style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                StampPill(label: '${s.cards}: ${r.count}', color: context.tones.brandInk),
              ]),
              const SizedBox(height: 4),
              if (r.storeName.isNotEmpty) _kv(cs, s.store, r.storeName),
              if (r.ownerName.isNotEmpty) _kv(cs, s.owner, r.ownerName),
              if (r.userPhone.isNotEmpty) _kv(cs, s.phone, r.userPhone),
              if (r.operatorPhone.isNotEmpty) _kv(cs, s.user, r.operatorPhone),
              if (r.governorate.isNotEmpty) _kv(cs, s.governorate, governorateLabel(r.governorate, loc)),
              if (r.mainAgentName.isNotEmpty) _kv(cs, s.mainAgent, r.mainAgentName),
              if (r.subAgentName.isNotEmpty) _kv(cs, s.subAgent, r.subAgentName),
            ]),
          ),
      ],
    );
  }
}

// ── #5 Total sold (rollup of #4 by agent × gov × company × category) ──────────
class _TotalSoldReport extends StatelessWidget {
  final List<SalesRow> rows;
  final _RS s;
  const _TotalSoldReport({required this.rows, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    final totals = <String, int>{};
    final meta = <String, SalesRow>{};
    for (final r in rows) {
      final key = '${r.mainAgentName}|${r.subAgentName}|${r.governorate}|${r.companyName}|${r.category}';
      totals[key] = (totals[key] ?? 0) + r.count;
      meta.putIfAbsent(key, () => r);
    }
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        _TotalStrip(
          label: s.totalSoldCards,
          value: Formatters.money(totals.values.fold<int>(0, (a, v) => a + v)),
          subLabel: s.category,
          subValue: Formatters.money(totals.length),
        ),
        for (final key in totals.keys)
          Builder(builder: (_) {
            final r = meta[key]!;
            final agent = [r.mainAgentName, r.subAgentName].where((x) => x.isNotEmpty).join(' / ');
            return InkCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text([r.companyName, r.category].where((x) => x.isNotEmpty).join(' · '),
                      style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                  StampPill(label: '${s.cards}: ${Formatters.money(totals[key] ?? 0)}', color: context.tones.brandInk),
                ]),
                const SizedBox(height: 4),
                if (agent.isNotEmpty) _kv(cs, s.agent, agent),
                if (r.governorate.isNotEmpty) _kv(cs, s.governorate, governorateLabel(r.governorate, loc)),
              ]),
            );
          }),
      ],
    );
  }
}

// ── #6 Uploaded cards ────────────────────────────────────────────────────────
class _UploadsReport extends StatelessWidget {
  final List<UploadsRow> rows;
  final _RS s;
  const _UploadsReport({required this.rows, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        _TotalStrip(
          label: s.totalUploaded,
          value: Formatters.money(rows.fold<int>(0, (a, r) => a + r.count)),
          subLabel: s.category,
          subValue: Formatters.money(rows.length),
        ),
        for (final r in rows)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text([r.companyName, r.category].where((x) => x.isNotEmpty).join(' · '),
                    style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                StampPill(label: '${s.cards}: ${r.count}', color: IntesharColors.sage),
              ]),
              const SizedBox(height: 4),
              if (r.agentName.isNotEmpty) _kv(cs, s.mainAgent, r.agentName),
              if (r.governorate.isNotEmpty) _kv(cs, s.governorate, governorateLabel(r.governorate, loc)),
            ]),
          ),
      ],
    );
  }
}

Widget _kv(ColorScheme cs, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 96, child: Text(k, style: IntesharType.sans(11.5, color: cs.onSurfaceVariant))),
        Expanded(child: Text(v, style: IntesharType.sans(12.5, color: cs.onSurface, w: FontWeight.w600))),
      ]),
    );

// ── #7 Prices ────────────────────────────────────────────────────────────────
class _PricesReport extends StatelessWidget {
  final PricingCatalog catalog;
  final _RS s;
  final String agentLabel;
  const _PricesReport({required this.catalog, required this.s, this.agentLabel = ''});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (catalog.rows.isEmpty) return _empty(context, s);
    final groups = <String, List<CategoryPriceRow>>{};
    for (final r in catalog.rows) {
      groups.putIfAbsent(r.companyName.isNotEmpty ? r.companyName : s.uncategorized, () => []).add(r);
    }
    final loc = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        if (agentLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _kv(cs, s.agentLabel, agentLabel),
          ),
        for (final e in groups.entries) ...[
          SectionLabel(e.key),
          for (final row in e.value)
            InkCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.name, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700)),
                  const SizedBox(height: 8),
                  _priceHeader(s, cs),
                  for (final g in _govRows(row))
                    _priceRow(g.$1 == '' ? s.untagged : governorateLabel(g.$1, loc), g.$2, g.$3, g.$4, cs),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  List<(String, num, num?, num)> _govRows(CategoryPriceRow row) {
    final hasBreakdown = row.governorates.length > 1 ||
        (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);
    if (!hasBreakdown) return [('', row.officialPrice, row.agentPrice, row.effectivePrice)];
    return [for (final g in row.governorates) (g.governorate, g.officialPrice, g.agentPrice, g.effectivePrice)];
  }

  Widget _priceHeader(_RS s, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(flex: 3, child: Text(s.category, style: IntesharType.overline(color: cs.onSurfaceVariant))),
          Expanded(flex: 2, child: Text(s.base, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
          Expanded(flex: 2, child: Text(s.agent, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
          Expanded(flex: 2, child: Text(s.effective, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
        ]),
      );

  Widget _priceRow(String gov, num base, num? agent, num eff, ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(flex: 3, child: Text(gov, style: IntesharType.sans(12.5, color: cs.onSurface))),
          Expanded(flex: 2, child: Text(Formatters.money(base), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurfaceVariant))),
          Expanded(flex: 2, child: Text(agent == null ? '—' : Formatters.money(agent), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurface))),
          Expanded(flex: 2, child: Text(Formatters.money(eff), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700))),
        ]),
      );
}

// ── #8 Stock ─────────────────────────────────────────────────────────────────
/// #5 مخزن الكروت — the spec asks for the CARD ARTWORK with the available count
/// beneath each image ("تظهر جميع صور البطاقات المتوفرة بالنظام واسفل كل صورة عدد
/// الكروت المتوفر"), filtered by governorate — not a table (B-091).
class _StockReport extends StatelessWidget {
  final List<SkuSummary> summary;
  final Map<String, String> artBySku; // sku -> ProductDefinition.imageUrl
  /// B-103: the governorate filter now lives in the page's filter row with the
  /// date range, instead of inside this body — two filters, one place.
  final String gov;
  final _RS s;
  const _StockReport({
    required this.summary,
    required this.artBySku,
    required this.gov,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (summary.isEmpty) return _empty(context, s);

    int availOf(SkuSummary k) => govCount(k, gov, (g) => g.available, k.available);
    int totalOf(SkuSummary k) => govCount(k, gov, (g) => g.total, k.total);
    int usedOf(SkuSummary k) => govCount(k, gov, (g) => g.printed, k.printed);

    final shown = summary.where((sku) => availOf(sku) > 0).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (shown.isEmpty) return _empty(context, s);

    return GridView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 214, // +18 for the total/used line
      ),
      itemCount: shown.length,
      itemBuilder: (_, i) {
        final sku = shown[i];
        final art = artBySku[sku.sku] ?? '';
        return InkCard(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            // The card picture — the point of this report.
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(IntesharRadii.md),
                child: art.trim().isEmpty
                    ? Container(
                        width: double.infinity,
                        color: cs.surfaceContainerHighest,
                        child: Icon(Icons.style_outlined, size: 34, color: cs.onSurfaceVariant),
                      )
                    : Image.network(art,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.style_outlined,
                                  size: 34, color: cs.onSurfaceVariant),
                            )),
              ),
            ),
            const SizedBox(height: 8),
            Text(sku.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w700)),
            const SizedBox(height: 2),
            // The available count, directly beneath the image (the spec's
            // "اسفل كل صورة عدد الكروت المتوفر") — still the hero number.
            Text(Formatters.money(availOf(sku)),
                style: IntesharType.mono(17, color: context.tones.brandInk, w: FontWeight.w900)),
            const SizedBox(height: 1),
            // …with the two columns the export also carries (B-091), kept quiet
            // so they inform without competing with the available count.
            Text(
              '${s.total} ${Formatters.money(totalOf(sku))} · ${s.used} ${Formatters.money(usedOf(sku))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: IntesharType.sans(10.5, color: cs.onSurfaceVariant),
            ),
          ]),
        );
      },
    );
  }
}

// ── #9 Detailed ──────────────────────────────────────────────────────────────
class _DetailedReport extends StatelessWidget {
  final PricingCatalog catalog;
  final _RS s;
  const _DetailedReport({required this.catalog, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (catalog.rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        // B-099: was a full gold slab — the last big brand-filled surface left after
        // B-094 demoted the dashboard card, POS tally, sign-in and splash. White with
        // a brand accent rule, matching those; the NUMBER is the hero, not the panel.
        _TotalStrip(
          label: s.grandTotal,
          value: Formatters.iqd(catalog.inventoryWorth.round()),
        ),
        for (final row in catalog.rows)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(row.name, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                  if (row.companyName.isNotEmpty)
                    Text(row.companyName, style: IntesharType.mono(11, color: cs.onSurfaceVariant)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(flex: 3, child: Text('', style: IntesharType.overline(color: cs.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text(s.available, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text(s.effective, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                  Expanded(flex: 3, child: Text(s.value, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                ]),
                for (final g in _detailRows(row))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(g.$1 == '' ? s.untagged : governorateLabel(g.$1, loc), style: IntesharType.sans(12.5, color: cs.onSurface))),
                      Expanded(flex: 2, child: Text('${g.$2}', textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurface))),
                      Expanded(flex: 2, child: Text(Formatters.money(g.$3), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurfaceVariant))),
                      // B-099: 90px column at 360dp; "125,876,000 IQD" needs 95px and
                      // used to WRAP, breaking the row's alignment. Money shrinks to fit
                      // rather than wrapping or ellipsising — a clipped figure is a lie.
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(Formatters.iqd(g.$4.round()),
                              maxLines: 1,
                              style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700)),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  List<(String, int, num, num)> _detailRows(CategoryPriceRow row) {
    final hasBreakdown = row.governorates.length > 1 ||
        (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);
    if (!hasBreakdown) return [('', row.available, row.effectivePrice, row.lineValue)];
    return [for (final g in row.governorates) (g.governorate, g.available, g.effectivePrice, g.lineValue)];
  }
}

/// The summary figure that sits above a report's rows.
///
/// B-099 replaced the Detailed report's full-gold panel with this; B-100 reuses it
/// so Transfers and Sold/Total-sold finally answer "how much altogether" without
/// exporting to Excel and summing by hand. White surface + a brand accent rule,
/// matching the dashboard balance card after B-094 — the number is the hero, not
/// the panel behind it.
class _TotalStrip extends StatelessWidget {
  final String label;
  final String value;

  /// Optional second figure (e.g. row count beside a summed amount).
  final String? subLabel;
  final String? subValue;

  const _TotalStrip({
    required this.label,
    required this.value,
    this.subLabel,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(IntesharRadii.lg),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: IntesharShadows.elev1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: context.tones.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: IntesharType.overline(color: cs.onSurfaceVariant)),
                const SizedBox(height: 3),
                // Totals are the widest numbers on the screen — shrink, never clip.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                        fontFamily: 'CodecPro',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        height: 1),
                  ),
                ),
              ],
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subLabel != null)
                  Text(subLabel!, style: IntesharType.overline(color: cs.onSurfaceVariant)),
                const SizedBox(height: 3),
                Text(subValue!,
                    maxLines: 1,
                    style: IntesharType.mono(15, color: cs.onSurface, w: FontWeight.w800)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Widget _empty(BuildContext context, _RS s) {
  final cs = Theme.of(context).colorScheme;
  return ListView(
    children: [
      const SizedBox(height: 80),
      Center(child: Icon(Icons.assessment_outlined, size: 48, color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),
      Center(child: Text(s.empty, style: IntesharType.sans(14, color: cs.onSurfaceVariant))),
    ],
  );
}
