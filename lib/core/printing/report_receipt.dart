import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/painting.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/receipt_raster.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/pos/domain/pos_report_summary.dart';

/// Prints the POS التقارير window itself — not a voucher.
///
/// سستم التقارير!A1 requires EVERY report to carry the shop's trade name, the
/// owner's full name and both agents above it; A4 requires the sales report to
/// name each category with its card count. Until now the panel could only
/// re-print a single card, so there was no way to hand anyone the window's
/// figures.
///
/// Laid out as pixels through [renderReceiptRaster] for the same reason the
/// voucher is: `Generator.text()` encodes Latin-1 and throws on Arabic, and
/// every label on this report is Arabic in the shipped app.
Future<PrintJob> buildSalesReportPrintJob({
  required PosReportIdentity identity,
  required PosReportSummary summary,
  required String fromDay,
  required String toDay,
  required DateTime printedAt,
  required bool ar,
  bool cutAtEnd = false,
}) async {
  final profile = await CapabilityProfile.load();
  final g = Generator(PaperSize.mm58, profile);
  final width = PaperSize.mm58.width;

  String t(String arabic, String english) => ar ? arabic : english;

  final blocks = <ReceiptBlock>[
    TextBlock(t('تقرير المبيعات', 'Sales report'),
        fontSize: 34, weight: FontWeight.w800, padBottom: 6),
  ];

  // ── Identity (التقارير!A1) — omit any line the shop could not resolve.
  void identityLine(String label, String value, {double size = 24}) {
    if (value.trim().isEmpty) return;
    blocks.add(TextBlock('$label: ${value.trim()}', fontSize: size, padBottom: 3));
  }

  identityLine(t('نقطة البيع', 'Point of sale'), identity.shopName, size: 28);
  identityLine(t('صاحب النقطة', 'Owner'), identity.ownerName);
  identityLine(t('الوكيل الفرعي', 'Sub agent'), identity.subAgentName);
  identityLine(t('الوكيل الرئيسي', 'Main agent'), identity.mainAgentName);

  blocks.add(RuleBlock());
  blocks.add(TextBlock('${t('من', 'From')} $fromDay  ${t('إلى', 'to')} $toDay',
      fontSize: 24, padBottom: 4));
  blocks.add(RuleBlock());

  // ── Totals.
  blocks.add(LabelValueBlock(
    t('عدد الكروت', 'Cards'),
    '${summary.cards}',
    labelSize: 24,
    valueSize: 38,
    valueWeight: FontWeight.w800,
    padBottom: 6,
  ));
  blocks.add(LabelValueBlock(
    t('المجموع', 'Total'),
    Formatters.iqd(summary.total.round()),
    labelSize: 24,
    valueSize: 34,
    valueWeight: FontWeight.w800,
    padBottom: 6,
  ));
  if (summary.notPrinted > 0) {
    blocks.add(TextBlock(
        '${t('لم تتم طباعتها', 'Not printed')}: ${summary.notPrinted}',
        fontSize: 26,
        weight: FontWeight.w700,
        padBottom: 4));
  }
  // The money can legitimately be lower than the card count implies; say why
  // on the paper rather than let someone reconcile a till against a silent gap.
  if (summary.unpriced > 0) {
    blocks.add(TextBlock(
        '${t('بدون سعر مسجل', 'No recorded price')}: ${summary.unpriced}',
        fontSize: 22,
        padBottom: 4));
  }

  // ── Per-category breakdown (التقارير!A4).
  if (summary.byCategory.isNotEmpty) {
    blocks.add(RuleBlock());
    blocks.add(TextBlock(t('حسب الفئة', 'By category'),
        fontSize: 26, weight: FontWeight.w700, padBottom: 5));
    for (final line in summary.byCategory) {
      blocks.add(LabelValueBlock(
        line.category,
        '${line.cards} × ${Formatters.iqd(line.total.round())}',
        labelSize: 22,
        valueSize: 24,
        valueWeight: FontWeight.w700,
        padBottom: 5,
      ));
    }
  }

  // UX-50: there is no longer a "partial report" caveat to print — the totals
  // come from one server-side aggregation over the whole window instead of from
  // however many pages the handheld managed to walk before giving up.
  blocks.add(RuleBlock());
  blocks.add(TextBlock(_stamp(printedAt), fontSize: 20));

  final raster = await renderReceiptRaster(width: width, blocks: blocks);

  final out = <int>[];
  out.addAll(g.imageRaster(raster));
  // Same cutterless-head reasoning as the voucher: `cut()` costs five blank
  // lines plus a tear-off advance on heads that have no cutter.
  out.addAll(g.feed(2));
  if (cutAtEnd) out.addAll(g.cut());

  return PrintJob(
    bytes: out,
    text: buildSalesReportText(
      identity: identity,
      summary: summary,
      fromDay: fromDay,
      toDay: toDay,
      printedAt: printedAt,
      ar: ar,
    ),
  );
}

/// Plain-text mirror of the printed report — used for share/copy, and as the
/// fallback body on intent-based printers that take text rather than bytes.
String buildSalesReportText({
  required PosReportIdentity identity,
  required PosReportSummary summary,
  required String fromDay,
  required String toDay,
  required DateTime printedAt,
  required bool ar,
}) {
  String t(String arabic, String english) => ar ? arabic : english;
  final b = StringBuffer();
  void line([String s = '']) => b.writeln(s);

  line(t('تقرير المبيعات', 'Sales report'));
  if (identity.shopName.trim().isNotEmpty) {
    line('${t('نقطة البيع', 'Point of sale')}: ${identity.shopName.trim()}');
  }
  if (identity.ownerName.trim().isNotEmpty) {
    line('${t('صاحب النقطة', 'Owner')}: ${identity.ownerName.trim()}');
  }
  if (identity.subAgentName.trim().isNotEmpty) {
    line('${t('الوكيل الفرعي', 'Sub agent')}: ${identity.subAgentName.trim()}');
  }
  if (identity.mainAgentName.trim().isNotEmpty) {
    line('${t('الوكيل الرئيسي', 'Main agent')}: ${identity.mainAgentName.trim()}');
  }
  line('${t('من', 'From')} $fromDay ${t('إلى', 'to')} $toDay');
  line('--------------------------------');
  line('${t('عدد الكروت', 'Cards')}: ${summary.cards}');
  line('${t('المجموع', 'Total')}: ${Formatters.iqd(summary.total.round())}');
  if (summary.notPrinted > 0) {
    line('${t('لم تتم طباعتها', 'Not printed')}: ${summary.notPrinted}');
  }
  if (summary.unpriced > 0) {
    line('${t('بدون سعر مسجل', 'No recorded price')}: ${summary.unpriced}');
  }
  if (summary.byCategory.isNotEmpty) {
    line('--------------------------------');
    line(t('حسب الفئة', 'By category'));
    for (final l in summary.byCategory) {
      line('${l.category}: ${l.cards} × ${Formatters.iqd(l.total.round())}');
    }
  }
  line('--------------------------------');
  line(_stamp(printedAt));
  return b.toString();
}

String _stamp(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
