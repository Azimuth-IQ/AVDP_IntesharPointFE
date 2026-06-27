import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';

/// Outcome of the (possibly two-step) login call. The backend returns a bare body
/// (no envelope): a token on success, or a TOTP challenge (enroll / code-required).
sealed class LoginResult {
  const LoginResult();
}

class LoginSuccess extends LoginResult {
  final String token;
  const LoginSuccess(this.token);
}

/// First TOTP enrollment: show the QR ([otpauthUri]) + [secret], collect a code.
class LoginEnrollResult extends LoginResult {
  final String otpauthUri;
  final String secret;
  final String? message; // e.g. "Invalid authentication code" on a retry
  const LoginEnrollResult(this.otpauthUri, this.secret, this.message);
}

/// Enrolled user: a 6-digit code is required to finish signing in.
class LoginTotpRequired extends LoginResult {
  final String? message;
  const LoginTotpRequired(this.message);
}

class AuthRepository {
  final ApiClient _api;
  AuthRepository(this._api);

  Future<LoginResult> login(String phone, String password, {String? totp}) async {
    try {
      final response = await _api.post(
        Endpoints.login,
        data: {
          'phone': phone,
          'password': password,
          if (totp != null && totp.isNotEmpty) 'totp': totp,
        },
      );
      final body = response.data;
      if (body is Map) {
        if (body['token'] != null) return LoginSuccess(body['token'] as String);
        if (body['enroll'] == true) {
          return LoginEnrollResult(
            body['otpauthUri'] as String? ?? '',
            body['secret'] as String? ?? '',
            body['message'] as String?,
          );
        }
        if (body['totpRequired'] == true) {
          return LoginTotpRequired(body['message'] as String?);
        }
      }
      throw const ApiException('Login failed: unexpected response');
    } on ApiException {
      rethrow;
    } catch (e) {
      // Unwrap the DioException so the user sees the real backend message
      // (e.g. the working-hours "Closed now …" reason), not a DioException string.
      throw ApiException.from(e) ?? ApiException(e.toString());
    }
  }

  /// Best-effort server-side logout: bumps the user's tokenVersion so the current
  /// token is revoked server-side. Swallows errors — local sign-out proceeds
  /// regardless (the token expires in 24h even if this call fails offline).
  Future<void> logout() async {
    try {
      await _api.post(Endpoints.logout);
    } catch (_) {
      // ignore — local clear in AuthController still signs the user out
    }
  }
}
