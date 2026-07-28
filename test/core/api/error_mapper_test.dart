import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/l10n/app_localizations_en.dart';

/// B-108: 401/403 were flattened to "wrong credentials" / "access denied"
/// unconditionally, which discarded the only messages that tell a user what to
/// DO — the working-hours window, a disabled section, no PIN set. A POS operator
/// saw "something went wrong" and had no way forward.
void main() {
  final AppLocalizations l = AppLocalizationsEn();

  group('a real backend reason reaches the user', () {
    test('403 outside working hours says so', () {
      const msg = 'Closed now — working hours are 09:00–21:00';
      expect(friendlyErrorL(const ApiException(msg, 403), l), msg);
    });

    test('403 for a disabled section says so', () {
      const msg = 'The POS section is disabled for this account';
      expect(friendlyErrorL(const ApiException(msg, 403), l), msg);
    });

    test('401 with a reason keeps it', () {
      const msg = 'Account is disabled';
      expect(friendlyErrorL(const ApiException(msg, 401), l), msg);
    });

    test('429 explains the wait', () {
      expect(friendlyErrorL(const ApiException('Too many attempts. Try again in a minute.', 429), l),
          contains('Too many attempts'));
    });
  });

  group('technical noise never reaches the user', () {
    test('an exception string falls back to the localized text', () {
      for (final raw in [
        'DioException [bad response]: …',
        'ApiException(401): nope',
        'HTTP status 403',
        'unknown error',
        '',
      ]) {
        final out = friendlyErrorL(ApiException(raw, 403), l);
        expect(out, l.errAccessDenied, reason: 'must not surface: $raw');
      }
    });

    test('a wrong password with no body still reads as wrong credentials', () {
      expect(friendlyErrorL(const ApiException('', 401), l), l.errWrongCredentials);
    });

    test('a 500 never shows the server\'s words', () {
      expect(friendlyErrorL(const ApiException('NullPointerException at line 42', 500), l),
          l.errServer);
    });

    test('a non-API error is a network problem', () {
      expect(friendlyErrorL(Exception('socket closed'), l), l.errNetwork);
    });
  });

  group('backendMessage guard', () {
    test('passes human text', () {
      expect(backendMessage('Insufficient withdrawal limit'), 'Insufficient withdrawal limit');
    });

    test('rejects null, empty and technical strings', () {
      for (final raw in [null, '', '   ', 'DioException x', 'status code 500', 'Network error']) {
        expect(backendMessage(raw), isNull, reason: 'should reject: $raw');
      }
    });
  });
}
