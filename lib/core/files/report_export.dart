import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:inteshar/core/files/web_download.dart';

/// Builds the XLSX bytes for a report. Separated from the save step so the sheet's
/// STRUCTURE — provenance block, blank separator, headers, data — is testable
/// without a file picker or a browser download in the way.
///
/// Returns null when there are no data rows: a provenance-only sheet would be a
/// file that looks like a report and contains none.
Uint8List? buildReportXlsx({
  required String sheetName,
  required List<String> headers,
  required List<List<String>> rows,
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

  for (final (label, value) in provenance) {
    sheet.appendRow([TextCellValue(label), TextCellValue(value)]);
  }
  if (provenance.isNotEmpty) sheet.appendRow([TextCellValue('')]);

  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  for (final r in rows) {
    sheet.appendRow(r.map((c) => TextCellValue(c)).toList());
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
  required List<List<String>> rows,
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
  return FilePicker.platform.saveFile(fileName: name, bytes: bytes);
}
