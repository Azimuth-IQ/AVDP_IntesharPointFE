/// PROD-033: the moments the app itself sends the cashier to another screen and expects them
/// back — the vendor print app, Android settings, the update installer.
///
/// The POS asks for its PIN every time it comes back from the background (the screen turned off,
/// the app was left or reopened). Only a trip the app started itself is let through, so printing
/// through the vendor app does not ask for the PIN after every receipt.
class HandOff {
  HandOff._();

  /// How long after [mark] a trip to the background still counts as the app's own.
  static const window = Duration(minutes: 2);

  static DateTime? _last;

  /// Call right before handing the screen to another app or to Android settings.
  static void mark([DateTime? at]) => _last = at ?? DateTime.now();

  /// Whether the app went to the background at [pausedAt] because of a recent [mark].
  /// Each mark covers ONE trip: it is used up here, so the next screen-off asks for the PIN.
  static bool consume(DateTime pausedAt) {
    final last = _last;
    if (last == null) return false;
    _last = null;
    final gap = pausedAt.difference(last);
    return gap >= const Duration(seconds: -1) && gap <= window;
  }

  /// For tests.
  static void reset() => _last = null;
}
