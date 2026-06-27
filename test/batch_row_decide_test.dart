import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/presentation/batch_add_page.dart';

void main() {
  group('batchRowDecide', () {
    const empty = <String>{};
    const occupied = {'sn0001', 'sn0002'};

    // ── invalid (empty serial or PIN) ─────────────────────────────────────

    test('empty serial → invalid', () {
      expect(
        batchRowDecide(serial: '', pin: '1234', existingSerials: empty),
        BatchRowAction.invalid,
      );
    });

    test('whitespace-only serial → invalid', () {
      expect(
        batchRowDecide(serial: '   ', pin: '1234', existingSerials: empty),
        BatchRowAction.invalid,
      );
    });

    test('empty pin → invalid', () {
      expect(
        batchRowDecide(serial: 'SN9999', pin: '', existingSerials: empty),
        BatchRowAction.invalid,
      );
    });

    test('whitespace-only pin → invalid', () {
      expect(
        batchRowDecide(serial: 'SN9999', pin: '\t', existingSerials: empty),
        BatchRowAction.invalid,
      );
    });

    test('both empty → invalid', () {
      expect(
        batchRowDecide(serial: '', pin: '', existingSerials: empty),
        BatchRowAction.invalid,
      );
    });

    // ── skip (serial already in inventory) ───────────────────────────────

    test('exact-case match → skip', () {
      expect(
        batchRowDecide(serial: 'sn0001', pin: '1234', existingSerials: occupied),
        BatchRowAction.skip,
      );
    });

    test('upper-case serial matches lower-case key → skip (case-insensitive)', () {
      expect(
        batchRowDecide(serial: 'SN0001', pin: '1234', existingSerials: occupied),
        BatchRowAction.skip,
      );
    });

    test('serial with leading/trailing spaces matches → skip', () {
      expect(
        batchRowDecide(serial: '  SN0002  ', pin: '5678', existingSerials: occupied),
        BatchRowAction.skip,
      );
    });

    // ── add (new, valid row) ──────────────────────────────────────────────

    test('new serial not in set → add', () {
      expect(
        batchRowDecide(serial: 'SN0003', pin: '9999', existingSerials: occupied),
        BatchRowAction.add,
      );
    });

    test('new serial with surrounding spaces → add', () {
      expect(
        batchRowDecide(serial: '  SN0099  ', pin: '0000', existingSerials: occupied),
        BatchRowAction.add,
      );
    });

    test('empty existing set → always add for valid row', () {
      expect(
        batchRowDecide(serial: 'SN1', pin: '1', existingSerials: empty),
        BatchRowAction.add,
      );
    });

    // ── precedence: invalid beats skip ───────────────────────────────────

    test('empty serial that happens to match a key → invalid (not skip)', () {
      // The key '' would never be in a real set, but the empty guard fires first.
      expect(
        batchRowDecide(serial: '', pin: '1234', existingSerials: {''}),
        BatchRowAction.invalid,
      );
    });
  });
}
