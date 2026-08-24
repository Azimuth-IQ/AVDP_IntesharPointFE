import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';

/// The parts of the batch-import result the operator reconciles by hand
/// (UX-05 / UX-85). These are pure, so they are asserted on the real artifact —
/// the CSV text and the rejected-row list — rather than on a re-statement of the
/// code that produces them.
void main() {
  group('parseVoucherFileDetailed — names the rows it drops', () {
    test('reports line number and reason for each unreadable row', () {
      const body = 'S1,P1,1/1/2030\n'
          'SERIALONLY\n'
          ',P2,1/1/2030\n'
          'S3,,1/1/2030\n'
          '\n';
      final parsed = parseVoucherFileDetailed(body, ImportFormat.newSew);

      expect(parsed.rows.length, 1);
      expect(parsed.rows.single.serial, 'S1');

      // A wholly blank line is formatting, not a lost voucher.
      expect(parsed.rejected.map((r) => r.line), [2, 3, 4]);
      expect(parsed.rejected.map((r) => r.reason), ['columns', 'serial', 'pin']);
      expect(parsed.rejected.first.text, 'SERIALONLY');
    });

    test('parseVoucherFile still returns exactly the readable rows', () {
      const body = 'serialNumber,pin,expiry\nS1,P1,1/1/2030\nJUNK\n';
      expect(parseVoucherFile(body, ImportFormat.newSew).length, 1);
    });
  });

  group('buildReconciliationCsv', () {
    test('gives every attempted serial an outcome, including the unsent tail',
        () {
      final csv = buildReconciliationCsv(
        attempted: const [
          ParsedVoucher(serial: 'S1', pin: 'P1'),
          ParsedVoucher(serial: 'S2', pin: 'P2'),
          ParsedVoucher(serial: 'S3', pin: 'P3'),
        ],
        duplicateSerials: {'S2'},
        rejected: const [
          RejectedRow(line: 9, text: 'JUNK', reason: 'columns'),
        ],
        // The upload died after two rows — S3 never reached the server.
        sentRows: 2,
      );

      expect(csv, '''
line,serial,pin,outcome,reason
,S1,P1,imported,imported
,S2,P2,duplicate,duplicate
,S3,P3,notsent,notsent
9,JUNK,,unreadable,columns
''');
    });

    test('everything counts as sent when sentRows is omitted', () {
      final csv = buildReconciliationCsv(
        attempted: const [ParsedVoucher(serial: 'S1', pin: 'P1')],
        duplicateSerials: const {},
      );
      expect(csv.contains('notsent'), isFalse);
      expect(csv.trim().split('\n').last, ',S1,P1,imported,imported');
    });

    test('quotes a field containing a comma so the columns survive Excel', () {
      final csv = buildReconciliationCsv(
        attempted: const [],
        duplicateSerials: const {},
        rejected: const [
          RejectedRow(line: 3, text: 'A,B', reason: 'columns'),
        ],
      );
      expect(csv.contains('3,"A,B",,unreadable,columns'), isTrue);
    });

    test('uses the supplied labels for the reason column', () {
      final csv = buildReconciliationCsv(
        attempted: const [ParsedVoucher(serial: 'S1', pin: 'P1')],
        duplicateSerials: {'S1'},
        label: (k) => k == 'duplicate' ? 'مكرر' : k,
      );
      expect(csv.contains(',S1,P1,duplicate,مكرر'), isTrue);
    });
  });

  group('BatchImportResult', () {
    test('carries the batch id the server opened for the import', () {
      final r = BatchImportResult.fromJson(
          {'imported': 2, 'batchId': 'b-1', 'assignedTo': 'agent-1'});
      expect(r.batchIds, ['b-1']);
      expect(r.assignedTo, 'agent-1');
      expect(r.isEmpty, isFalse);
    });

    test('a chunked upload accumulates one batch id per chunk', () {
      final a = BatchImportResult.fromJson({'imported': 1000, 'batchId': 'b-1'});
      final b = BatchImportResult.fromJson({'imported': 1000, 'batchId': 'b-2'});
      expect(a.merge(b).batchIds, ['b-1', 'b-2']);
      expect(a.merge(b).imported, 2000);
    });

    test('a result with no counts at all is empty', () {
      expect(const BatchImportResult().isEmpty, isTrue);
      expect(const BatchImportResult(invalid: 1).isEmpty, isFalse);
    });
  });

  test('PartialImportException knows what still has to go up', () {
    const e = PartialImportException(
      partial: BatchImportResult(imported: 1000),
      cause: 'timeout',
      sentRows: 1000,
      totalRows: 2000,
    );
    expect(e.remainingRows, 1000);
  });
}
