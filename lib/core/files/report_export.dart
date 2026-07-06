import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:inteshar/core/files/web_download.dart';

/// Builds a single-sheet XLSX from [headers] + [rows] and saves it cross-platform:
/// a browser download on web, the system save dialog on mobile. Returns the saved
/// path/name, or null if nothing was written (empty or cancelled). Mirrors the batch
/// import-template export but takes generic rows so any report can reuse it.
Future<String?> exportRowsToXlsx({
  required String fileName,
  required String sheetName,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  if (rows.isEmpty) return null;
  final excel = Excel.createExcel();
  // Excel sheet names cap at 31 chars and forbid a few characters.
  final safeSheet = sheetName.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final sheetKey = safeSheet.isEmpty ? 'Report' : (safeSheet.length > 31 ? safeSheet.substring(0, 31) : safeSheet);
  final sheet = excel[sheetKey];
  excel.setDefaultSheet(sheetKey);
  if (excel.tables.containsKey('Sheet1') && sheetKey != 'Sheet1') excel.delete('Sheet1');

  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  for (final r in rows) {
    sheet.appendRow(r.map((c) => TextCellValue(c)).toList());
  }

  final encoded = excel.encode();
  if (encoded == null) return null;
  final bytes = Uint8List.fromList(encoded);
  final name = fileName.toLowerCase().endsWith('.xlsx') ? fileName : '$fileName.xlsx';

  if (kIsWeb) {
    downloadBytes(name, bytes);
    return name;
  }
  // Android/iOS: the system save dialog writes the bytes directly (no dart:io).
  return FilePicker.platform.saveFile(fileName: name, bytes: bytes);
}
