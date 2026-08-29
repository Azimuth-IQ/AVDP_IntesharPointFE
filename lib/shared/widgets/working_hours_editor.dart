import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/entities/domain/entity.dart';

/// HQ editor for a per-account working-hours login window (BRD FR-03). Controlled:
/// the parent holds the [WorkingHours] value and persists it via `EntityMeta`.
/// Times are 24h "HH:mm" in Asia/Baghdad; an end before the start wraps past
/// midnight; no allowed days selected = every day; the switch off = always open.
class WorkingHoursEditor extends StatelessWidget {
  final WorkingHours? value;
  final ValueChanged<WorkingHours?> onChanged;
  const WorkingHoursEditor({super.key, required this.value, required this.onChanged});

  static const _dayLabelsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayLabelsAr = ['إث', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح'];

  TimeOfDay? _parse(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final wh = value ?? const WorkingHours();
    final labels = ar ? _dayLabelsAr : _dayLabelsEn;

    Future<void> pick(bool isStart) async {
      final init = _parse(isStart ? wh.start : wh.end) ?? const TimeOfDay(hour: 8, minute: 0);
      final picked = await showTimePicker(context: context, initialTime: init);
      if (picked == null) return;
      onChanged(wh.copyWith(
        enabled: true,
        start: isStart ? _fmt(picked) : wh.start,
        end: isStart ? wh.end : _fmt(picked),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: wh.enabled,
          title: Text(ar ? 'تقييد ساعات الدخول' : 'Restrict login hours'),
          subtitle: Text(
            ar
                ? 'يمنع تسجيل الدخول خارج النافذة (توقيت بغداد)'
                : 'Blocks sign-in outside the window (Baghdad time)',
            style: IntesharText.body(color: cs.onSurfaceVariant),
          ),
          onChanged: (v) => onChanged(wh.copyWith(enabled: v)),
        ),
        if (wh.enabled) ...[
          const SizedBox(height: IntesharSpacing.sm),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('${ar ? 'من' : 'Open'}  ${wh.start.isEmpty ? '--:--' : wh.start}'),
                onPressed: () => pick(true),
              ),
            ),
            const SizedBox(width: IntesharSpacing.sm2),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 18),
                label: Text('${ar ? 'إلى' : 'Close'}  ${wh.end.isEmpty ? '--:--' : wh.end}'),
                onPressed: () => pick(false),
              ),
            ),
          ]),
          const SizedBox(height: IntesharSpacing.sm2),
          Text(
            ar ? 'الأيام المسموحة (لا شيء = كل الأيام)' : 'Allowed days (none = every day)',
            style: IntesharText.body(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (int d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(labels[d - 1]),
                  selected: wh.days.contains(d),
                  onSelected: (sel) {
                    final days = [...wh.days];
                    if (sel) {
                      days.add(d);
                    } else {
                      days.remove(d);
                    }
                    days.sort();
                    onChanged(wh.copyWith(days: days));
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
