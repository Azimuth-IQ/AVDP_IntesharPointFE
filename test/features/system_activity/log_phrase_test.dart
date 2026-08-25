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

    test('B-110: each report names ITSELF rather than collapsing', () {
      // The first pass lumped every report into "Report viewed", which told an
      // admin nothing about what was actually looked at.
      expect(logPhrase(log(path: '/api/reports/sales'), ar: false).title, 'Sales report');
      expect(logPhrase(log(path: '/api/reports/balances'), ar: false).title, 'Balances report');
      expect(logPhrase(log(path: '/api/admin/overview'), ar: false).title, 'Oversight dashboard');
      expect(logPhrase(log(path: '/api/health/ram'), ar: false).title, 'Health check');
    });

    test('B-110: reads are named too — they are most of the feed', () {
      // Every screen load fires several GETs; leaving them as "Request" is why
      // the monitor still looked untranslated after the first pass.
      expect(logPhrase(log(path: '/api/entity/me'), ar: false).title, 'Session loaded');
      expect(logPhrase(log(path: '/api/entity/children'), ar: false).title, 'Sub-accounts list');
      expect(logPhrase(log(path: '/api/inventory/product/sellable'), ar: false).title,
          'Sellable stock');
      expect(logPhrase(log(path: '/api/pricing/catalog'), ar: false).title, 'Price list');
      expect(logPhrase(log(path: '/api/chat/threads'), ar: false).title, 'Conversations list');
    });

    test('B-110: id-bearing routes resolve, not just static ones', () {
      expect(logPhrase(log(path: '/api/notifications/abc123/read'), ar: false).title,
          'Notification read');
      expect(logPhrase(log(path: '/api/settings/auth.totp.required.STORE'), ar: false).title,
          'Platform setting changed');
      expect(logPhrase(log(path: '/api/slider/xyz'), ar: false).title, 'Slider updated');
    });

    test('B-110: a more specific route wins over its prefix', () {
      // /product/draw-bulk and /product/draw/recover must not be eaten by /product/draw.
      expect(logPhrase(log(path: '/api/inventory/product/draw'), ar: false).title,
          'Voucher drawn');
      expect(logPhrase(log(path: '/api/inventory/product/draw-bulk'), ar: false).title,
          'Bulk voucher sale');
      expect(logPhrase(log(path: '/api/inventory/product/draw/recover'), ar: false).title,
          'Sale recovery');
      expect(logPhrase(log(path: '/api/inventory/product/draw/recover-batch'), ar: false).title,
          'Bulk sale recovery');
      expect(logPhrase(log(path: '/api/entity/users/add'), ar: false).title, 'User added');
      expect(logPhrase(log(path: '/api/entity/users'), ar: false).title, 'User list');
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

  // C-19. The lookup is a substring test walked in declaration order, so the
  // shortest of a family of routes will answer for all of them if it is listed
  // first. Three routes that share a stem is exactly where that goes wrong, and
  // an admin reading "stock retired" against a plain list view would be looking
  // at an event that never happened.
  group('the three retire routes each keep their own sentence', () {
    test('retiring, restoring and listing do not collapse into one phrase', () {
      final retire = logPhrase(log(path: '/api/inventory/retire'), ar: false).title;
      final restore = logPhrase(log(path: '/api/inventory/retire/restore'), ar: false).title;
      final list = logPhrase(log(path: '/api/inventory/retired'), ar: false).title;

      expect(retire, 'Stock retired permanently');
      expect(restore, 'Retired stock restored');
      expect(list, 'Retired stock list');
      expect({retire, restore, list}, hasLength(3));
    });

    test('and none of them is mistaken for the ordinary withdraw', () {
      expect(logPhrase(log(path: '/api/inventory/withdraw'), ar: false).title,
          'Stock withdrawn from an agent');
      expect(logPhrase(log(path: '/api/inventory/retire'), ar: false).title,
          isNot('Stock withdrawn from an agent'));
    });

    test('the Arabic side is Arabic, not an English fallback', () {
      for (final path in [
        '/api/inventory/retire',
        '/api/inventory/retire/restore',
        '/api/inventory/retired',
      ]) {
        final title = logPhrase(log(path: path), ar: true).title;
        expect(RegExp(r'[؀-ۿ]').hasMatch(title), isTrue, reason: path);
      }
    });
  });
}
