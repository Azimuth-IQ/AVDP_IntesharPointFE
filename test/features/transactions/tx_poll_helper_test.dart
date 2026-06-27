// Tests for the pure [txPollShouldContinue] helper extracted from
// new_transaction_page.dart. No widget harness needed — all cases are plain
// synchronous [test] calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/transactions/presentation/new_transaction_page.dart';

void main() {
  group('txPollShouldContinue', () {
    const deadline = Duration(seconds: 30);

    test('returns true when no time has elapsed (zero duration)', () {
      expect(txPollShouldContinue(Duration.zero, deadline: deadline), isTrue);
    });

    test('returns true well before the deadline', () {
      expect(
          txPollShouldContinue(const Duration(seconds: 5), deadline: deadline),
          isTrue);
    });

    test('returns true for the last poll window just inside the deadline', () {
      // 28.5 s elapsed — still inside 30 s budget.
      expect(
          txPollShouldContinue(const Duration(milliseconds: 28500),
              deadline: deadline),
          isTrue);
    });

    test('returns false exactly at the deadline boundary', () {
      // elapsed == deadline: the budget is exhausted.
      expect(txPollShouldContinue(deadline, deadline: deadline), isFalse);
    });

    test('returns false when elapsed exceeds the deadline', () {
      expect(
          txPollShouldContinue(const Duration(seconds: 35), deadline: deadline),
          isFalse);
    });

    test('default deadline is 30 s', () {
      // Passes nothing for deadline — relies on the constant default.
      expect(
          txPollShouldContinue(const Duration(seconds: 29, milliseconds: 999)),
          isTrue);
      expect(
          txPollShouldContinue(const Duration(seconds: 30)), isFalse);
    });

    test('respects a custom deadline', () {
      const short = Duration(seconds: 10);
      expect(
          txPollShouldContinue(const Duration(seconds: 9), deadline: short),
          isTrue);
      expect(
          txPollShouldContinue(const Duration(seconds: 10), deadline: short),
          isFalse);
    });
  });
}
