import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/pos/data/pos_pin_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the current POS session has passed PIN verification this run.
///
/// Defaults to `false`. Set to `true` by [PosPinSetupPage] (first setup or
/// change) and [PosPinLockPage] (resume). Reset to `false` on logout so
/// every new POS session re-requires PIN entry.
///
/// This is a pure in-memory flag — no persistence — so a cold restart also
/// triggers the PIN lock (intentionally, matching physical POS behaviour).
final posUnlockedProvider = StateProvider<bool>((ref) => false);

/// Provides a [PosPinRepository] backed by the shared [ApiClient].
final posPinRepositoryProvider = Provider<PosPinRepository>((ref) {
  return PosPinRepository(ref.watch(apiClientProvider));
});

// ── Remembered PIN LENGTH (UX-54) ────────────────────────────────────────────
//
// The server never tells the client how long this shop's PIN is (4–6 digits),
// so the keypad cannot know when the operator has finished typing — and an
// unlock that needs a deliberate "Unlock" tap after every relock is exactly the
// friction the 90-second relock multiplies.
//
// Only the LENGTH is kept, never the PIN, and only after a verify the server
// accepted. It is cleared the moment a PIN is rejected, so a PIN that changed
// behind the app's back can cost at most one auto-submitted wrong attempt
// before the pad goes back to requiring an explicit tap.
const String _pinLenKey = 'pos_pin_len';

Future<int?> readRememberedPinLength() async {
  final p = await SharedPreferences.getInstance();
  final v = p.getInt(_pinLenKey);
  return (v != null && v >= 4 && v <= 6) ? v : null;
}

Future<void> rememberPinLength(int length) async {
  if (length < 4 || length > 6) return;
  final p = await SharedPreferences.getInstance();
  await p.setInt(_pinLenKey, length);
}

Future<void> forgetRememberedPinLength() async {
  final p = await SharedPreferences.getInstance();
  await p.remove(_pinLenKey);
}
