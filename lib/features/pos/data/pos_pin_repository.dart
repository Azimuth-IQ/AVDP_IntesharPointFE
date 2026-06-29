import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';

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
  /// Returns `true` on success (HTTP 200).
  /// Returns `false` when the PIN is wrong (HTTP 403).
  /// **Throws [ApiException] with `statusCode == 409`** when no PIN has been
  /// set yet — callers should catch this and redirect to the setup flow.
  /// Any other error (network failure, 5xx, etc.) is rethrown so callers can
  /// show an appropriate error message.
  Future<bool> verifyPin(String pin) async {
    try {
      final response = await _api.post(
        Endpoints.authVerifyPin,
        data: {'pin': pin},
      );
      _api.unwrap(response, (_) => null);
      return true;
    } catch (e) {
      final apiErr = ApiException.from(e);
      if (apiErr?.statusCode == 403) return false; // Wrong PIN — show inline error
      // 409 = no PIN set yet; propagate so the lock page redirects to setup.
      // Network errors and other exceptions also propagate.
      rethrow;
    }
  }
}
