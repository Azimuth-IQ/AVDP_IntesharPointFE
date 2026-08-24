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

/// One line of the source that could not be turned into a voucher.
///
/// UX-05: the import result reported `invalid: 12` and nothing else, so the rows
/// a 20k-row file lost were unreconcilable — the server cannot name them either
/// (a row it calls invalid has a BLANK serial), and the client parser had already
/// dropped them before the upload. Keeping the raw line and its number is the
/// only way the operator can find them in the file they still have.
class RejectedRow {
  /// 1-based line number in the pasted text / file.
  final int line;

  /// The raw line, trimmed.
  final String text;

  /// Why it was dropped: `columns` | `serial` | `pin`.
  final String reason;

  const RejectedRow({
    required this.line,
    required this.text,
    required this.reason,
  });
}

/// A parse result: the rows that will be uploaded, and the lines thrown away.
class ParsedImport {
  final List<ParsedVoucher> rows;
  final List<RejectedRow> rejected;
  const ParsedImport({this.rows = const [], this.rejected = const []});
}

/// Parse a whole CSV/TXT body, keeping the lines that could NOT be read.
/// Tolerates a leading header line (first line contains "serial"). Wholly blank
/// lines are not reported — a blank line is formatting, not a lost voucher.
ParsedImport parseVoucherFileDetailed(String content, ImportFormat format) {
  final rows = <ParsedVoucher>[];
  final rejected = <RejectedRow>[];
  final lines = content.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (i == 0 && lines[i].toLowerCase().contains('serial')) continue;
    final trimmed = lines[i].trim();
    if (trimmed.isEmpty) continue;
    final v = parseVoucherLine(lines[i], format);
    if (v != null) {
      rows.add(v);
      continue;
    }
    final cols = trimmed.split(',');
    final reason = cols.length < 2
        ? 'columns'
        : (cols[0].trim().isEmpty ? 'serial' : 'pin');
    rejected.add(RejectedRow(line: i + 1, text: trimmed, reason: reason));
  }
  return ParsedImport(rows: rows, rejected: rejected);
}

/// Parse a whole CSV/TXT body. Tolerates a leading header line (first line contains
/// "serial"). Blank/short/invalid lines are dropped.
List<ParsedVoucher> parseVoucherFile(String content, ImportFormat format) =>
    parseVoucherFileDetailed(content, format).rows;

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

  /// Ids of the `VoucherBatch` documents this import created. The upload is
  /// chunked, and the server opens ONE batch per POST — so a 2,000-row file
  /// produces two ids, not one. Empty when nothing was imported.
  final List<String> batchIds;

  /// The AGENT1 the stock was handed to, echoed by the server (null = HQ kept it).
  final String? assignedTo;

  const BatchImportResult({
    this.imported = 0,
    this.skipped = 0,
    this.invalid = 0,
    this.skippedSerials = const [],
    this.batchIds = const [],
    this.assignedTo,
  });

  factory BatchImportResult.fromJson(Map<String, dynamic> j) => BatchImportResult(
        imported: j['imported'] as int? ?? 0,
        skipped: j['skipped'] as int? ?? 0,
        invalid: j['invalid'] as int? ?? 0,
        skippedSerials:
            (j['skippedSerials'] as List<dynamic>?)?.cast<String>() ?? const [],
        batchIds: [
          if ((j['batchId'] as String?)?.isNotEmpty ?? false) j['batchId'] as String,
        ],
        assignedTo: j['assignedTo'] as String?,
      );

  /// Anything at all reached the server — the operator must NOT be told the
  /// upload failed outright.
  bool get isEmpty => imported == 0 && skipped == 0 && invalid == 0;

  BatchImportResult merge(BatchImportResult o) => BatchImportResult(
        imported: imported + o.imported,
        skipped: skipped + o.skipped,
        invalid: invalid + o.invalid,
        skippedSerials: [...skippedSerials, ...o.skippedSerials],
        batchIds: [...batchIds, ...o.batchIds],
        assignedTo: o.assignedTo ?? assignedTo,
      );
}

/// A chunked import that died part-way (UX-85).
///
/// The upload is split into POSTs of 1,000 rows. When chunk two fails, chunk
/// one's vouchers **are on the server** — owned, sellable, and already counted
/// against the agent. Throwing a bare error made the operator believe nothing
/// landed and re-upload, and the retry then reported "1,000 duplicates", which
/// reads like a second bug. This carries the accumulated result so the UI can
/// say what did land, what did not, and that a retry is safe (the server dedups
/// on serial).
class PartialImportException implements Exception {
  /// Counts aggregated across the chunks that DID succeed.
  final BatchImportResult partial;

  /// The failure that stopped the upload.
  final Object cause;

  /// Rows already POSTed successfully — the retry can start here.
  final int sentRows;

  /// Rows in the whole file.
  final int totalRows;

  const PartialImportException({
    required this.partial,
    required this.cause,
    required this.sentRows,
    required this.totalRows,
  });

  /// Rows that never reached the server.
  int get remainingRows => totalRows - sentRows;

  @override
  String toString() =>
      'PartialImportException($sentRows/$totalRows sent, cause: $cause)';
}

/// A per-serial reconciliation of one import as CSV (UX-05).
///
/// Every attempted row appears with its outcome, so the file can be diffed
/// against the supplier's list instead of reconciled by eye from three numbers
/// and the first 20 duplicate serials. [rejected] rows never reached the server
/// (the parser could not read them) and carry their line number.
///
/// [duplicateSerials] is the server's skipped list. [sentRows] bounds how much
/// of [attempted] was actually POSTed — rows past it are reported as not sent,
/// which is what a partial failure leaves behind.
///
/// [label] maps an outcome key (`imported`, `duplicate`, `notsent`, `columns`,
/// `serial`, `pin`) to display text; it defaults to the key so the function
/// stays pure and testable.
String buildReconciliationCsv({
  required List<ParsedVoucher> attempted,
  required Set<String> duplicateSerials,
  List<RejectedRow> rejected = const [],
  int? sentRows,
  String Function(String key)? label,
}) {
  final text = label ?? (k) => k;
  final sent = sentRows ?? attempted.length;
  final buf = StringBuffer('line,serial,pin,outcome,reason\n');
  for (var i = 0; i < attempted.length; i++) {
    final v = attempted[i];
    final key = i >= sent
        ? 'notsent'
        : (duplicateSerials.contains(v.serial) ? 'duplicate' : 'imported');
    buf.writeln([
      '',
      _csv(v.serial),
      _csv(v.pin),
      _csv(key),
      _csv(text(key)),
    ].join(','));
  }
  for (final r in rejected) {
    buf.writeln([
      '${r.line}',
      _csv(r.text),
      '',
      'unreadable',
      _csv(text(r.reason)),
    ].join(','));
  }
  return buf.toString();
}

String _csv(String v) =>
    (v.contains(',') || v.contains('"') || v.contains('\n'))
        ? '"${v.replaceAll('"', '""')}"'
        : v;
