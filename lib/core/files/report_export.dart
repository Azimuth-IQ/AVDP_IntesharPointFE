import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:inteshar/core/files/web_download.dart';

/// One exported cell.
///
/// UX-42: every cell used to be written as `TextCellValue`, with the amounts
/// arriving already comma-grouped ("25,876,000") or carrying a currency suffix.
/// The whole point of the export is that accounting works the figures in Excel,
/// and a text column sums to nothing, sorts alphabetically and cannot be pivoted.
///
/// So a cell is now either:
/// - a [String] — identity data (names, phones, SKUs, dates). Phones especially
///   MUST stay text: `07701234567` written as a number loses its leading zero.
/// - a [num] — written as a real number with a `#,##0` (or `#,##0.00`) format,
///   so it *reads* exactly as it did on screen and still behaves as a number.
typedef XlsxCell = Object;

/// The cell value + the number format that makes an integer render grouped
/// (`25,876,000`) rather than as a bare `25876000`.
(CellValue, CellStyle?) _cellOf(Object v) {
  if (v is num) {
    // NaN/Infinity would encode as a corrupt numeric cell — degrade to text.
    if (v is double && !v.isFinite) return (TextCellValue(v.toString()), null);
    final whole = v is int || v == v.roundToDouble();
    return whole
        ? (
            IntCellValue(v.round()),
            CellStyle(numberFormat: NumFormat.standard_3), // #,##0
          )
        : (
            DoubleCellValue(v.toDouble()),
            CellStyle(numberFormat: NumFormat.standard_4), // #,##0.00
          );
  }
  return (TextCellValue(v.toString()), null);
}

/// Builds the XLSX bytes for a report. Separated from the save step so the sheet's
/// STRUCTURE — provenance block, blank separator, headers, data — is testable
/// without a file picker or a browser download in the way.
///
/// [rows] cells follow the [XlsxCell] contract: `String` = text, `num` = a real
/// number. A `List<List<String>>` is still a valid argument, so a report that has
/// nothing to sum needs no change.
///
/// Returns null when there are no data rows: a provenance-only sheet would be a
/// file that looks like a report and contains none.
Uint8List? buildReportXlsx({
  required String sheetName,
  required List<String> headers,
  required List<List<XlsxCell>> rows,
  List<(String, String)> provenance = const [],
}) {
  if (rows.isEmpty) return null;
  final excel = Excel.createExcel();
  // Excel sheet names cap at 31 chars and forbid a few characters.
  final safeSheet = sheetName.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final sheetKey = safeSheet.isEmpty ? 'Report' : (safeSheet.length > 31 ? safeSheet.substring(0, 31) : safeSheet);
  final sheet = excel[sheetKey];
  excel.setDefaultSheet(sheetKey);
  if (excel.tables.containsKey('Sheet1') && sheetKey != 'Sheet1') excel.delete('Sheet1');

  // A number format can only be attached per cell (appendRow takes no style), so
  // rows are written by index rather than appended.
  var r = 0;
  void put(int col, Object value) {
    final (cell, style) = _cellOf(value);
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r),
      cell,
      cellStyle: style,
    );
  }

  for (final (label, value) in provenance) {
    put(0, label);
    put(1, value);
    r++;
  }
  if (provenance.isNotEmpty) {
    put(0, '');
    r++;
  }

  for (var c = 0; c < headers.length; c++) {
    put(c, headers[c]);
  }
  r++;
  for (final row in rows) {
    for (var c = 0; c < row.length; c++) {
      put(c, row[c]);
    }
    r++;
  }
  final encoded = excel.encode();
  return encoded == null ? null : Uint8List.fromList(encoded);
}

/// Builds a single-sheet XLSX from [headers] + [rows] and saves it cross-platform:
/// a browser download on web, the system save dialog on mobile. Returns the saved
/// path/name, or null if nothing was written (empty or cancelled).
///
/// [provenance] (B-098) is written as `label: value` lines above the header row,
/// followed by a blank line. Without it two exports of the same report are
/// indistinguishable — same filename, same columns, nothing recording which agent
/// or which date range produced them, which on an audit trail is worse than not
/// exporting at all.
Future<String?> exportRowsToXlsx({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<XlsxCell>> rows,
  List<(String, String)> provenance = const [],
}) async {
  final bytes = buildReportXlsx(
      sheetName: sheetName, headers: headers, rows: rows, provenance: provenance);
  if (bytes == null) return null;
  final name = fileName.toLowerCase().endsWith('.xlsx') ? fileName : '$fileName.xlsx';

  if (kIsWeb) {
    downloadBytes(name, bytes);
    return name;
  }
  // Android/iOS: the system save dialog writes the bytes directly (no dart:io).
  // B-106: WITHOUT type/allowedExtensions this goes to SAF as FileType.any →
  // MIME `*/*`, and an OEM picker (Sunmi ships stock Android 7.1) can then write
  // a document whose type does not match its name — which is why a valid
  // workbook opened as "unknown format".
  return FilePicker.platform.saveFile(
    fileName: name,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
}
