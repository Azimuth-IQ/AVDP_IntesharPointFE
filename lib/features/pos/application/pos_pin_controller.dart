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
