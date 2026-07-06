import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/agents/data/agent_repository.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// The Reports section (client spec `Docs/سستم.xlsx` → التقارير). Phase 1 wires the
/// three reports whose data already exists on the backend: Prices (#7), Stock (#8),
/// Detailed (#9). Phases 2-3 add the balance/transfer/sales/upload tabs — see
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
  String get subtitle => p('Prices, stock and detailed valuation', 'الأسعار والمخزون والتقييم المفصّل');
  String get tabPrices => p('Prices', 'الأسعار');
  String get tabStock => p('Stock', 'المخزون');
  String get tabDetailed => p('Detailed', 'مفصّل');
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
  String get notSet => p('—', '—');
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  int _tab = 0;
  String? _targetId; // null = own entity
  PricingCatalog? _catalog;
  List<SkuSummary>? _summary;
  bool _loading = true;
  Object? _error;

  // HQ target picker: (id, label) options = self + main + sub agents.
  List<(String, String)> _pickables = const [];

  ReportsRepository get _repo => ReportsRepository(ref.read(apiClientProvider));

  Entity? get _me => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity;
  bool get _isHq => _me?.type == EntityType.INTESHAR;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (_isHq) {
      // Capture context-derived values before the async gap.
      final selfLabel = _RS.of(context).self;
      final me = _me;
      // Load the agent list once so HQ can scope any report to a specific agent.
      try {
        final repo = AgentRepository(ref.read(apiClientProvider));
        final mains = await repo.listAll('AGENT1');
        final subs = await repo.listAll('AGENT2');
        _pickables = [
          if (me != null) (me.id, '$selfLabel · ${me.meta.name}'),
          ...mains.map((e) => (e.id, e.name)),
          ...subs.map((e) => (e.id, e.name)),
        ];
      } catch (_) {
        // A failed agent list just leaves the picker at "self" — reports still load.
      }
    }
    await _load();
  }

  String get _effectiveId => _targetId ?? _me?.id ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = _effectiveId;
      final catalog = await _repo.priceCatalog(entityId: id);
      final summary = await _repo.stockSummary(entityId: id);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _RS.of(context);
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle),
          if (_isHq && _pickables.length > 1) _targetPicker(s),
          _tabBar(s),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _targetPicker(_RS s) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
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
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar(_RS s) {
    final labels = [s.tabPrices, s.tabStock, s.tabDetailed];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SegmentedButton<int>(
        segments: [
          for (var i = 0; i < labels.length; i++)
            ButtonSegment(value: i, label: Text(labels[i])),
        ],
        selected: {_tab},
        showSelectedIcon: false,
        onSelectionChanged: (sel) => setState(() => _tab = sel.first),
      ),
    );
  }

  Widget _body(_RS s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: switch (_tab) {
        0 => _PricesReport(catalog: _catalog!, s: s),
        1 => _StockReport(summary: _summary ?? const [], s: s),
        _ => _DetailedReport(catalog: _catalog!, s: s),
      },
    );
  }
}

// ── #7 Prices ────────────────────────────────────────────────────────────────
class _PricesReport extends StatelessWidget {
  final PricingCatalog catalog;
  final _RS s;
  const _PricesReport({required this.catalog, required this.s});

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
                    _priceRow(
                      g.$1 == '' ? s.untagged : governorateLabel(g.$1, loc),
                      g.$2, g.$3, g.$4, cs,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  // (gov, base, agentOrNull, effective) — the SKU-wide row first, then per-gov overrides.
  List<(String, num, num?, num)> _govRows(CategoryPriceRow row) {
    final hasBreakdown = row.governorates.length > 1 ||
        (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);
    if (!hasBreakdown) {
      return [('', row.officialPrice, row.agentPrice, row.effectivePrice)];
    }
    return [
      for (final g in row.governorates) (g.governorate, g.officialPrice, g.agentPrice, g.effectivePrice),
    ];
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
                  StampPill(label: '${s.available}: ${sku.available}', color: IntesharColors.sage),
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
                      Expanded(flex: 2, child: Text('${g.available}', textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700))),
                      Expanded(flex: 2, child: Text('${g.total}', textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurfaceVariant))),
                      Expanded(flex: 2, child: Text('${g.printed}', textAlign: TextAlign.end, style: IntesharType.mono(12.5, color: cs.onSurfaceVariant))),
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
        // Grand total = Σ line value = the page's transferable balance (spec).
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

  // (gov, available, effectivePrice, lineValue)
  List<(String, int, num, num)> _detailRows(CategoryPriceRow row) {
    final hasBreakdown = row.governorates.length > 1 ||
        (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);
    if (!hasBreakdown) {
      return [('', row.available, row.effectivePrice, row.lineValue)];
    }
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
