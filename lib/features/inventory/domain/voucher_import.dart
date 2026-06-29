/// Supplier voucher-batch upload formats (spec r12–r13). Both are comma-separated
/// with NO header row and dates in DD/MM/YYYY (day-first):
///   NEW/SEW (Asiacell, Zain — region-locked):  serial,pin,expiry
///   OTHER   (everything else — region-free):    serial,pin,expiry,label
enum ImportFormat { newSew, other }

extension ImportFormatX on ImportFormat {
  /// Wire value sent to the backend.
  String get wire => this == ImportFormat.newSew ? 'NEW' : 'OTHER';

  /// Whether this format is region-locked (carries a governorate).
  bool get regionLocked => this == ImportFormat.newSew;
}

/// One parsed voucher row. [expiry] is normalized ISO yyyy-MM-dd (or null).
class ParsedVoucher {
  final String serial;
  final String pin;
  final String? expiry;
  final String? label;
  const ParsedVoucher({
    required this.serial,
    required this.pin,
    this.expiry,
    this.label,
  });
}

/// Normalize a supplier expiry string (DD/MM/YYYY or D/M/YYYY, also `-`/`.` separators,
/// optional surrounding spaces, 2-digit years) to ISO `yyyy-MM-dd`. Day-first (Iraq).
/// Returns null when blank or unparseable.
String? normalizeExpiry(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final parts = s.split(RegExp(r'[/\-.]'));
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  var y = int.tryParse(parts[2].trim());
  if (d == null || m == null || y == null) return null;
  if (y < 100) y += 2000;
  if (d < 1 || d > 31 || m < 1 || m > 12) return null;
  return '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

/// Parse one CSV line into a voucher by POSITION (no header). Returns null for a
/// blank/short line or one missing a serial or pin.
/// NEW = `serial,pin,expiry` ; OTHER = `serial,pin,expiry,label`.
ParsedVoucher? parseVoucherLine(String line, ImportFormat format) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final cols = trimmed.split(',');
  if (cols.length < 2) return null;
  final serial = cols[0].trim();
  final pin = cols[1].trim();
  if (serial.isEmpty || pin.isEmpty) return null;
  final expiry = cols.length > 2 ? normalizeExpiry(cols[2]) : null;
  final label =
      (format == ImportFormat.other && cols.length > 3) ? cols[3].trim() : null;
  return ParsedVoucher(serial: serial, pin: pin, expiry: expiry, label: label);
}

/// Parse a whole CSV/TXT body. Tolerates a leading header line (first line contains
/// "serial"). Blank/short/invalid lines are dropped.
List<ParsedVoucher> parseVoucherFile(String content, ImportFormat format) {
  final out = <ParsedVoucher>[];
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (i == 0 && lines[i].toLowerCase().contains('serial')) continue;
    final v = parseVoucherLine(lines[i], format);
    if (v != null) out.add(v);
  }
  return out;
}

/// Auto-detect the import format from raw pasted/loaded content by counting the
/// columns of the first usable data line (skips blanks + a `serial`-header line):
/// 4 or more comma-separated columns => OTHER (carries a label), otherwise NEW.
/// Returns null when there is no parseable data line, so the caller can keep the
/// current selection. Drives "auto-select the fields on paste".
ImportFormat? detectFormat(String content) {
  for (final line in content.split('\n')) {
    final t = line.trim();
    if (t.isEmpty) continue;
    if (t.toLowerCase().contains('serial')) continue; // header row
    final cols = t.split(',');
    if (cols.length < 2) continue;
    return cols.length >= 4 ? ImportFormat.other : ImportFormat.newSew;
  }
  return null;
}

/// Result of a bulk import (mirrors the backend `BatchImportResult`).
class BatchImportResult {
  final int imported;
  final int skipped;
  final int invalid;
  final List<String> skippedSerials;
  const BatchImportResult({
    this.imported = 0,
    this.skipped = 0,
    this.invalid = 0,
    this.skippedSerials = const [],
  });

  factory BatchImportResult.fromJson(Map<String, dynamic> j) => BatchImportResult(
        imported: j['imported'] as int? ?? 0,
        skipped: j['skipped'] as int? ?? 0,
        invalid: j['invalid'] as int? ?? 0,
        skippedSerials:
            (j['skippedSerials'] as List<dynamic>?)?.cast<String>() ?? const [],
      );

  BatchImportResult merge(BatchImportResult o) => BatchImportResult(
        imported: imported + o.imported,
        skipped: skipped + o.skipped,
        invalid: invalid + o.invalid,
        skippedSerials: [...skippedSerials, ...o.skippedSerials],
      );
}
