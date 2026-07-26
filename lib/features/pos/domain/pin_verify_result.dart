/// Why the POS PIN gate said no (B-065).
///
/// The endpoint used to answer with bare status codes, so the lock screen could
/// only ever say "wrong PIN" — it couldn't warn that the next miss locks the
/// terminal, and an operator whose working window had closed got "wrong PIN"
/// and kept retyping a PIN that was never the problem.
enum PinVerifyReason { ok, wrongPin, lockedOut, noPin, outsideHours, unknown }

class PinVerifyResult {
  final PinVerifyReason reason;

  /// Guesses left before the lockout arms. Null unless [reason] is `wrongPin`.
  final int? attemptsLeft;

  /// Seconds until the lockout lifts. Null unless [reason] is `lockedOut`.
  final int? retryAfterSeconds;

  /// Window bounds ("HH:mm"). Null unless [reason] is `outsideHours`.
  final String? opensAt;
  final String? closesAt;

  /// The server's own message — used as the fallback when a reason is unknown
  /// (an older backend, or a new reason this build predates).
  final String? message;

  const PinVerifyResult({
    required this.reason,
    this.attemptsLeft,
    this.retryAfterSeconds,
    this.opensAt,
    this.closesAt,
    this.message,
  });

  bool get isOk => reason == PinVerifyReason.ok;

  static PinVerifyReason _reasonOf(String? raw) => switch (raw) {
        'OK' => PinVerifyReason.ok,
        'WRONG_PIN' => PinVerifyReason.wrongPin,
        'LOCKED_OUT' => PinVerifyReason.lockedOut,
        'NO_PIN' => PinVerifyReason.noPin,
        'OUTSIDE_HOURS' => PinVerifyReason.outsideHours,
        _ => PinVerifyReason.unknown,
      };

  /// Parses the `data` object. [fallback] is used when the payload is absent —
  /// an older backend returns the bare string "ok", so a 200 with no object
  /// still has to unlock rather than dead-end the terminal.
  factory PinVerifyResult.fromJson(dynamic json, {
    required PinVerifyReason fallback,
    String? message,
  }) {
    if (json is! Map) return PinVerifyResult(reason: fallback, message: message);
    return PinVerifyResult(
      reason: _reasonOf(json['reason'] as String?),
      attemptsLeft: (json['attemptsLeft'] as num?)?.toInt(),
      retryAfterSeconds: (json['retryAfterSeconds'] as num?)?.toInt(),
      opensAt: json['opensAt'] as String?,
      closesAt: json['closesAt'] as String?,
      message: message,
    );
  }
}

/// Turns a [PinVerifyResult] into the sentence an operator should read.
///
/// Shared by the lock screen and the bulk-sale confirm pad: the three failures
/// need three different reactions — try again (and here's how many tries are
/// left), wait N seconds, or come back during opening hours — and a single
/// "Incorrect PIN" told the operator to do the wrong thing in two of the three.
String posPinReasonText(PinVerifyResult r, bool ar) {
  switch (r.reason) {
    case PinVerifyReason.wrongPin:
      final left = r.attemptsLeft;
      if (left == null) return ar ? 'رمز غير صحيح' : 'Incorrect PIN';
      return ar
          ? 'رمز غير صحيح — بقيت $left ${left == 1 ? 'محاولة' : 'محاولات'}'
          : 'Incorrect PIN — $left ${left == 1 ? 'try' : 'tries'} left';
    case PinVerifyReason.lockedOut:
      final secs = r.retryAfterSeconds;
      if (secs == null || secs <= 0) {
        return ar ? 'محاولات كثيرة — انتظر قليلاً' : 'Too many attempts — wait a moment';
      }
      return ar
          ? 'محاولات كثيرة — أعد المحاولة بعد $secs ثانية'
          : 'Too many attempts — try again in ${secs}s';
    case PinVerifyReason.outsideHours:
      final open = r.opensAt, close = r.closesAt;
      if (open == null || close == null) {
        return ar ? 'المحل مغلق الآن' : 'Closed right now';
      }
      return ar
          ? 'المحل مغلق الآن — أوقات العمل $open–$close'
          : 'Closed right now — working hours are $open–$close';
    case PinVerifyReason.ok:
    case PinVerifyReason.noPin:
    case PinVerifyReason.unknown:
      return r.message ?? (ar ? 'حدث خطأ' : 'An error occurred');
  }
}
