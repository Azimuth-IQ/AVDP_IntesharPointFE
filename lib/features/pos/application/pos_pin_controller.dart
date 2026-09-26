import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/pos/data/pos_pin_repository.dart';

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

// ── POS PIN length ─────────────────────────────────────────────
//
// Every POS PIN is FOUR digits. `/api/pos-users/reset-pin` has only ever minted
// four (`String.format("%04d", …)`), so this is the length the operator is
// actually handed — the pad now says so instead of guessing.
//
// This replaces a remembered-length scheme (UX-54) that cached the length of the
// last accepted PIN because the server never sent one. With the length fixed
// that cache is not merely redundant, it is harmful: a device that had stored 6
// would keep waiting for a sixth digit the pad can no longer accept, and the
// operator could never finish entry. Reading it is therefore removed, not
// defaulted — see the 2026-09-26 report ("بالتطبيق ديطلب 6").
const int kPosPinLength = 4;
