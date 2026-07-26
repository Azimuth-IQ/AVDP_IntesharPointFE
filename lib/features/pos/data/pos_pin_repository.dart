import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/pos/domain/pin_verify_result.dart';

/// Repository for the POS-session PIN operations.
///
/// The PIN is set once by the POS operator and stored server-side (BCrypt-hashed
/// on `User.posPin`). Each POS session is gated behind a local PIN-lock screen
/// that calls [verifyPin] before showing the voucher counter.
class PosPinRepository {
  final ApiClient _api;
  PosPinRepository(this._api);

  /// Sets or changes the POS PIN.
  ///
  /// Pass [currentPin] when changing an existing PIN so the backend can
  /// authenticate the change. On first setup [currentPin] is omitted.
  /// Throws [ApiException] on any backend error; rethrows network errors.
  Future<void> setPin(String pin, {String? currentPin}) async {
    final response = await _api.post(
      Endpoints.authSetPin,
      data: {
        'pin': pin,
        // ignore: use_null_aware_elements
        if (currentPin != null) 'currentPin': currentPin,
      },
    );
    _api.unwrap(response, (_) => null);
  }

  /// Verifies the POS PIN for the signed-in user.
  ///
  /// B-065: returns the typed REASON rather than a bool. A 403 can mean "wrong
  /// PIN" (with the guesses left before lockout) or "the shop is shut right now"
  /// — telling an operator the latter is a wrong PIN sends them retyping a PIN
  /// that was never the problem.
  ///
  /// **Throws [ApiException] with `statusCode == 409`** when no PIN has been set
  /// yet — callers should catch this and redirect to the setup flow. Any other
  /// error (network failure, 5xx) is rethrown.
  Future<PinVerifyResult> verifyPin(String pin) async {
    try {
      final response = await _api.post(
        Endpoints.authVerifyPin,
        data: {'pin': pin},
      );
      final data = _api.unwrap<dynamic>(response, (d) => d);
      // An older backend answers with the bare string "ok" — a 200 must still
      // unlock, never dead-end the terminal on a payload it doesn't recognise.
      return PinVerifyResult.fromJson(data, fallback: PinVerifyReason.ok);
    } catch (e) {
      final apiErr = ApiException.from(e);
      if (apiErr?.statusCode == 403 || apiErr?.statusCode == 429) {
        // `raw` is the whole {status, message, data} envelope the interceptor kept.
        final raw = apiErr?.raw;
        return PinVerifyResult.fromJson(
          raw is Map ? raw['data'] : null,
          // An older backend sends no body on 403; "wrong PIN" is the safe read.
          fallback: apiErr?.statusCode == 429
              ? PinVerifyReason.lockedOut
              : PinVerifyReason.wrongPin,
          message: apiErr?.message,
        );
      }
      // 409 = no PIN set yet; propagate so the lock page redirects to setup.
      rethrow;
    }
  }
}
