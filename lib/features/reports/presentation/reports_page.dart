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
  // UX-36: this is `PricingCatalog.inventoryWorth` — the SAME server figure, on
  // the SAME basis, that the pricing screen labels قيمة المخزون. Calling it
  // "المجموع الكلي (الرصيد القابل للتحويل)" here made one number look like two
  // different things, and implied a relationship to the virtual balance it does
  // not have. Named after what it is, with its basis stated beneath.
  String get grandTotal => p('Stock value', 'قيمة المخزون');
  String get grandTotalBasis => p(
      'Available cards × their effective price — not the transferable balance.',
      'الكروت المتوفرة × سعرها الفعلي — وليس الرصيد القابل للتحويل.');
  String get untagged => p('No region', 'بدون محافظة');
  String get uncategorized => p('Uncategorized', 'بدون شركة');
  String get empty => p('Nothing to report yet.', 'لا توجد بيانات للتقرير بعد.');
  String get owner => p('Owner', 'المالك');
  String get phone => p('Phone', 'الهاتف');
  String get balance => p('Balance', 'الرصيد');
  // Export-only columns: the table has no room for them, the sheet does.
  String get spent => p('Spent', 'المصروف');
  String get posPoints => p('POS points', 'نقاط البيع');
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
  // UX-81: an export walks EVERY page of a paged feed — up to 200 sequential
  // requests — and used to change nothing on screen while it did.
  String get exporting => p('Exporting…', 'جارٍ التصدير…');
  String exportingRows(int n) =>
      p('Exporting… $n rows', 'جارٍ التصدير… $n صف');
  String get exportCancelled =>
      p('Export cancelled — no file saved', 'أُلغي التصدير — لم يُحفظ أي ملف');
  String get date => p('Date', 'التاريخ');
  String get time => p('Time', 'الوقت');
  String get from => p('From', 'من');
  String get to => p('To', 'إلى');
  String get source => p('Source', 'المصدر');
  String get destination => p('Destination', 'الوجهة');
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
  // UX-34: the roster serves BOTH balance tabs, so the tier has to be on the row —
  // otherwise a Main Agent and a Sub Agent are indistinguishable.
  String get tier => p('Type', 'النوع');
  String get hq => p('Headquarters', 'الإدارة');
  // UX-35: `ordersSpent` / `grantsOut` / `storeCount` were parsed, exported and
  // never shown — so the roster gave one number per account and no answer to
  // "made of what". Same three words the dashboard balance card uses (UX-20),
  // so the two screens describe the same money the same way.
  String get credited => p('Credited', 'المُضاف');
  String get givenOut => p('Given out', 'المُحوَّل');
  String get rosterComposition => p(
      'Balance = credited − given to its own accounts − spent.',
      'الرصيد = المُضاف − المُحوَّل إلى حساباته − المصروف.');
  // UX-43: the pricing screen states its export scope on screen; the reports now
  // do the same, so a filtered view and its sheet can't quietly differ.
  String exportFollows(String scope) =>
      p('Export follows: $scope', 'التصدير يتبع: $scope');
  // UX-39: a sorted column over a paged feed is sorted over what is LOADED.
  String sortedOf(int n) => p(
      'Sorted over the $n rows loaded so far — not the whole report.',
      'الترتيب على $n صفًا محمّلًا فقط — وليس على كامل التقرير.');
  String get sortBy => p('Sort', 'ترتيب');
  String get sortNone => p('Original order', 'الترتيب الأصلي');
  // UX-33: a paged total is a total of what is LOADED, not of what exists. Say so
  // on screen rather than letting a finance user read page 1 as the whole figure.
  String partialOf(int n) => p(
      'Partial — over the $n rows loaded so far. Load more, or export for the full figure.',
      'جزئي — على $n صفًا محمّلًا حتى الآن. حمّل المزيد، أو صدّر الملف للرقم الكامل.');
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

/// A built sheet. UX-42: a cell is a `String` (identity: names, phones, dates) or
/// a `num` (a REAL number in the workbook — see `XlsxCell`). Amounts are handed
/// over unformatted; the number format does the grouping, so the sheet reads like
/// the screen and still sums, sorts and pivots.
class _Export {
  final List<String> headers;
  final List<List<XlsxCell>> rows;
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
  /// [onProgress] reports the running row count so the Export button can say how
  /// far it has got (UX-81) — 200 silent round-trips is what made users re-tap.
  Future<List<dynamic>> _fetchAllPages(String src,
      {required void Function() onCapped, void Function(int)? onProgress}) async {
    const maxPages = 200; // 20k rows at _pageSize
    final out = <dynamic>[];
    for (var p = 0; p < maxPages; p++) {
      final res = await _fetchPage(src, p);
      out.addAll(_filterPage(src, res.items));
      onProgress?.call(out.length);
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

  /// UX-81: the report key whose export is in flight, or null.
  ///
  /// `_export` sets no busy state at all, and for a paged feed it fires up to 200
  /// sequential requests. The button stayed enabled and its label never changed,
  /// so an operator with nothing to look at re-tapped and launched a SECOND full
  /// walk of the same feed alongside the first.
  String? _exporting;

  /// Rows pulled so far by the in-flight export — the button counts up, which is
  /// the only honest way to show progress over an unknown number of pages.
  int _exportedRows = 0;

  Future<void> _export(String key, _RS s) async {
    if (_exporting != null) return; // re-entrancy guard, not just a disabled button
    final loc = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final src = _sourceKey(key);
    final isPaged = src == 'posBalances' || src == 'agentBalances' || src == 'transfers';
    dynamic data;
    var capped = false;
    setState(() {
      _exporting = key;
      _exportedRows = 0;
    });
    try {
      // B-097: a paged report must export EVERY page. Exporting only what happens to
      // be on screen produces a sheet that looks complete and silently isn't — which
      // on an audit trail is worse than not exporting at all.
      data = isPaged
          ? await _fetchAllPages(src,
              onCapped: () => capped = true,
              onProgress: (n) {
                if (mounted) setState(() => _exportedRows = n);
              })
          : await _futureFor(key); // resolves instantly from the cache once loaded
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = null);
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
      return;
    }
    final built = _exportRows(key, data, s, loc);
    if (!mounted) return;
    if (built == null || built.rows.isEmpty) {
      setState(() => _exporting = null);
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
      if (mounted) {
        // UX-81: a null path is the save dialog being CANCELLED (or nothing
        // written). Saying nothing at all left that indistinguishable from a
        // failed export — and from a hung one.
        messenger.showSnackBar(SnackBar(
            content: Text(path == null
                ? s.exportCancelled
                // Never let a capped export pass as a complete one.
                : (capped ? s.exportTruncated : s.exported))));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  /// The label of the tab [key] belongs to. UX-34: the balances roster and its
  /// XLSX are shared by two tabs, so the identity column has to be named after
  /// the tab in view rather than hardcoded to "POS balances".
  String _labelFor(String key, _RS s) {
    for (final t in _tabsFor(s)) {
      if (t.key == key) return t.label;
    }
    return '';
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
  ///
  /// UX-42: money and counts go in as `num`, never as pre-grouped text — a text
  /// column is why nothing summed in Excel.
  /// UX-43: the sheet follows the screen's FILTERS — the stock sheet ignoring the
  /// on-screen governorate was the real defect. It does not follow the screen's
  /// columns: identity noise the operator cannot preview (`address`,
  /// `operatorPhone`) is dropped, but quantities stay, because an export is for
  /// arithmetic and a missing column breaks a formula silently.
  _Export? _exportRows(String key, dynamic data, _RS s, String loc) {
    String gov(String g) => g.isEmpty ? s.untagged : governorateLabel(g, loc);

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
        final rows = <List<XlsxCell>>[
          for (final r in c.rows)
            for (final g in priceGovs(r))
              // An unset agent price stays BLANK rather than 0 — a zero would
              // both look like a real price and drag any average down.
              [agent, r.companyName, r.name, gov(g.$1), g.$2, g.$3 ?? '', g.$4],
        ];
        return _Export([s.agentLabel, s.company, s.category, s.governorate, s.base, s.agent, s.effective], rows, 'prices');
      case 'stock':
        final list = (data as List<SkuSummary>?) ?? const [];
        // UX-43: the SAME projection the grid renders, governorate filter included.
        final rows = <List<XlsxCell>>[
          for (final l in stockExportLines(list, _stockGov))
            [l.name, gov(l.governorate), l.available, l.total, l.used],
        ];
        return _Export([s.category, s.governorate, s.available, s.total, s.used], rows, 'stock');
      case 'detailed':
        final c = data as PricingCatalog?;
        if (c == null) return null;
        final rows = <List<XlsxCell>>[
          for (final r in c.rows)
            for (final g in detailGovs(r)) [r.name, gov(g.$1), g.$2, g.$3, g.$4],
        ];
        rows.add([s.grandTotal, '', '', '', c.inventoryWorth]);
        return _Export([s.category, s.governorate, s.available, s.effective, s.value], rows, 'detailed');
      case 'posBalances':
      case 'agentBalances':
        final list = (data as List<BalanceRosterRow>?) ?? const [];
        // UX-34: name the identity column after the TAB, and carry the tier —
        // without it an AGENT1 and an AGENT2 row are identical in the sheet too.
        final rows = <List<XlsxCell>>[
          for (final r in list)
            [r.name, _tierLabel(r.tier, s), r.ownerName, r.userPhone, gov(r.governorate),
              r.mainAgentName, r.subAgentName, r.available, r.ordersSpent, r.storeCount,
              r.grantsOut],
        ];
        // Spent and POS points stay in the SHEET even though the table has no
        // room for them. A screen is for attention and an export is for
        // arithmetic: an extra column costs a reader nothing, while removing one
        // silently breaks whatever formula downstream already points at it — and
        // "spent" beside "balance" is the pair reconciliation is actually done on.
        // UX-35: `givenOut` is APPENDED, not slotted in beside the other money —
        // an existing column's position is load-bearing for whatever formula
        // downstream already points at this sheet.
        return _Export(
            [_labelFor(key, s), s.tier, s.owner, s.phone, s.governorate, s.mainAgent,
              s.subAgent, s.balance, s.spent, s.posPoints, s.givenOut],
            rows, key);
      case 'transfers':
        final list = (data as List<TransferRow>?) ?? const [];
        final rows = <List<XlsxCell>>[
          for (final r in list)
            [r.date, r.time, r.sourceName, r.destName, r.amount, r.balanceAfter,
              r.destOwnerName, r.destPhone, gov(r.destGovernorate), r.mainAgentName, r.subAgentName],
        ];
        return _Export(
            [s.date, s.time, s.source, s.destination, s.transferAmount, s.balanceAfter, s.owner, s.phone, s.governorate, s.mainAgent, s.subAgent],
            rows, 'transfers');
      case 'sold':
        final list = (data as List<SalesRow>?) ?? const [];
        final rows = <List<XlsxCell>>[
          for (final r in list)
            [r.storeName, r.ownerName, r.userPhone, gov(r.governorate), r.companyName, r.category,
              r.mainAgentName, r.subAgentName, r.count],
        ];
        return _Export(
            [s.store, s.owner, s.phone, s.governorate, s.company, s.category, s.mainAgent, s.subAgent, s.cards],
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
        final rows = <List<XlsxCell>>[
          for (final k in totals.keys)
            [meta[k]!.mainAgentName, meta[k]!.subAgentName, gov(meta[k]!.governorate),
              meta[k]!.companyName, meta[k]!.category, totals[k] ?? 0],
        ];
        return _Export([s.mainAgent, s.subAgent, s.governorate, s.company, s.category, s.cards], rows, 'total_sold');
      case 'uploaded':
        final list = (data as List<UploadsRow>?) ?? const [];
        final rows = <List<XlsxCell>>[
          for (final r in list)
            [r.agentName, gov(r.governorate), r.companyName, r.category, r.count],
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Column(children: [
        Row(children: [
          if (_isDated(key))
            Expanded(child: _dateBar(s))
          else if (key == 'stock')
            Expanded(child: _stockGovBar(s))
          else
            const Spacer(),
          const SizedBox(width: 8),
          // UX-81: while an export is walking the feed the button spins, counts
          // the rows it has pulled, and refuses further taps — a second tap used
          // to start a whole parallel pull of the same 200 pages.
          OutlinedButton.icon(
            icon: _exporting != null
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 16),
            label: Text(
              _exporting == null
                  ? s.export
                  : (_exportedRows > 0 ? s.exportingRows(_exportedRows) : s.exporting),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: (_booting || _exporting != null) ? null : () => _export(key, s),
          ),
        ]),
        // UX-43: say what the sheet will contain, the way the pricing screen does.
        // "Export" beside a filtered screen otherwise reads as "export everything",
        // and the two silently disagreeing is exactly what went wrong on stock.
        // Only when something actually narrows it — this bar is already the third
        // row of chrome on a 360dp phone (B-103).
        if (_exportScopeLabel(s, key) case final scope?)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4, bottom: 2),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                s.exportFollows(scope),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.sans(11.5, color: cs.onSurfaceVariant, w: FontWeight.w600),
              ),
            ),
          ),
      ]),
    );
  }

  /// What the export for [key] will cover, or null when nothing narrows it and
  /// the sheet is simply the whole report.
  String? _exportScopeLabel(_RS s, String key) {
    final loc = Localizations.localeOf(context).languageCode;
    final parts = <String>[
      if (_targetId != null && _currentAgentLabel.isNotEmpty) _currentAgentLabel,
      if (_isDated(key)) (_allDates ? s.allDates : '${_ymd(_from)} → ${_ymd(_to)}'),
      if (key == 'stock' && _stockGov.isNotEmpty) governorateLabel(_stockGov, loc),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
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
        // UX-33: a paged feed with more pages behind it means every figure folded
        // over the loaded rows is PARTIAL. The reports that show a headline total
        // say so instead of presenting page 1 as the whole story.
        final more = _accMore[_sourceKey(key)] ?? false;
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
            'transfers' => _TransfersReport(
                rows: (data as List<TransferRow>?) ?? const [], s: s, partial: more),
            'sold' => _SalesReport(rows: (data as List<SalesRow>?) ?? const [], s: s),
            'totalSold' => _TotalSoldReport(rows: (data as List<SalesRow>?) ?? const [], s: s),
            'uploaded' => _UploadsReport(rows: (data as List<UploadsRow>?) ?? const [], s: s),
            _ => _RosterReport(
                rows: (data as List<BalanceRosterRow>?) ?? const [],
                s: s,
                identityLabel: _labelFor(key, s),
                partial: more),
          },
        );
        // B-097: the paged feeds show the first page with a Load-more tail rather
        // than pulling the whole subtree/ledger up front. Export still walks every
        // page — see _fetchAllPages.
        if (!more) return body;
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

// ── Shared report surface ────────────────────────────────────────────────────

/// One column of a report.
///
/// [primary] is the row's identity (bold, leads the narrow layout). [numeric]
/// right-aligns and sets tabular figures so columns of money line up. [trailing]
/// is the row's headline figure — it stays on the first line when narrow.
class _RCol {
  final String label;
  final int flex;
  final bool numeric;
  final bool primary;
  final bool trailing;
  const _RCol(this.label, {this.flex = 2, this.numeric = false, this.primary = false, this.trailing = false});
}

class _RCell {
  final String text;
  final Color? color;

  /// UX-39: the underlying figure. Sorting on the rendered text would put
  /// "9,000" after "80,000", and a `+` or a currency word ahead of both.
  final num? value;
  const _RCell(this.text, {this.color, this.value});
}

/// The report surface, replacing card-per-record (B-104).
///
/// Reports are tabular data. Rendered as full-width cards the content pinned to
/// one edge and 50–70% of every card was empty white space, with 6–8 stacked
/// label/value rows per record reading like a debug dump. So:
///
/// - **wide**: one header row, then hairline-separated data rows with aligned
///   columns — the width does the work and figures line up for scanning;
/// - **narrow**: two lines per record (identity + headline figure, then the
///   remaining values joined by `·`), no per-row card chrome.
///
/// One component so all five list reports look identical and improve together.
/// Scrollable report: [leading] (totals / search) then the surface.
class _ReportTable extends StatelessWidget {
  final List<_RCol> columns;
  final List<List<_RCell>> rows;
  final Widget? leading;
  final Widget? emptyRows;
  final _RS s;

  /// UX-39: more pages exist behind these rows, so any sort is over a prefix.
  final bool partial;

  const _ReportTable({
    required this.columns,
    required this.rows,
    required this.s,
    this.leading,
    this.emptyRows,
    this.partial = false,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        children: [
          ?leading,
          _ReportSurface(
              columns: columns, rows: rows, emptyRows: emptyRows, s: s, partial: partial),
        ],
      );
}

/// The bordered table itself — no scroll view of its own, so it can also be
/// embedded in a list that already scrolls (Prices groups one per company).
class _ReportSurface extends StatefulWidget {
  final List<_RCol> columns;
  final List<List<_RCell>> rows;
  final Widget? emptyRows;
  final _RS s;

  /// UX-39: these rows are a prefix of the report (more pages behind them), so a
  /// sorted "lowest balance" is the lowest of what has been LOADED.
  final bool partial;

  const _ReportSurface({
    required this.columns,
    required this.rows,
    required this.s,
    this.emptyRows,
    this.partial = false,
  });

  @override
  State<_ReportSurface> createState() => _ReportSurfaceState();
}

/// UX-39: nothing in the app could be sorted, so "who has the lowest balance" and
/// "who sold most" could not be asked at all. Sorting is client-side over the rows
/// in hand — which is exactly why it is labelled as partial when more pages exist.
class _ReportSurfaceState extends State<_ReportSurface> {
  int? _sortIndex;
  bool _desc = true;

  static const _wide = 720.0;

  List<int> get _sortable => [
        for (var i = 0; i < widget.columns.length; i++)
          if (widget.columns[i].numeric) i,
      ];

  /// Tap cycles: descending (the useful default for money) → ascending → off.
  void _tapColumn(int i) => setState(() {
        if (_sortIndex != i) {
          _sortIndex = i;
          _desc = true;
        } else if (_desc) {
          _desc = false;
        } else {
          _sortIndex = null;
        }
      });

  List<List<_RCell>> get _rows {
    final i = _sortIndex;
    // Columns change with the data (the roster's tier column appears only on a
    // mixed roster), so a stale index must not sort by whatever now sits there.
    if (i == null || i >= widget.columns.length || !widget.columns[i].numeric) {
      return widget.rows;
    }
    int cmp(List<_RCell> a, List<_RCell> b) {
      final av = i < a.length ? a[i].value : null;
      final bv = i < b.length ? b[i].value : null;
      if (av != null && bv != null) return av.compareTo(bv);
      if (av != null) return -1;
      if (bv != null) return 1;
      return (i < a.length ? a[i].text : '').compareTo(i < b.length ? b[i].text : '');
    }

    return [...widget.rows]..sort((a, b) => _desc ? cmp(b, a) : cmp(a, b));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _rows;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= _wide;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(IntesharRadii.lg),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: IntesharShadows.elev1,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // A phone has no column header to tap, and every POS user is on one.
              if (!wide && _sortable.isNotEmpty && widget.rows.isNotEmpty) _narrowSortBar(cs),
              if (wide) _header(cs),
              // Sorting a partial feed answers "the lowest of the ones loaded",
              // which is a different question from the one being asked.
              if (_sortIndex != null && widget.partial) _partialSortNote(rows.length),
              if (rows.isEmpty && widget.emptyRows != null)
                widget.emptyRows!
              else
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                  wide ? _wideRow(cs, rows[i]) : _narrowRow(cs, rows[i]),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _partialSortNote(int n) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        color: IntesharColors.warn.withValues(alpha: 0.08),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 14, color: IntesharColors.warn),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.s.sortedOf(n),
                style: IntesharType.sans(11.5, color: IntesharColors.warn, w: FontWeight.w600)),
          ),
        ]),
      );

  Widget _narrowSortBar(ColorScheme cs) {
    final i = _sortIndex;
    final label = i == null
        ? widget.s.sortBy
        : '${widget.s.sortBy}: ${widget.columns[i].label} ${_desc ? '↓' : '↑'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 6, 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: PopupMenuButton<int>(
          tooltip: widget.s.sortBy,
          position: PopupMenuPosition.under,
          // -1 = back to the order the server returned.
          onSelected: (v) => setState(() {
            if (v < 0) {
              _sortIndex = null;
            } else if (_sortIndex == v) {
              _desc = !_desc;
            } else {
              _sortIndex = v;
              _desc = true;
            }
          }),
          itemBuilder: (_) => [
            for (final c in _sortable)
              PopupMenuItem(
                value: c,
                child: Row(children: [
                  Icon(
                    _sortIndex == c
                        ? (_desc ? Icons.arrow_downward : Icons.arrow_upward)
                        : Icons.swap_vert,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(widget.columns[c].label, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            if (_sortIndex != null)
              PopupMenuItem(value: -1, child: Text(widget.s.sortNone)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.swap_vert, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(11.5,
                        color: cs.onSurfaceVariant, w: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < widget.columns.length; i++)
              Expanded(
                flex: widget.columns[i].flex,
                child: _headerCell(cs, i),
              ),
          ],
        ),
      );

  /// A figure column is tappable to sort; everything else is a plain label.
  Widget _headerCell(ColorScheme cs, int i) {
    final col = widget.columns[i];
    final text = Text(
      col.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: col.numeric ? TextAlign.end : TextAlign.start,
      style: IntesharType.overline(
          color: _sortIndex == i ? context.tones.brandInk : cs.onSurfaceVariant),
    );
    if (!col.numeric) return text;
    return InkWell(
      onTap: () => _tapColumn(i),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(child: text),
          const SizedBox(width: 2),
          Icon(
            _sortIndex == i
                ? (_desc ? Icons.arrow_downward : Icons.arrow_upward)
                : Icons.unfold_more,
            size: 13,
            color: _sortIndex == i ? context.tones.brandInk : cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _wideRow(ColorScheme cs, List<_RCell> cells) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            for (var i = 0; i < widget.columns.length; i++)
              Expanded(
                flex: widget.columns[i].flex,
                child: _cellText(
                    cs, widget.columns[i], i < cells.length ? cells[i] : const _RCell('')),
              ),
          ],
        ),
      );

  Widget _cellText(ColorScheme cs, _RCol col, _RCell cell) {
    final style = col.numeric
        ? IntesharType.mono(12.5,
            color: cell.color ?? (col.primary || col.trailing ? cs.onSurface : cs.onSurfaceVariant),
            w: col.trailing ? FontWeight.w800 : FontWeight.w600)
        : IntesharType.sans(13,
            color: cell.color ?? (col.primary ? cs.onSurface : cs.onSurfaceVariant),
            w: col.primary ? FontWeight.w700 : FontWeight.w500);
    // Figures shrink rather than clip — a truncated amount is a lie (B-095/B-099).
    final text = Text(cell.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: col.numeric ? TextAlign.end : TextAlign.start,
        style: style);
    return col.numeric
        ? FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerEnd, child: text)
        : text;
  }

  /// Identity + headline figure on line 1; everything else muted on line 2.
  ///
  /// UX-41: the meta line used to join every remaining cell with `·` and NO
  /// labels, so an unlabelled `balanceAfter` sat between a governorate and an
  /// owner name while a second, equally unlabelled money figure led the row —
  /// two amounts on one row and no way to tell which was which. Figures now carry
  /// their column name (names and places still speak for themselves), and the
  /// headline figure is captioned with its own.
  Widget _narrowRow(ColorScheme cs, List<_RCell> cells) {
    final columns = widget.columns;
    String? at(bool Function(_RCol) test) {
      for (var i = 0; i < columns.length && i < cells.length; i++) {
        if (test(columns[i]) && cells[i].text.trim().isNotEmpty) return cells[i].text;
      }
      return null;
    }

    final title = at((c) => c.primary) ?? '';
    final trailing = at((c) => c.trailing);
    Color? trailingColor;
    String trailingLabel = '';
    for (var i = 0; i < columns.length && i < cells.length; i++) {
      if (columns[i].trailing) {
        trailingColor = cells[i].color;
        trailingLabel = columns[i].label;
      }
    }
    final meta = <String>[
      for (var i = 0; i < columns.length && i < cells.length; i++)
        if (!columns[i].primary && !columns[i].trailing && cells[i].text.trim().isNotEmpty)
          columns[i].numeric ? '${columns[i].label}: ${cells[i].text}' : cells[i].text,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (trailingLabel.isNotEmpty)
                        Text(trailingLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: IntesharType.overline(color: cs.onSurfaceVariant)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(trailing,
                            maxLines: 1,
                            style: IntesharType.mono(14,
                                color: trailingColor ?? cs.onSurface, w: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(meta.join('  ·  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.sans(11.5, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

// ── #1/#2 Balances roster ────────────────────────────────────────────────────

/// UX-34: the roster serves BOTH balance tabs, and `tier` is the only thing that
/// tells a Main Agent from a Sub Agent. Rendered whenever the roster is mixed.
String _tierLabel(String tier, _RS s) => switch (tier) {
      'INTESHAR' => s.hq,
      'AGENT1' => s.mainAgent,
      'AGENT2' => s.subAgent,
      'STORE' => s.store,
      _ => '',
    };

bool _mixedTiers(List<BalanceRosterRow> rows) =>
    rows.map((r) => r.tier).where((t) => t.isNotEmpty).toSet().length > 1;

class _RosterReport extends StatefulWidget {
  final List<BalanceRosterRow> rows;
  final _RS s;

  /// UX-34: the identity column is headed with the TAB's own label. Hardcoding
  /// "POS balances" put that header over a list of Main and Sub Agents.
  final String identityLabel;

  /// UX-33: more pages exist, so `rows` is a prefix of the roster — the search
  /// denominator counts what is LOADED, not what exists.
  final bool partial;
  const _RosterReport(
      {required this.rows, required this.s, this.identityLabel = '', this.partial = false});

  @override
  State<_RosterReport> createState() => _RosterReportState();
}

/// B-102: filters the rows ALREADY LOADED (name / owner / phone / governorate);
/// the Load-more tail keeps working, so a search that comes up empty on page 1
/// is a prompt to load more rather than a dead end.
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
    // Only worth a column when the list actually mixes tiers (the agent-balances
    // tab); a roster of nothing but shops would just repeat "Store" 200 times.
    final showTier = _mixedTiers(widget.rows);
    // UX-35: the two figures that make the balance mean something. Shown only
    // where they can be non-zero — a POS roster's `grantsOut` and `storeCount`
    // are structurally 0 (a shop grants nothing and hosts nothing), and three
    // columns of zeros would bury the ones that matter.
    final showGiven = widget.rows.any((r) => r.grantsOut != 0);
    final showStores = widget.rows.any((r) => r.storeCount > 0);

    return _ReportTable(
      s: s,
      partial: widget.partial,
      leading: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: s.searchRoster,
              // UX-33: "12/100+" — the trailing + says the denominator is the rows
              // loaded so far, not the size of the roster.
              suffixText: _q.isEmpty
                  ? null
                  : '${rows.length}/${widget.rows.length}${widget.partial ? '+' : ''}',
            ),
          ),
          const SizedBox(height: 6),
          // UX-35: name the arithmetic once, above the table, rather than leaving
          // three money columns with no stated relationship to each other.
          Text(s.rosterComposition,
              style: IntesharType.sans(11.5, color: cs.onSurfaceVariant, w: FontWeight.w600)),
        ]),
      ),
      columns: [
        _RCol(widget.identityLabel.isEmpty ? s.tabPosBalances : widget.identityLabel,
            flex: 4, primary: true),
        if (showTier) _RCol(s.tier, flex: 2),
        _RCol(s.owner, flex: 3),
        _RCol(s.phone, flex: 3),
        _RCol(s.governorate, flex: 2),
        _RCol(s.mainAgent, flex: 3),
        if (showStores) _RCol(s.posPoints, flex: 2, numeric: true),
        if (showGiven) _RCol(s.givenOut, flex: 3, numeric: true),
        // UX-24: "المصروف" reached the XLSX and was dropped from the table — so
        // "which of my shops is stuck?" (funded but not selling) could be asked
        // in Excel and nowhere on screen.
        _RCol(s.spent, flex: 3, numeric: true),
        _RCol(s.balance, flex: 3, numeric: true, trailing: true),
      ],
      rows: [
        for (final r in rows)
          [
            _RCell(r.name),
            if (showTier) _RCell(_tierLabel(r.tier, s)),
            _RCell(r.ownerName),
            _RCell(r.userPhone),
            _RCell(r.governorate.isEmpty ? '' : governorateLabel(r.governorate, loc)),
            _RCell([r.mainAgentName, r.subAgentName].where((x) => x.isNotEmpty).join(' / ')),
            if (showStores) _RCell(Formatters.money(r.storeCount), value: r.storeCount),
            if (showGiven) _RCell(Formatters.iqd(r.grantsOut.round()), value: r.grantsOut),
            _RCell(Formatters.iqd(r.ordersSpent.round()), value: r.ordersSpent),
            // UX-24: an account at zero cannot buy a card — flag it rather than
            // leaving it as one more number in a column of numbers.
            _RCell(Formatters.iqd(r.available.round()),
                value: r.available, color: r.available <= 0 ? cs.error : null),
          ],
      ],
      emptyRows: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Center(
          child: Text(s.noMatchLoaded,
              textAlign: TextAlign.center,
              style: IntesharType.sans(13, color: cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

// ── #3 Transfers ─────────────────────────────────────────────────────────────
class _TransfersReport extends StatelessWidget {
  final List<TransferRow> rows;
  final _RS s;

  /// UX-33: the ledger is paged, so "Total moved" folds over the pages loaded so
  /// far — while the export walks every page and stamps the complete figure. The
  /// two legitimately disagree, so the screen must say which one it is showing.
  final bool partial;
  const _TransfersReport({required this.rows, required this.s, this.partial = false});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    final arrow = Directionality.of(context) == TextDirection.rtl ? '←' : '→';
    final moved = rows.fold<num>(0, (a, r) => a + r.amount);
    return _ReportTable(
      s: s,
      partial: partial,
      leading: _TotalStrip(
        label: s.totalMoved,
        value: Formatters.iqd(moved.round()),
        subLabel: s.tabTransfers,
        subValue: Formatters.money(rows.length),
        note: partial ? s.partialOf(rows.length) : null,
      ),
      columns: [
        _RCol(s.date, flex: 3),
        _RCol('${s.source} $arrow ${s.destination}', flex: 5, primary: true),
        _RCol(s.owner, flex: 3),
        _RCol(s.governorate, flex: 2),
        _RCol(s.balanceAfter, flex: 3, numeric: true),
        _RCol(s.transferAmount, flex: 3, numeric: true, trailing: true),
      ],
      rows: [
        for (final r in rows)
          [
            _RCell('${r.date} · ${r.time}'),
            _RCell('${r.sourceName} $arrow ${r.destName}'),
            _RCell(r.destOwnerName),
            _RCell(r.destGovernorate.isEmpty ? '' : governorateLabel(r.destGovernorate, loc)),
            _RCell(Formatters.iqd(r.balanceAfter.round()), value: r.balanceAfter),
            _RCell('+${Formatters.iqd(r.amount.round())}',
                color: IntesharColors.sage, value: r.amount),
          ],
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
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    final sold = rows.fold<int>(0, (a, r) => a + r.count);
    return _ReportTable(
      s: s,
      leading: _TotalStrip(
        label: s.totalSoldCards,
        value: Formatters.money(sold),
        subLabel: s.store,
        subValue: Formatters.money(rows.map((r) => r.storeName).toSet().length),
      ),
      columns: [
        _RCol(s.store, flex: 4, primary: true),
        _RCol(s.company, flex: 3),
        _RCol(s.category, flex: 3),
        _RCol(s.governorate, flex: 2),
        _RCol(s.mainAgent, flex: 3),
        _RCol(s.cards, flex: 2, numeric: true, trailing: true),
      ],
      rows: [
        for (final r in rows)
          [
            _RCell(r.storeName),
            _RCell(r.companyName),
            _RCell(r.category),
            _RCell(r.governorate.isEmpty ? '' : governorateLabel(r.governorate, loc)),
            _RCell([r.mainAgentName, r.subAgentName].where((x) => x.isNotEmpty).join(' / ')),
            _RCell(Formatters.money(r.count), value: r.count),
          ],
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
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    final totals = <String, int>{};
    final meta = <String, SalesRow>{};
    for (final r in rows) {
      final key = '${r.mainAgentName}|${r.subAgentName}|${r.governorate}|${r.companyName}|${r.category}';
      totals[key] = (totals[key] ?? 0) + r.count;
      meta.putIfAbsent(key, () => r);
    }
    return _ReportTable(
      s: s,
      leading: _TotalStrip(
        label: s.totalSoldCards,
        value: Formatters.money(totals.values.fold<int>(0, (a, v) => a + v)),
        subLabel: s.category,
        subValue: Formatters.money(totals.length),
      ),
      columns: [
        _RCol('${s.company} · ${s.category}', flex: 4, primary: true),
        _RCol(s.mainAgent, flex: 3),
        _RCol(s.subAgent, flex: 3),
        _RCol(s.governorate, flex: 2),
        _RCol(s.cards, flex: 2, numeric: true, trailing: true),
      ],
      rows: [
        for (final key in totals.keys)
          [
            _RCell([meta[key]!.companyName, meta[key]!.category].where((x) => x.isNotEmpty).join(' · ')),
            _RCell(meta[key]!.mainAgentName),
            _RCell(meta[key]!.subAgentName),
            _RCell(meta[key]!.governorate.isEmpty ? '' : governorateLabel(meta[key]!.governorate, loc)),
            _RCell(Formatters.money(totals[key] ?? 0), value: totals[key] ?? 0),
          ],
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
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    return _ReportTable(
      s: s,
      leading: _TotalStrip(
        label: s.totalUploaded,
        value: Formatters.money(rows.fold<int>(0, (a, r) => a + r.count)),
        subLabel: s.category,
        subValue: Formatters.money(rows.length),
      ),
      columns: [
        _RCol('${s.company} · ${s.category}', flex: 4, primary: true),
        _RCol(s.mainAgent, flex: 3),
        _RCol(s.governorate, flex: 2),
        _RCol(s.cards, flex: 2, numeric: true, trailing: true),
      ],
      rows: [
        for (final r in rows)
          [
            _RCell([r.companyName, r.category].where((x) => x.isNotEmpty).join(' · ')),
            _RCell(r.agentName),
            _RCell(r.governorate.isEmpty ? '' : governorateLabel(r.governorate, loc)),
            _RCell(Formatters.money(r.count), color: IntesharColors.sage, value: r.count),
          ],
      ],
    );
  }
}

// ── #7 Prices ────────────────────────────────────────────────────────────────
/// B-104: was a card per SKU, each repeating the base/agent/effective column
/// header. One table per company instead — the header is stated once.
class _PricesReport extends StatelessWidget {
  final PricingCatalog catalog;
  final _RS s;
  final String agentLabel;
  const _PricesReport({required this.catalog, required this.s, this.agentLabel = ''});

  @override
  Widget build(BuildContext context) {
    if (catalog.rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    final groups = <String, List<CategoryPriceRow>>{};
    for (final r in catalog.rows) {
      groups.putIfAbsent(r.companyName.isNotEmpty ? r.companyName : s.uncategorized, () => []).add(r);
    }

    List<(String, num, num?, num)> govRows(CategoryPriceRow row) {
      final hasBreakdown = row.governorates.length > 1 ||
          (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);
      if (!hasBreakdown) return [('', row.officialPrice, row.agentPrice, row.effectivePrice)];
      return [for (final g in row.governorates) (g.governorate, g.officialPrice, g.agentPrice, g.effectivePrice)];
    }

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        if (agentLabel.isNotEmpty)
          _TotalStrip(label: s.agentLabel, value: agentLabel),
        for (final e in groups.entries) ...[
          SectionLabel(e.key),
          _ReportSurface(
            s: s,
            columns: [
              _RCol(s.category, flex: 4, primary: true),
              _RCol(s.governorate, flex: 3),
              _RCol(s.base, flex: 2, numeric: true),
              _RCol(s.agent, flex: 2, numeric: true),
              _RCol(s.effective, flex: 2, numeric: true, trailing: true),
            ],
            rows: [
              for (final row in e.value)
                for (final g in govRows(row))
                  [
                    _RCell(row.name),
                    _RCell(g.$1.isEmpty ? s.untagged : governorateLabel(g.$1, loc)),
                    _RCell(Formatters.money(g.$2), value: g.$2),
                    _RCell(g.$3 == null ? '—' : Formatters.money(g.$3!), value: g.$3),
                    _RCell(Formatters.money(g.$4), value: g.$4),
                  ],
            ],
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
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

    // UX-43: shared with the export, so the sheet can never hold stock the
    // filtered grid excluded (or miss stock the grid shows).
    final shown = visibleStock(summary, gov);
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
    if (catalog.rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;

    List<(String, int, num, num)> detailRows(CategoryPriceRow row) {
      final hasBreakdown = row.governorates.length > 1 ||
          (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);
      if (!hasBreakdown) return [('', row.available, row.effectivePrice, row.lineValue)];
      return [for (final g in row.governorates) (g.governorate, g.available, g.effectivePrice, g.lineValue)];
    }

    return _ReportTable(
      s: s,
      leading: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _TotalStrip(
          label: s.grandTotal,
          value: Formatters.iqd(catalog.inventoryWorth.round()),
          subLabel: s.category,
          subValue: Formatters.money(catalog.rows.length),
        ),
        // UX-36: state the basis. Two screens showed money under names that
        // sounded identical on different bases, and a third gave this one a name
        // that pointed at the balance instead of at the stock.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(s.grandTotalBasis,
              style: IntesharType.sans(11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  w: FontWeight.w600)),
        ),
      ]),
      columns: [
        _RCol(s.category, flex: 4, primary: true),
        _RCol(s.governorate, flex: 3),
        _RCol(s.available, flex: 2, numeric: true),
        _RCol(s.effective, flex: 2, numeric: true),
        _RCol(s.value, flex: 3, numeric: true, trailing: true),
      ],
      rows: [
        for (final row in catalog.rows)
          for (final g in detailRows(row))
            [
              _RCell(row.name),
              _RCell(g.$1.isEmpty ? s.untagged : governorateLabel(g.$1, loc)),
              _RCell(Formatters.money(g.$2), value: g.$2),
              _RCell(Formatters.money(g.$3), value: g.$3),
              _RCell(Formatters.iqd(g.$4.round()), value: g.$4),
            ],
      ],
    );
  }
}

class _TotalStrip extends StatelessWidget {
  final String label;
  final String value;

  /// Optional second figure (e.g. row count beside a summed amount).
  final String? subLabel;
  final String? subValue;

  /// UX-33: a caveat printed WITH the figure — used when the number is folded
  /// over loaded pages only. A headline total that is silently partial is the
  /// one thing a finance user cannot recover from by reading more carefully.
  final String? note;

  const _TotalStrip({
    required this.label,
    required this.value,
    this.subLabel,
    this.subValue,
    this.note,
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(
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
          // Grouped at the start rather than flung to opposite edges — on a wide
          // screen an Expanded main column left the sub-figure stranded ~900px away.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.overline(color: cs.onSurfaceVariant)),
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
            const SizedBox(width: 24),
            Container(width: 1, height: 30, color: cs.outlineVariant),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
          const Spacer(),
        ],
      ),
      if (note != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.info_outline, size: 14, color: IntesharColors.warn),
          const SizedBox(width: 6),
          Expanded(
            child: Text(note!,
                style: IntesharType.sans(11.5, color: IntesharColors.warn, w: FontWeight.w600)),
          ),
        ]),
      ],
      ]),
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

// ─────────────────────────────────────────────────────────────────────────────
// Design harness. NOT routed in the app — reaching the real /hq/reports needs a
// login, which makes reviewing these visuals awkward and made the B-104 redesign
// fly blind for two rounds. Renders every report body against fixed sample data:
//
//   flutter build web -t lib/main_reports_preview.dart   (then serve build/web)
//
// It is also the fixture for report_table_responsive_test.dart, which pins both
// sides of the wide/narrow branch — so keep it in step with the report widgets.
// ─────────────────────────────────────────────────────────────────────────────

class ReportsPreviewPage extends StatelessWidget {
  const ReportsPreviewPage({super.key});

  static final _roster = [
    const BalanceRosterRow(
        entityId: 'st1', name: 'مكتب سعد للاتصالات', ownerName: 'أحمد علي حسن',
        userPhone: '07701234567', governorate: 'BAGHDAD', address: 'الكرادة، شارع 62',
        tier: 'STORE', available: 25876000, ordersSpent: 4250000,
        mainAgentName: 'وكيل بغداد', subAgentName: 'الرصافة'),
    const BalanceRosterRow(
        entityId: 'st2', name: 'Noor Mobile Center', ownerName: 'Noor Kadhim',
        userPhone: '07709876543', governorate: 'BASRA', address: 'Al Ashar, main st.',
        tier: 'STORE', available: 1250000, ordersSpent: 0,
        mainAgentName: 'Basra Main', subAgentName: 'Ashar Sub'),
    const BalanceRosterRow(
        entityId: 'st3', name: 'مكتب الفرات', ownerName: 'حسين عبد',
        userPhone: '07705554433', governorate: 'NAJAF', address: 'حي السلام',
        tier: 'STORE', available: 150000, ordersSpent: 980000,
        mainAgentName: 'وكيل النجف', subAgentName: ''),
  ];

  /// UX-34: the agent-balances tab feeds the SAME widget a mixed roster. Kept
  /// distinct from `_roster` so the tier column and the tab-specific header are
  /// visible in the preview instead of being taken on trust.
  static final _agentRoster = [
    const BalanceRosterRow(
        entityId: 'a1', name: 'وكيل بغداد', ownerName: 'كريم جاسم',
        userPhone: '07701110000', governorate: 'BAGHDAD', tier: 'AGENT1',
        available: 480000000, storeCount: 62, mainAgentName: 'وكيل بغداد'),
    const BalanceRosterRow(
        entityId: 'a2', name: 'الرصافة', ownerName: 'مثنى قيس',
        userPhone: '07702220000', governorate: 'BAGHDAD', tier: 'AGENT2',
        available: 96000000, storeCount: 18,
        mainAgentName: 'وكيل بغداد', subAgentName: 'الرصافة'),
  ];

  static final _transfers = [
    const TransferRow(
        id: 'g1', date: '2026-07-26', time: '14:05', sourceName: 'Inteshar HQ',
        destName: 'مكتب سعد للاتصالات', amount: 5000000, balanceAfter: 25876000,
        destAvailable: 25876000, destGovernorate: 'BAGHDAD', destOwnerName: 'أحمد علي حسن',
        destPhone: '07701234567', mainAgentName: 'وكيل بغداد', subAgentName: 'الرصافة'),
    const TransferRow(
        id: 'g2', date: '2026-07-25', time: '09:41', sourceName: 'وكيل بغداد',
        destName: 'Noor Mobile Center', amount: 1250000, balanceAfter: 1250000,
        destAvailable: 1250000, destGovernorate: 'BASRA', destOwnerName: 'Noor Kadhim',
        destPhone: '07709876543', mainAgentName: 'Basra Main', subAgentName: 'Ashar Sub'),
  ];

  static final _sales = [
    const SalesRow(
        storeName: 'مكتب سعد للاتصالات', ownerName: 'أحمد علي حسن', userPhone: '07701234567',
        operatorPhone: '07701234567', governorate: 'BAGHDAD', companyName: 'Asiacell',
        category: 'Asia 5,000', mainAgentName: 'وكيل بغداد', subAgentName: 'الرصافة', count: 128),
    const SalesRow(
        storeName: 'Noor Mobile Center', ownerName: 'Noor Kadhim', userPhone: '07709876543',
        operatorPhone: '07709876543', governorate: 'BASRA', companyName: 'Zain',
        category: 'Zain 10,000', mainAgentName: 'Basra Main', subAgentName: 'Ashar Sub', count: 46),
  ];

  static final _uploads = [
    const UploadsRow(agentName: 'وكيل بغداد', governorate: 'BAGHDAD',
        companyName: 'Asiacell', category: 'Asia 5,000', count: 5000),
    const UploadsRow(agentName: 'Basra Main', governorate: 'BASRA',
        companyName: 'Zain', category: 'Zain 10,000', count: 1200),
  ];

  static const _catalog = PricingCatalog(inventoryWorth: 128760000, rows: [
    CategoryPriceRow(
        sku: 'AS5', name: 'Asia 5,000', companyName: 'Asiacell', officialPrice: 5000,
        agentPrice: 4800, effectivePrice: 4800, available: 12400, lineValue: 59520000,
        priced: true),
    CategoryPriceRow(
        sku: 'ZN10', name: 'Zain 10,000', companyName: 'Zain', officialPrice: 10000,
        effectivePrice: 10000, available: 6924, lineValue: 69240000, priced: true),
  ]);

  @override
  Widget build(BuildContext context) {
    final s = _RS.of(context);
    final sections = <(String, Widget)>[
      ('POS balances (roster)',
          _RosterReport(rows: _roster, s: s, identityLabel: s.tabPosBalances)),
      ('Agent balances',
          _RosterReport(rows: _agentRoster, s: s, identityLabel: s.tabAgentBalances)),
      ('Transfers', _TransfersReport(rows: _transfers, s: s, partial: true)),
      ('Sold cards', _SalesReport(rows: _sales, s: s)),
      ('Total sold', _TotalSoldReport(rows: _sales, s: s)),
      ('Uploaded', _UploadsReport(rows: _uploads, s: s)),
      ('Prices', _PricesReport(catalog: _catalog, s: s, agentLabel: 'وكيل بغداد')),
      ('Detailed', _DetailedReport(catalog: _catalog, s: s)),
    ];
    return DefaultTabController(
      length: sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports — design preview'),
          bottom: TabBar(isScrollable: true, tabs: [for (final (t, _) in sections) Tab(text: t)]),
        ),
        body: TabBarView(children: [for (final (_, w) in sections) w]),
      ),
    );
  }
}
