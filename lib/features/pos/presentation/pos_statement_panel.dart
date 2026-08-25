import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/pos/data/pos_self_repository.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

/// الحسابات (سستم A93): the shop's account statement — a date window, every
/// balance addition from the agent and every purchased card with its price,
/// and the running balance after each event.
class PosStatementPanel extends ConsumerStatefulWidget {
  const PosStatementPanel({super.key});

  @override
  ConsumerState<PosStatementPanel> createState() => _PosStatementPanelState();
}

/// UX-50: the windows an operator actually asks a statement for. The old 30-day
/// default is still here as "الشهر", but it is no longer where the screen opens.
enum _StatementPreset { today, yesterday, week, month, custom }

class _PosStatementPanelState extends ConsumerState<PosStatementPanel> {
  List<StatementRow> _rows = const [];
  bool _loading = true;
  Object? _error;
  late DateTimeRange _range;
  _StatementPreset _preset = _StatementPreset.today;

  @override
  void initState() {
    super.initState();
    _range = _rangeFor(_StatementPreset.today);
    _load();
  }

  static DateTimeRange _rangeFor(_StatementPreset p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (p) {
      _StatementPreset.today => DateTimeRange(start: today, end: today),
      _StatementPreset.yesterday => DateTimeRange(
          start: today.subtract(const Duration(days: 1)),
          end: today.subtract(const Duration(days: 1))),
      _StatementPreset.week =>
        DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      _StatementPreset.month =>
        DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today),
      _StatementPreset.custom => DateTimeRange(start: today, end: today),
    };
  }

  Future<void> _applyPreset(_StatementPreset p) async {
    setState(() {
      _preset = p;
      _range = _rangeFor(p);
    });
    await _load();
  }

  String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await PosSelfRepository(ref.read(apiClientProvider))
          .statement(from: _day(_range.start), to: _day(_range.end));
      if (!mounted) return;
      setState(() {
        _rows = rows.reversed.toList(); // newest first for display
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

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _range = picked;
      _preset = _StatementPreset.custom;
    });
    await _load();
  }

  Widget _presetRow(bool ar, ColorScheme cs) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (p, label) in [
            (_StatementPreset.today, ar ? 'اليوم' : 'Today'),
            (_StatementPreset.yesterday, ar ? 'أمس' : 'Yesterday'),
            (_StatementPreset.week, ar ? '٧ أيام' : '7 days'),
            (_StatementPreset.month, ar ? 'الشهر' : 'Month'),
          ])
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                selected: _preset == p,
                onSelected: (_) => _applyPreset(p),
                label: Text(label),
                labelStyle: IntesharType.sans(12.5,
                    color: _preset == p ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                    w: FontWeight.w700),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 28),
        children: [
          _presetRow(ar, cs),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text('${_day(_range.start)} → ${_day(_range.end)}'),
          ),
          const SizedBox(height: 12),
          if (_rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  ar ? 'لا توجد حركات في هذه الفترة.' : 'No activity in this window.',
                  style: IntesharType.sans(14, color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final r in _rows) _rowCard(r, ar, cs),
        ],
      ),
    );
  }

  Widget _rowCard(StatementRow r, bool ar, ColorScheme cs) {
    final grant = r.type == 'GRANT';
    // Semantic tones: money in is a success, money out is the danger tone the
    // rest of the app uses for an outgoing/destructive row.
    final tint = grant ? context.status.success : context.status.danger;
    final when = r.at.length >= 16 ? r.at.substring(0, 16).replaceFirst('T', ' ') : r.at;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkCard(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(grant ? Icons.south_west : Icons.receipt_long,
                size: 17, color: tint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                grant
                    ? (ar ? 'رصيد من ${r.label}' : 'Balance from ${r.label}')
                    : r.label +
                        (r.receiptNo != null ? '  ·  #${r.receiptNo}' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.sans(13.5, color: cs.onSurface, w: FontWeight.w600),
              ),
              const SizedBox(height: 1),
              Text(when, style: IntesharType.mono(11, color: cs.onSurfaceVariant)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              r.amount == null ? '—' : '${grant ? '+' : ''}${Formatters.iqd(r.amount!.round())}',
              style: IntesharType.mono(13, color: tint),
            ),
            const SizedBox(height: 1),
            // A93: show the balance BEFORE → AFTER this event (before is derived
            // from after − amount). Falls back to the after-value when the price
            // of a legacy sale is unknown.
            Text(
              r.amount == null
                  ? '${ar ? 'الرصيد' : 'Balance'}: ${Formatters.iqd(r.balanceAfter.round())}'
                  : '${Formatters.iqd((r.balanceAfter - r.amount!).round())} → ${Formatters.iqd(r.balanceAfter.round())}',
              style: IntesharType.mono(10.5, color: cs.onSurfaceVariant),
            ),
          ]),
        ]),
      ),
    );
  }
}
