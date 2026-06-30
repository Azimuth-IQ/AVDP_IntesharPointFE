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

/// Same as [friendlyError] when you already hold the [AppLocalizations] instance.
String friendlyErrorL(Object? e, AppLocalizations l) {
  final api = ApiException.from(e);
  if (api == null) return l.errNetwork; // not an API error (timeout / connection / unknown)
  final msg = api.message.trim();
  final hasRealBackendMessage = msg.isNotEmpty &&
      !msg.contains('DioException') &&
      !msg.contains('ApiException') &&
      !msg.toLowerCase().startsWith('http status') &&
      !msg.toLowerCase().contains('status code') &&
      msg.toLowerCase() != 'unknown error' &&
      msg.toLowerCase() != 'network error';

  return switch (api.statusCode) {
    401 => l.errWrongCredentials,
    403 => l.errAccessDenied,
    404 => hasRealBackendMessage ? msg : l.errNotFound,
    402 => hasRealBackendMessage ? msg : l.errInsufficientBalance,
    400 || 409 || 422 => hasRealBackendMessage ? msg : l.errValidation,
    int s when s >= 500 => l.errServer,
    null => l.errNetwork,
    _ => hasRealBackendMessage ? msg : l.errGeneric,
  };
}
