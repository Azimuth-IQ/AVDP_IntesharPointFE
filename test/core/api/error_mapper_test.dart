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

  // PROD-016: a Sunmi V2 with no internet showed this, word for word, on the sign-in screen.
  const v2Offline = "The connection errored: Failed host lookup: 'inteshar.azimuth-iraq.com' "
      'This indicates an error which most likely cannot be solved by the library.';

  group('the network library\'s own words never reach the user (PROD-016)', () {
    test('Dio connection and timeout wording is technical', () {
      for (final raw in [
        v2Offline,
        'The request connection took longer than 0:00:20.000000 and it was aborted.',
        'The request took longer than 0:00:30.000000 to receive data.',
        'SocketException: Connection refused (OS Error: Connection refused, errno = 111)',
        'HandshakeException: Handshake error in client',
        'The XMLHttpRequest onError callback was called.',
      ]) {
        expect(backendMessage(raw), isNull, reason: 'should reject: $raw');
      }
    });

    test('offline sign-in reads as a network problem', () {
      expect(loginErrorText(l, null, v2Offline), l.errNetwork);
      expect(loginErrorText(l, null), l.errNetwork);
    });

    test('a status with the same wording still never shows it', () {
      expect(loginErrorText(l, 403, v2Offline), l.errAccessDenied);
      expect(friendlyErrorL(const ApiException(v2Offline, 400), l), l.errValidation);
    });

    test('real server reasons still win on sign-in', () {
      expect(loginErrorText(l, 403, 'Closed now — working hours are 09:00–21:00'),
          'Closed now — working hours are 09:00–21:00');
      expect(loginErrorText(l, 401), l.errWrongCredentials);
      expect(loginErrorText(l, 429, 'Too many attempts. Try again in 30 minutes.'),
          l.errTooManyAttemptsMinutes(30));
      expect(loginErrorText(l, 503), l.errServer);
    });
  });
}
