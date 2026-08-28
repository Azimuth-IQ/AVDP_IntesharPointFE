import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/printing/printer_service.dart';

/// How a printer state should look. Kept separate from the colour so the
/// vocabulary is decided once and the palette stays a theme concern.
enum PrinterChipTone { ready, warn, inFlight, neutral }

extension PrinterChipToneColor on PrinterChipTone {
  Color color(BuildContext context) => switch (this) {
        PrinterChipTone.ready => context.status.success,
        PrinterChipTone.warn => context.status.warn,
        PrinterChipTone.inFlight => context.status.inFlight,
        PrinterChipTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
      };
}

/// What to SAY about the printer, in one place.
///
/// UX-55: every surface used to ask the same reduced question — `status ==
/// connected` — and print the same two answers. That flattened three genuinely
/// different situations into one:
///
/// * **unreachable** — a printer is chosen but did not answer the last probe.
///   It looked identical to "connected", green chip and all, until a code had
///   already been burned.
/// * **needsChoice** — auto-connect found several plausible printers and
///   deliberately picked none. A decision is waiting for the operator, and they
///   were told "no printer found", which is not the same sentence at all.
/// * **idle** — genuinely nothing to print to.
///
/// The strings are bilingual literals, matching the rest of the POS.
@immutable
class PrinterStatusInfo {
  /// Short form, for a chip.
  final String label;

  /// The fuller sentence a banner can afford, when there is something to add.
  final String? sentence;

  final IconData icon;
  final PrinterChipTone tone;

  const PrinterStatusInfo({
    required this.label,
    required this.icon,
    required this.tone,
    this.sentence,
  });
}

PrinterStatusInfo printerStatusInfo(PrinterState s, {required bool ar}) {
  final name = (s.deviceName ?? '').trim();
  switch (s.status) {
    case PrinterStatus.connected:
      return PrinterStatusInfo(
        label: name.isNotEmpty ? name : (ar ? 'الطابعة متصلة' : 'Printer connected'),
        icon: Icons.print_outlined,
        tone: PrinterChipTone.ready,
      );

    case PrinterStatus.unreachable:
      return PrinterStatusInfo(
        label: ar ? 'الطابعة لا تستجيب' : 'Printer not responding',
        icon: Icons.print_disabled_outlined,
        tone: PrinterChipTone.warn,
        sentence: ar
            ? 'لم نتمكن من الوصول إلى ${name.isNotEmpty ? name : 'الطابعة'} — تأكد أنها مشغّلة وقريبة. يمكنك البيع ثم نسخ أو مشاركة الرمز.'
            : 'Could not reach ${name.isNotEmpty ? name : 'the printer'} — check it is switched on and nearby. You can still sell, then copy or share the code.',
      );

    case PrinterStatus.needsChoice:
      return PrinterStatusInfo(
        label: ar ? 'اختر الطابعة' : 'Choose a printer',
        icon: Icons.help_outline,
        tone: PrinterChipTone.warn,
        sentence: ar
            ? 'وُجدت أكثر من طابعة ولم يتم اختيار أي منها — اختر واحدة قبل البيع.'
            : 'Several printers were found and none was picked — choose one before selling.',
      );

    case PrinterStatus.connecting:
      return PrinterStatusInfo(
        label: ar ? 'جارٍ ربط الطابعة…' : 'Connecting…',
        icon: Icons.print_outlined,
        tone: PrinterChipTone.inFlight,
      );

    case PrinterStatus.error:
      return PrinterStatusInfo(
        label: ar ? 'تعذّر ربط الطابعة' : 'Printer failed to connect',
        icon: Icons.print_disabled_outlined,
        tone: PrinterChipTone.warn,
        sentence: ar
            ? 'تعذّر ربط الطابعة — افتح الإعدادات وأعد المحاولة. يمكنك البيع ثم نسخ أو مشاركة الرمز.'
            : 'The printer could not be connected — open setup and try again. You can still sell, then copy or share the code.',
      );

    case PrinterStatus.idle:
      return PrinterStatusInfo(
        label: ar ? 'إعداد الطابعة' : 'Set up printer',
        icon: Icons.print_disabled_outlined,
        tone: PrinterChipTone.neutral,
        sentence: ar
            ? 'لا توجد طابعة متصلة — يمكنك البيع ثم نسخ أو مشاركة الرمز.'
            : 'No printer connected — you can still sell, then copy or share the code.',
      );
  }
}

/// The printer state as a compact chip.
///
/// UX-63: [maxWidth] exists because a printer named after its MAC address
/// ("A1:B2:C3:D4:E5:F6") has no natural end, and this chip sits in the POS app
/// bar next to the shop name. The label ellipsizes; the shop keeps its name.
class PrinterStatusChip extends StatelessWidget {
  const PrinterStatusChip({
    super.key,
    required this.state,
    required this.ar,
    this.onTap,
    this.maxWidth = 132,
    this.filled = false,
  });

  final PrinterState state;
  final bool ar;
  final VoidCallback? onTap;
  final double maxWidth;

  /// The rounded, tinted treatment used inside the voucher sheet. The app-bar
  /// chip stays flat.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = printerStatusInfo(state, ar: ar);
    final tint = info.tone.color(context);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(info.icon, size: filled ? 14 : 16, color: tint),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            info.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 12,
              color: tint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );

    final body = filled
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: info.tone == PrinterChipTone.neutral
                  ? cs.surfaceContainerHighest
                  : tint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: info.tone == PrinterChipTone.neutral
                    ? cs.outline
                    : tint.withValues(alpha: 0.4),
              ),
            ),
            child: row,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: row,
          );

    final clamped = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: body,
    );

    if (onTap == null) return clamped;
    // UX-119: the flat app-bar treatment is 6px of vertical padding around a
    // 16px icon — a 28dp tap target on the control that leads to printer setup,
    // i.e. the way out of "no printer" on a counter device operated one-handed.
    // The padded target is raised to 48dp; `widthFactor: 1` keeps the Center
    // sized to the chip, so the app-bar row's horizontal budget is unchanged.
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Center(widthFactor: 1, child: clamped),
      ),
    );
  }
}
