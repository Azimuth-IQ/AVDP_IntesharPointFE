import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';

void main() {
  group('normalizeExpiry — DD/MM/YYYY day-first → ISO', () {
    test('two-digit day and month', () {
      expect(normalizeExpiry('28/02/2028'), '2028-02-28');
    });
    test('single-digit day/month zero-padded', () {
      expect(normalizeExpiry('9/5/2024'), '2024-05-09');
      expect(normalizeExpiry('10/5/2024'), '2024-05-10');
    });
    test('surrounding whitespace tolerated', () {
      expect(normalizeExpiry('  03/03/2027  '), '2027-03-03');
    });
    test('dash and dot separators', () {
      expect(normalizeExpiry('03-03-2027'), '2027-03-03');
      expect(normalizeExpiry('03.03.2027'), '2027-03-03');
    });
    test('two-digit year → 2000s', () {
      expect(normalizeExpiry('01/02/28'), '2028-02-01');
    });
    test('blank / null / malformed → null', () {
      expect(normalizeExpiry(''), isNull);
      expect(normalizeExpiry(null), isNull);
      expect(normalizeExpiry('not a date'), isNull);
      expect(normalizeExpiry('2024'), isNull);
      expect(normalizeExpiry('40/13/2024'), isNull); // out of range
    });
  });

  group('parseVoucherLine — position-based, no header', () {
    test('NEW: serial,pin,expiry', () {
      final v = parseVoucherLine('80385983791,020339743268988,28/02/2028',
          ImportFormat.newSew);
      expect(v, isNotNull);
      expect(v!.serial, '80385983791');
      expect(v.pin, '020339743268988');
      expect(v.expiry, '2028-02-28');
      expect(v.label, isNull);
    });
    test('OTHER: serial,pin,expiry,label', () {
      final v = parseVoucherLine(
          '260303MIN0001031,X97645X48D7LHF4J,03/03/2027,Apple 2',
          ImportFormat.other);
      expect(v!.serial, '260303MIN0001031');
      expect(v.pin, 'X97645X48D7LHF4J');
      expect(v.expiry, '2027-03-03');
      expect(v.label, 'Apple 2');
    });
    test('NEW ignores a 4th column', () {
      final v = parseVoucherLine('S,P,9/5/2024,IGNORED', ImportFormat.newSew);
      expect(v!.label, isNull);
    });
    test('trailing whitespace (real Asiacell file)', () {
      final v = parseVoucherLine('10070240116,98257662989010,9/5/2024  ',
          ImportFormat.newSew);
      expect(v!.serial, '10070240116');
      expect(v.expiry, '2024-05-09');
    });
    test('blank line / missing serial or pin → null', () {
      expect(parseVoucherLine('', ImportFormat.newSew), isNull);
      expect(parseVoucherLine('   ', ImportFormat.newSew), isNull);
      expect(parseVoucherLine(',PIN,9/5/2024', ImportFormat.newSew), isNull);
      expect(parseVoucherLine('SERIAL,,9/5/2024', ImportFormat.newSew), isNull);
      expect(parseVoucherLine('SERIALONLY', ImportFormat.newSew), isNull);
    });
  });

  group('parseVoucherFile', () {
    test('parses multiple lines and drops blanks', () {
      const body = '10070240116,98257662989010,9/5/2024\n'
          '10070221738,98257559327808,9/5/2024\n'
          '\n'
          '10070255880,98257521976219,9/5/2024\n';
      final rows = parseVoucherFile(body, ImportFormat.newSew);
      expect(rows.length, 3);
      expect(rows.first.serial, '10070240116');
      expect(rows.last.expiry, '2024-05-09');
    });
    test('tolerates a header line', () {
      const body = 'serialNumber,pin,expiry\nS1,P1,1/1/2030';
      final rows = parseVoucherFile(body, ImportFormat.newSew);
      expect(rows.length, 1);
      expect(rows.first.serial, 'S1');
    });
  });

  group('BatchImportResult', () {
    test('fromJson + merge', () {
      final a = BatchImportResult.fromJson(
          {'imported': 5, 'skipped': 2, 'invalid': 1, 'skippedSerials': ['x']});
      final b = BatchImportResult.fromJson({'imported': 3});
      final m = a.merge(b);
      expect(m.imported, 8);
      expect(m.skipped, 2);
      expect(m.invalid, 1);
      expect(m.skippedSerials, ['x']);
    });
  });
}
