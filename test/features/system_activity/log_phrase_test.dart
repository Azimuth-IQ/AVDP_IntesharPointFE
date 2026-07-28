import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/system_activity/domain/log_phrase.dart';
import 'package:inteshar/features/system_activity/domain/operation_log.dart';

/// B-108: the activity feed printed raw routes, so an admin read
/// `POST /api/auth/login` next to a phone number to understand their own audit
/// trail. The headline is a sentence now; the raw fields stay in the detail sheet.
void main() {
  OperationLog log({String path = '', String phone = '', String action = ''}) =>
      OperationLog(path: path, userPhone: phone, action: action);

  group('routes become sentences', () {
    test('login names the act and who did it', () {
      final en = logPhrase(log(path: '/api/auth/login', phone: '07701234567'), ar: false);
      expect(en.title, 'Login request');
      expect(en.by, 'by phone 07701234567');
      expect(en.line, 'Login request · by phone 07701234567');
    });

    test('the same entry in Arabic is Arabic, not a fallback', () {
      final ar = logPhrase(log(path: '/api/auth/login', phone: '07701234567'), ar: true);
      expect(ar.title, 'طلب تسجيل دخول');
      expect(ar.by, contains('07701234567'));
      expect(RegExp(r'[؀-ۿ]').hasMatch(ar.title), isTrue);
    });

    test('the money and selling routes read as business events', () {
      expect(logPhrase(log(path: '/api/balance/grant'), ar: false).title, 'Balance transfer');
      expect(logPhrase(log(path: '/api/inventory/product/sendForPrinting'), ar: false).title,
          'Voucher sold');
      expect(logPhrase(log(path: '/api/pos-users/onboard'), ar: false).title, 'POS point created');
    });

    test('a query string does not defeat the match', () {
      expect(logPhrase(log(path: '/api/entity/update?id=abc123'), ar: false).title,
          'Account updated');
    });

    test('report/admin/health families collapse to one phrase each', () {
      expect(logPhrase(log(path: '/api/reports/sales'), ar: false).title, 'Report viewed');
      expect(logPhrase(log(path: '/api/admin/overview'), ar: false).title, 'Oversight feed');
      expect(logPhrase(log(path: '/api/health/ram'), ar: false).title, 'Health check');
    });
  });

  group('nothing leaks a URL', () {
    test('an unknown route degrades to a translated "request"', () {
      // Automated/bot traffic lands here — it stays a "request", per the ask,
      // but a translated one rather than a raw path.
      for (final p in ['/api/some/future/route', '/internal/ping', '/api/x']) {
        final en = logPhrase(log(path: p), ar: false);
        final ar = logPhrase(log(path: p), ar: true);
        expect(en.title, 'Request');
        expect(ar.title, 'طلب');
        expect(en.line.contains('/'), isFalse, reason: 'a URL must never reach the headline: $p');
        expect(ar.line.contains('/'), isFalse);
      }
    });

    test('a client-side entry uses its action instead of a route', () {
      expect(logPhrase(log(action: 'print_failed'), ar: false).title, 'print_failed');
    });

    test('an entry with neither path nor action still says something', () {
      expect(logPhrase(log(), ar: false).title, 'Request');
      expect(logPhrase(log(), ar: true).title, 'طلب');
    });
  });

  test('no phone means no dangling separator', () {
    final p = logPhrase(log(path: '/api/auth/login'), ar: false);
    expect(p.by, isNull);
    expect(p.line, 'Login request');
    expect(p.line.endsWith('·'), isFalse);
  });
}
