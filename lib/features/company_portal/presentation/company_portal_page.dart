import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/files/report_export.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/company_portal/data/company_portal_repository.dart';
import 'package:inteshar/features/company_portal/domain/company_portal_models.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

/// PROD-037: the ONE screen of a telecom company's account (Asiacell, Zain) — the cards of
/// its own card types uploaded into the system, per day, governorate and category. No
/// sales, no withdrawals, no agents, no shops (the client, 26 Nov 2026). The server
/// decides the company; this page cannot ask for another one.
///
/// HQ opens the same page with [companyId] to see exactly what that company sees
/// ([preview]: no sign-out, a back button instead).
class CompanyPortalPage extends ConsumerStatefulWidget {
  final String? companyId;
  const CompanyPortalPage({super.key, this.companyId});

  bool get preview => companyId != null && companyId!.isNotEmpty;

  @override
  ConsumerState<CompanyPortalPage> createState() => _CompanyPortalPageState();
}

/// '' in the governorate filter = the region-free cards; null = every governorate.
const _kNoGov = '';

class _CompanyPortalPageState extends ConsumerState<CompanyPortalPage> {
  late DateTime _from;
  late DateTime _to;
  String? _gov;
  Future<CompanyPortalInfo>? _info;
  Future<List<CompanyUploadRow>>? _rows;
  bool _exporting = false;

  CompanyPortalRepository get _repo => CompanyPortalRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    final today = _day(DateTime.now());
    _from = today;
    _to = today;
    _info = _repo.me(companyId: widget.companyId);
    _load();
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  void _load() {
    setState(() {
      _rows = _repo.uploads(
          from: Formatters.date(_from), to: Formatters.date(_to), companyId: widget.companyId);
    });
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;
  String get _loc => Localizations.localeOf(context).languageCode;

  String _govLabel(String code) =>
      code.isEmpty ? _t('بدون محافظة', 'No governorate') : governorateLabel(code, _loc);

  List<CompanyUploadRow> _filtered(List<CompanyUploadRow> rows) =>
      _gov == null ? rows : rows.where((r) => r.governorate == _gov).toList();

  void _setRange(DateTime from, DateTime to) {
    _from = _day(from);
    _to = _day(to);
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: _day(now),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) _setRange(picked.start, picked.end);
  }

  Future<void> _export(CompanyPortalInfo info, List<CompanyUploadRow> rows) async {
    final messenger = ScaffoldMessenger.of(context);
    if (rows.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(_t('لا يوجد ما يُحفظ', 'Nothing to save'))));
      return;
    }
    setState(() => _exporting = true);
    final from = Formatters.date(_from), to = Formatters.date(_to);
    final total = rows.fold<int>(0, (a, r) => a + r.count);
    final now = DateTime.now();
    try {
      final path = await exportRowsToXlsx(
        fileName: 'uploaded-cards-${from}_$to',
        sheetName: 'uploaded',
        headers: [
          _t('اليوم', 'Day'),
          _t('المحافظة', 'Governorate'),
          _t('الفئة', 'Category'),
          _t('عدد الكروت', 'Cards'),
        ],
        rows: [
          for (final r in rows) [r.day, _govLabel(r.governorate), r.category, r.count],
        ],
        provenance: [
          (_t('التقرير', 'Report'), _t('الكروت المرفوعة', 'Uploaded cards')),
          (_t('الشركة', 'Company'), info.companyName),
          (_t('الفترة', 'Dates'), '$from → $to'),
          (_t('المحافظة', 'Governorate'), _gov == null ? _t('الكل', 'All') : _govLabel(_gov!)),
          (_t('المجموع', 'Total'), Formatters.money(total)),
          (_t('وقت الإصدار', 'Generated'), Formatters.dateTime(now)),
        ],
      );
      if (path != null) {
        await _repo.exported(from: from, to: to, governorate: _gov, companyId: widget.companyId);
      }
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(path == null ? _t('أُلغي الحفظ', 'Save cancelled') : _t('تم حفظ الملف', 'File saved'))));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<CompanyPortalInfo>(
      future: _info,
      builder: (context, infoSnap) {
        final info = infoSnap.data ?? const CompanyPortalInfo();
        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            automaticallyImplyLeading: widget.preview,
            titleSpacing: widget.preview ? 0 : IntesharSpacing.lg,
            title: Row(children: [
              if (info.companyLogoUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: IntesharSpacing.sm),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(IntesharRadii.xs),
                    child: Image.network(info.companyLogoUrl,
                        height: 32, width: 32, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    info.companyName.isEmpty ? _t('الكروت المرفوعة', 'Uploaded cards') : info.companyName,
                    style: IntesharType.sans(16, w: IntesharWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.preview
                        ? _t('معاينة: ما تراه الشركة', 'Preview: what the company sees')
                        : _t('الكروت المرفوعة', 'Uploaded cards'),
                    style: IntesharType.sans(12, color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            actions: [
              if (!widget.preview)
                TextButton.icon(
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(_t('خروج', 'Sign out')),
                  onPressed: () => ref.read(authStateProvider.notifier).logout(),
                ),
              const SizedBox(width: IntesharSpacing.sm),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(children: [
                _filters(cs),
                Expanded(child: _results(cs, info)),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _filters(ColorScheme cs) {
    final today = _day(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    bool isRange(DateTime f, DateTime t) => _from == f && _to == t;
    Widget chip(String label, DateTime f, DateTime t) => ChoiceChip(
          label: Text(label),
          selected: isRange(f, t),
          onSelected: (_) => _setRange(f, t),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: IntesharSpacing.sm, runSpacing: IntesharSpacing.sm, children: [
          chip(_t('اليوم', 'Today'), today, today),
          chip(_t('أمس', 'Yesterday'), yesterday, yesterday),
          chip(_t('آخر 7 أيام', 'Last 7 days'), today.subtract(const Duration(days: 6)), today),
          chip(_t('هذا الشهر', 'This month'), DateTime(today.year, today.month), today),
        ]),
        const SizedBox(height: IntesharSpacing.sm),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                _from == _to
                    ? Formatters.date(_from)
                    : '${Formatters.date(_from)} → ${Formatters.date(_to)}',
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: _pickRange,
            ),
          ),
          const SizedBox(width: IntesharSpacing.sm),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _gov,
              isExpanded: true,
              decoration: InputDecoration(isDense: true, labelText: _t('المحافظة', 'Governorate')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(_t('كل المحافظات', 'All governorates'))),
                for (final g in kGovernorates)
                  DropdownMenuItem<String?>(value: g.code, child: Text(g.label(_loc), overflow: TextOverflow.ellipsis)),
                DropdownMenuItem<String?>(value: _kNoGov, child: Text(_govLabel(_kNoGov))),
              ],
              onChanged: (v) => setState(() => _gov = v),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _results(ColorScheme cs, CompanyPortalInfo info) {
    return FutureBuilder<List<CompanyUploadRow>>(
      future: _rows,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return ErrorState(error: snap.error!, onRetry: _load);
        final rows = _filtered(snap.data ?? const []);
        final total = rows.fold<int>(0, (a, r) => a + r.count);
        return RefreshIndicator(
          onRefresh: () async {
            _load();
            await _rows;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _totalStrip(cs, total, info, rows),
              const SizedBox(height: IntesharSpacing.md),
              if (rows.isEmpty)
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  message: _t('لا توجد كروت مرفوعة في هذه الفترة', 'No cards were uploaded in these dates'),
                  dense: true,
                )
              else
                _table(cs, rows),
              const SizedBox(height: IntesharSpacing.lg),
              Text(
                _t('يعرض هذا التقرير الكروت المرفوعة إلى النظام فقط، حسب يوم الرفع (بتوقيت بغداد).',
                    'This report shows only the cards uploaded into the system, by upload day (Baghdad time).'),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _totalStrip(ColorScheme cs, int total, CompanyPortalInfo info, List<CompanyUploadRow> rows) {
    return Container(
      padding: const EdgeInsets.all(IntesharSpacing.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_t('مجموع الكروت المرفوعة', 'Cards uploaded'),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(Formatters.money(total), style: IntesharType.sans(26, w: IntesharWeight.bold)),
          ]),
        ),
        FilledButton.tonalIcon(
          icon: _exporting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined, size: 18),
          label: Text(_t('حفظ Excel', 'Save Excel')),
          onPressed: _exporting ? null : () => _export(info, rows),
        ),
      ]),
    );
  }

  Widget _table(ColorScheme cs, List<CompanyUploadRow> rows) {
    final head = IntesharType.sans(12, color: cs.onSurfaceVariant, w: IntesharWeight.bold);
    final body = IntesharType.sans(14);
    Widget cell(String text, {int flex = 1, TextStyle? style, bool end = false}) => Expanded(
          flex: flex,
          child: Text(text,
              style: style ?? body,
              textAlign: end ? TextAlign.end : TextAlign.start,
              overflow: TextOverflow.ellipsis),
        );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            cell(_t('اليوم', 'Day'), flex: 3, style: head),
            cell(_t('المحافظة', 'Governorate'), flex: 3, style: head),
            cell(_t('الفئة', 'Category'), flex: 4, style: head),
            cell(_t('الكروت', 'Cards'), flex: 2, style: head, end: true),
          ]),
        ),
        for (final r in rows) ...[
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              cell(r.day, flex: 3),
              cell(_govLabel(r.governorate), flex: 3),
              cell(r.category, flex: 4),
              cell(Formatters.money(r.count), flex: 2, end: true, style: body.copyWith(fontWeight: IntesharWeight.bold)),
            ]),
          ),
        ],
      ]),
    );
  }
}
