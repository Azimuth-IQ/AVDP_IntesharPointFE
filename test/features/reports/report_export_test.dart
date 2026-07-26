import 'package:excel/excel.dart' hide Border;
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/files/report_export.dart';

/// B-098: two exports of the same report used to be indistinguishable — identical
/// filename, identical columns, and nothing inside recording which agent or which
/// date range produced them. On an audit trail that is worse than not exporting.
///
/// These decode the ACTUAL bytes the exporter produces, rather than re-deriving
/// the layout in the test (which would pass no matter what the writer did).
void main() {
  List<List<String?>> sheetRows(List<int> bytes) {
    final x = Excel.decodeBytes(bytes);
    final sheet = x.tables[x.getDefaultSheet()!]!;
    return [
      for (final r in sheet.rows) [for (final c in r) c?.value?.toString()],
    ];
  }

  test('provenance sits above the headers, separated by a blank line', () {
    final bytes = buildReportXlsx(
      sheetName: 'sold_cards',
      headers: const ['Store', 'Cards'],
      rows: const [
        ['Shop A', '12'],
      ],
      provenance: const [
        ('Report', 'Sold cards'),
        ('Report for', 'Baghdad'),
        ('Date range', '2026-01-01 → 2026-01-31'),
      ],
    );
    expect(bytes, isNotNull);

    final rows = sheetRows(bytes!);
    expect(rows[0][0], 'Report');
    expect(rows[0][1], 'Sold cards');
    expect(rows[1][1], 'Baghdad');
    expect(rows[2][1], '2026-01-01 → 2026-01-31',
        reason: 'the range is the whole point — two months must not look alike');
    expect((rows[3][0] ?? '').trim(), '', reason: 'blank line separates provenance from data');
    expect(rows[4][0], 'Store', reason: 'headers follow the block');
    expect(rows[5][0], 'Shop A');
  });

  test('without provenance the headers are still row 0', () {
    final bytes = buildReportXlsx(
      sheetName: 'x',
      headers: const ['Store'],
      rows: const [
        ['Shop A'],
      ],
    );
    final rows = sheetRows(bytes!);
    expect(rows[0][0], 'Store', reason: 'no leading blank row when there is nothing to stamp');
    expect(rows[1][0], 'Shop A');
  });

  test('an empty report writes nothing, even with provenance', () {
    // A provenance-only file would look like a report and contain none.
    expect(
      buildReportXlsx(
        sheetName: 'x',
        headers: const ['A'],
        rows: const [],
        provenance: const [('Report', 'X')],
      ),
      isNull,
    );
  });

  test('a sheet name with forbidden characters is sanitised, not rejected', () {
    // Excel forbids : * ? / \ [ ] in sheet names and caps at 31 chars.
    final bytes = buildReportXlsx(
      sheetName: 'a/b:c*d?e[f]g' * 4,
      headers: const ['A'],
      rows: const [
        ['1'],
      ],
    );
    expect(bytes, isNotNull);
    final x = Excel.decodeBytes(bytes!);
    final name = x.getDefaultSheet()!;
    expect(name.length, lessThanOrEqualTo(31));
    expect(RegExp(r'[\[\]:*?/\\]').hasMatch(name), isFalse);
  });
}
