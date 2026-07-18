import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/files/report_export.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/agents/data/agent_repository.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
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
  String get store => p('Store', 'المكتب');
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
}

class _Tab {
  final String key;
  final String label;
  const _Tab(this.key, this.label);
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

  List<(String, String)> _pickables = const []; // (id, label) for the HQ target picker
  final Map<String, Future<dynamic>> _cache = {}; // per-tab futures, cleared on scope/date change
  bool _booting = true;

  ReportsRepository get _repo => ReportsRepository(ref.read(apiClientProvider));
  Entity? get _me => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity;
  bool get _isHq => _me?.type == EntityType.INTESHAR;
  String get _effectiveId => _targetId ?? _me?.id ?? '';

  List<_Tab> _tabsFor(_RS s) => [
        _Tab('prices', s.tabPrices),
        _Tab('stock', s.tabStock),
        _Tab('detailed', s.tabDetailed),
        _Tab('posBalances', s.tabPosBalances),
        // #2 agent balances: admin + main agent only.
        if (_isHq || _me?.type == EntityType.AGENT1) _Tab('agentBalances', s.tabAgentBalances),
        _Tab('transfers', s.tabTransfers),
        _Tab('sold', s.tabSold),
        _Tab('totalSold', s.tabTotalSold),
        // #6 uploaded cards: admin + main agent only.
        if (_isHq || _me?.type == EntityType.AGENT1) _Tab('uploaded', s.tabUploaded),
      ];

  // sold + totalSold share one /sales fetch; everything else is its own source.
  String _sourceKey(String tab) => (tab == 'sold' || tab == 'totalSold') ? 'sales' : tab;
  bool _isDated(String key) =>
      key == 'transfers' || key == 'sold' || key == 'totalSold' || key == 'uploaded';

  @override
  void initState() {
    super.initState();
    // Default the dated reports to the last 30 days so nothing loads a full history
    // (the backend applies the same default if these are omitted).
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
    if (_isHq) {
      final selfLabel = _RS.of(context).self;
      final me = _me;
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
    }
    if (mounted) setState(() => _booting = false);
  }

  void _invalidate() => setState(() => _cache.clear());

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
          return _repo.balancesRoster(rootId: id, type: 'STORE');
        case 'agentBalances':
          return _repo.balancesRoster(rootId: id).then((rows) =>
              rows.where((r) => r.tier == 'AGENT1' || r.tier == 'AGENT2').toList());
        case 'transfers':
          return _repo.transfers(rootId: id, from: _ymd(_from), to: _ymd(_to));
        case 'sales':
          return _repo.sales(rootId: id, from: _ymd(_from), to: _ymd(_to));
        case 'uploaded':
          return _repo.uploads(rootId: id, from: _ymd(_from), to: _ymd(_to));
        default:
          return Future.value(null);
      }
    });
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
    dynamic data;
    try {
      data = await _futureFor(key); // resolves instantly from the cache once loaded
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
    try {
      final path = await exportRowsToXlsx(
          fileName: built.file, sheetName: built.file, headers: built.headers, rows: built.rows);
      if (mounted && path != null) messenger.showSnackBar(SnackBar(content: Text(s.exported)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
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
          if (_isHq && _pickables.length > 1) _targetPicker(s),
          Row(children: [
            Expanded(child: _tabBar(tabs)),
            IconButton(
              tooltip: s.export,
              icon: const Icon(Icons.download_outlined),
              onPressed: _booting ? null : () => _export(key, s),
            ),
            const SizedBox(width: 8),
          ]),
          if (_isDated(key)) _dateBar(s),
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

  Widget _tabBar(List<_Tab> tabs) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (var i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: ChoiceChip(
                label: Text(tabs[i].label),
                selected: _tab == i,
                onSelected: (_) => setState(() => _tab = i),
                labelStyle: IntesharType.sans(12.5,
                    color: _tab == i ? cs.onSurface : cs.onSurfaceVariant, w: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateBar(_RS s) {
    final cs = Theme.of(context).colorScheme;
    final label = (_from != null && _to != null) ? '${_ymd(_from)} → ${_ymd(_to)}' : s.allDates;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(children: [
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range, size: 16),
          label: Text(label),
        ),
        if (_from != null) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.clear, size: 18, color: cs.onSurfaceVariant),
            onPressed: () => setState(() {
              _from = null;
              _to = null;
              _cache.clear();
            }),
          ),
        ],
      ]),
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
        return RefreshIndicator(
          onRefresh: () async => setState(() => _cache.remove(_sourceKey(key))),
          child: switch (key) {
            'prices' => _PricesReport(catalog: data as PricingCatalog, s: s, agentLabel: _currentAgentLabel),
            'stock' => _StockReport(summary: (data as List<SkuSummary>?) ?? const [], s: s),
            'detailed' => _DetailedReport(catalog: data as PricingCatalog, s: s),
            'transfers' => _TransfersReport(rows: (data as List<TransferRow>?) ?? const [], s: s),
            'sold' => _SalesReport(rows: (data as List<SalesRow>?) ?? const [], s: s),
            'totalSold' => _TotalSoldReport(rows: (data as List<SalesRow>?) ?? const [], s: s),
            'uploaded' => _UploadsReport(rows: (data as List<UploadsRow>?) ?? const [], s: s),
            _ => _RosterReport(rows: (data as List<BalanceRosterRow>?) ?? const [], s: s),
          },
        );
      },
    );
  }
}

// ── #1/#2 Balances roster ────────────────────────────────────────────────────
class _RosterReport extends StatelessWidget {
  final List<BalanceRosterRow> rows;
  final _RS s;
  const _RosterReport({required this.rows, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        for (final r in rows)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(r.name, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                  Text(Formatters.iqd(r.available.round()),
                      style: IntesharType.mono(15, color: IntesharColors.saffronDeep, w: FontWeight.w800)),
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
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
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
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        for (final r in rows)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text([r.companyName, r.category].where((x) => x.isNotEmpty).join(' · '),
                    style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                StampPill(label: '${s.cards}: ${r.count}', color: IntesharColors.saffronDeep),
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
                  StampPill(label: '${s.cards}: ${Formatters.money(totals[key] ?? 0)}', color: IntesharColors.saffronDeep),
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
class _StockReport extends StatelessWidget {
  final List<SkuSummary> summary;
  final _RS s;
  const _StockReport({required this.summary, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (summary.isEmpty) return _empty(context, s);
    final loc = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      children: [
        for (final sku in summary)
          InkCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(sku.name, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
                  StampPill(label: '${s.available}: ${Formatters.money(sku.available)}', color: IntesharColors.sage),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(flex: 3, child: Text('', style: IntesharType.overline(color: cs.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text(s.available, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text(s.total, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                  Expanded(flex: 2, child: Text(s.used, textAlign: TextAlign.end, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                ]),
                for (final g in sku.governorates)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(g.governorate.isEmpty ? s.untagged : governorateLabel(g.governorate, loc), style: IntesharType.sans(12.5, color: cs.onSurface))),
                      Expanded(flex: 2, child: Text(Formatters.money(g.available), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700))),
                      Expanded(flex: 2, child: Text(Formatters.money(g.total), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurfaceVariant))),
                      Expanded(flex: 2, child: Text(Formatters.money(g.printed), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurfaceVariant))),
                    ]),
                  ),
              ],
            ),
          ),
      ],
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
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(color: IntesharColors.saffron, borderRadius: BorderRadius.circular(IntesharRadii.lg)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.grandTotal, style: IntesharType.overline(color: IntesharColors.ink.withValues(alpha: 0.7))),
              const SizedBox(height: 2),
              Text(Formatters.iqd(catalog.inventoryWorth.round()),
                  style: const TextStyle(fontFamily: 'CodecPro', fontSize: 24, fontWeight: FontWeight.w900, color: IntesharColors.ink, height: 1)),
            ],
          ),
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
                      Expanded(flex: 3, child: Text(Formatters.iqd(g.$4.round()), textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700))),
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
