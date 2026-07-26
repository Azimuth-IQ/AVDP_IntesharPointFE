import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pos/domain/pin_verify_result.dart';

/// B-065: the PIN gate used to answer with bare status codes, so the lock screen
/// could only say "Incorrect PIN". That was the wrong instruction in two of the
/// three failure cases — a locked-out operator needs to wait, and one whose shop
/// is shut needs to come back later, not retype a PIN that was never wrong.
void main() {
  group('parsing', () {
    test('reads the typed reason and its payload', () {
      final r = PinVerifyResult.fromJson(
        {'reason': 'WRONG_PIN', 'attemptsLeft': 2},
        fallback: PinVerifyReason.unknown,
      );
      expect(r.reason, PinVerifyReason.wrongPin);
      expect(r.attemptsLeft, 2);
      expect(r.isOk, isFalse);
    });

    test('outside-hours carries the window', () {
      final r = PinVerifyResult.fromJson(
        {'reason': 'OUTSIDE_HOURS', 'opensAt': '09:00', 'closesAt': '21:00'},
        fallback: PinVerifyReason.unknown,
      );
      expect(r.reason, PinVerifyReason.outsideHours);
      expect(r.opensAt, '09:00');
      expect(r.closesAt, '21:00');
    });

    test('an OLD backend answering "ok" still unlocks', () {
      // Pre-B-065 the 200 body was the bare string "ok". A terminal that refuses
      // to unlock against an older server is worse than one that shows no reason.
      final r = PinVerifyResult.fromJson('ok', fallback: PinVerifyReason.ok);
      expect(r.isOk, isTrue);
    });

    test('an OLD backend 403 with no body reads as a wrong PIN', () {
      final r = PinVerifyResult.fromJson(null, fallback: PinVerifyReason.wrongPin);
      expect(r.reason, PinVerifyReason.wrongPin);
      expect(r.attemptsLeft, isNull, reason: 'no countdown is better than a wrong one');
    });

    test('a reason this build predates falls back to the server message', () {
      final r = PinVerifyResult.fromJson(
        {'reason': 'SOME_FUTURE_REASON'},
        fallback: PinVerifyReason.unknown,
        message: 'Account suspended',
      );
      expect(r.reason, PinVerifyReason.unknown);
      expect(posPinReasonText(r, false), 'Account suspended');
    });
  });

  group('what the operator reads', () {
    test('a wrong PIN counts down, and singular/plural agree', () {
      expect(
        posPinReasonText(
            const PinVerifyResult(reason: PinVerifyReason.wrongPin, attemptsLeft: 2), false),
        'Incorrect PIN — 2 tries left',
      );
      expect(
        posPinReasonText(
            const PinVerifyResult(reason: PinVerifyReason.wrongPin, attemptsLeft: 1), false),
        'Incorrect PIN — 1 try left',
      );
    });

    test('a lockout says how long to wait, not to try again', () {
      final msg = posPinReasonText(
          const PinVerifyResult(reason: PinVerifyReason.lockedOut, retryAfterSeconds: 42), false);
      expect(msg, contains('42'));
      expect(msg.toLowerCase(), isNot(contains('incorrect')));
    });

    test('a closed shop names the hours instead of blaming the PIN', () {
      final msg = posPinReasonText(
        const PinVerifyResult(
            reason: PinVerifyReason.outsideHours, opensAt: '09:00', closesAt: '21:00'),
        false,
      );
      expect(msg, contains('09:00'));
      expect(msg, contains('21:00'));
      expect(msg.toLowerCase(), isNot(contains('pin')),
          reason: 'blaming the PIN here is exactly the bug B-065 fixes');
    });

    test('Arabic is not a fallback to English', () {
      for (final r in const [
        PinVerifyResult(reason: PinVerifyReason.wrongPin, attemptsLeft: 2),
        PinVerifyResult(reason: PinVerifyReason.lockedOut, retryAfterSeconds: 30),
        PinVerifyResult(
            reason: PinVerifyReason.outsideHours, opensAt: '09:00', closesAt: '21:00'),
      ]) {
        final ar = posPinReasonText(r, true);
        expect(ar, isNot(posPinReasonText(r, false)));
        expect(RegExp(r'[؀-ۿ]').hasMatch(ar), isTrue, reason: 'must be Arabic: $ar');
      }
    });

    test('degrades to a plain message when the payload is missing', () {
      expect(posPinReasonText(const PinVerifyResult(reason: PinVerifyReason.wrongPin), false),
          'Incorrect PIN');
      expect(posPinReasonText(const PinVerifyResult(reason: PinVerifyReason.lockedOut), false),
          contains('wait'));
    });
  });
}
