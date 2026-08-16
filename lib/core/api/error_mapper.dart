import 'package:flutter/widgets.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// Maps ANY thrown error to a friendly, localized message — never raw JSON, a
/// `DioException` string, or `"ApiException(401): ..."`. Use this at every catch site
/// instead of `e.toString()`:
///
/// ```dart
/// } catch (e) {
///   setState(() => _error = friendlyError(e, context));
/// }
/// ```
///
/// The backend's enveloped `{status,message,data}` carries genuinely useful messages for
/// 400/402/409 (e.g. "Insufficient withdrawal limit"), so those are shown as-is; empty-body
/// auth/permission/server failures fall back to a localized message keyed by status code.
String friendlyError(Object? e, BuildContext context) =>
    friendlyErrorL(e, AppLocalizations.of(context)!);

/// The backend's own message when it is genuinely user-facing, else null.
///
/// Exposed (B-108) because the login screen needs the same judgement: a 403
/// carrying "Closed now — working hours are 09:00–21:00" must reach the user,
/// while a DioException string never should.
String? backendMessage(String? raw) {
  final msg = raw?.trim() ?? '';
  final lower = msg.toLowerCase();
  final technical = msg.isEmpty ||
      msg.contains('DioException') ||
      msg.contains('ApiException') ||
      lower.startsWith('http status') ||
      lower.contains('status code') ||
      lower == 'unknown error' ||
      lower == 'network error';
  return technical ? null : msg;
}

/// Same as [friendlyError] when you already hold the [AppLocalizations] instance.
String friendlyErrorL(Object? e, AppLocalizations l) {
  final api = ApiException.from(e);
  if (api == null) return l.errNetwork; // not an API error (timeout / connection / unknown)
  final msg = api.message.trim();
  final hasRealBackendMessage = backendMessage(msg) != null;

  return switch (api.statusCode) {
    // B-108: 401/403 used to be flattened to "wrong credentials" / "access
    // denied" UNCONDITIONALLY, which threw away the only messages that tell the
    // user what to actually do — "Closed now — working hours are 09:00–21:00",
    // "The POS section is disabled for this account", "No PIN set". That is why
    // a failed POS login read as a bare "something went wrong". The backend's
    // 401/403 bodies are written for end users; the hasRealBackendMessage guard
    // still filters DioException/status-code noise, so nothing technical leaks.
    401 => hasRealBackendMessage ? msg : l.errWrongCredentials,
    403 => hasRealBackendMessage ? msg : l.errAccessDenied,
    429 => hasRealBackendMessage ? msg : l.errTooManyAttempts,
    404 => hasRealBackendMessage ? msg : l.errNotFound,
    402 => hasRealBackendMessage ? msg : l.errInsufficientBalance,
    400 || 409 || 422 => hasRealBackendMessage ? msg : l.errValidation,
    int s when s >= 500 => l.errServer,
    null => l.errNetwork,
    _ => hasRealBackendMessage ? msg : l.errGeneric,
  };
}

/// B-132: true when a write failed because the phone is already registered.
///
/// The server answers `409 Phone is already in use` when onboarding a POS whose
/// phone belongs to an existing user. Callers need to distinguish it from every
/// other failure so it can stop the operator with a modal rather than a
/// snackbar they can miss and retype the same number into.
///
/// Uses [ApiException.from] rather than a bare type check: a raw `catch (e)`
/// yields the DioException the interceptor packs the ApiException into, so
/// `e is ApiException` never matches.
bool isDuplicatePhone(Object? e) => ApiException.from(e)?.statusCode == 409;

/// The message the SERVER sent, when there is one worth showing.
///
/// Most failures should go through [friendlyError], which deliberately replaces
/// backend text with something an operator can act on. This is the exception:
/// a few endpoints answer with the one detail the client cannot work out for
/// itself — which shop holds a phone number, why a window is closed — and
/// discarding it leaves the user with a dead end (B-108 was the same lesson for
/// 401/403). Returns null for an empty message or a non-API error, so the caller
/// can fall back to its own copy.
String? serverReason(Object? e) {
  final message = ApiException.from(e)?.message.trim();
  return (message == null || message.isEmpty) ? null : message;
}
