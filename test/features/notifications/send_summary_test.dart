// UX-88 — the broadcast confirmation.
//
// "Notification sent!" was the same six characters whether the message went to
// one shop or to every account in the country, so it confirmed that a button had
// been pressed and nothing about what the press did. The backend now answers the
// send with a delivery tally and this is the string that reports it; the wording
// is decided by arithmetic (nothing reached / the audience already states the
// number / append the reach) plus Arabic number agreement, none of which shows up
// in a widget test.
//
// These assert the real strings the page emits — `notificationStringsFor` is the
// page's own `_S`, not a copy of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';
import 'package:inteshar/features/notifications/presentation/notifications_compose_page.dart';

void main() {
  final en = notificationStringsFor(false);
  final ar = notificationStringsFor(true);

  group('sentSummary — the reach is named', () {
    test('an everyone broadcast reports the account count', () {
      expect(
        en.sentSummary(
            alert: false,
            audience: 'everyone',
            accounts: 42,
            recipients: 57,
            posOnly: false),
        'Notification sent to everyone — reached 42 accounts',
      );
      expect(
        ar.sentSummary(
            alert: false,
            audience: 'الجميع',
            accounts: 42,
            recipients: 57,
            posOnly: false),
        'أُرسل الإشعار إلى الجميع — وصل إلى 42 حساباً',
      );
    });

    test('an alert says it was an alert, not a notification', () {
      final out = en.sentSummary(
          alert: true,
          audience: 'Main Agents',
          accounts: 3,
          recipients: 5,
          posOnly: false);
      expect(out, 'Alert sent to Main Agents — reached 3 accounts');
      expect(out.contains('Notification'), isFalse);
    });

    test('a POS-only send counts operators, not accounts', () {
      // The account count is the wrong unit here: the sender narrowed to people.
      expect(
        en.sentSummary(
            alert: false,
            audience: 'all POS operators',
            accounts: 40,
            recipients: 55,
            posOnly: true),
        'Notification sent to all POS operators — reached 55 POS operators',
      );
      expect(
        ar.sentSummary(
            alert: false,
            audience: 'كل مستخدمي نقاط البيع',
            accounts: 40,
            recipients: 55,
            posOnly: true),
        'أُرسل الإشعار إلى كل مستخدمي نقاط البيع — وصل إلى 55 مستخدماً لنقاط البيع',
      );
    });
  });

  group('sentSummary — the cases that must not read as plain success', () {
    test('a send nothing can receive says so instead of claiming a reach', () {
      expect(
        en.sentSummary(
            alert: true,
            audience: 'Stores',
            accounts: 0,
            recipients: 0,
            posOnly: false),
        'Alert sent to Stores — but no account can receive it yet',
      );
      expect(
        ar.sentSummary(
            alert: true,
            audience: 'المتاجر',
            accounts: 0,
            recipients: 0,
            posOnly: false),
        'أُرسل التنبيه إلى المتاجر — لكن لا يوجد حساب يمكنه استلامه',
      );
    });

    test('a short reach on a picked audience is still stated', () {
      // 5 shops picked, 3 reachable — the discrepancy is the whole point.
      expect(
        en.sentSummary(
            alert: false,
            audience: '5 accounts',
            accounts: 3,
            recipients: 3,
            posOnly: false,
            audienceAccounts: 5),
        'Notification sent to 5 accounts — reached 3 accounts',
      );
    });

    test('a full reach on a picked audience does not say the number twice', () {
      expect(
        en.sentSummary(
            alert: false,
            audience: '5 accounts',
            accounts: 5,
            recipients: 9,
            posOnly: false,
            audienceAccounts: 5),
        'Notification sent to 5 accounts',
      );
    });
  });

  group('Arabic number agreement', () {
    test('accounts: singular, dual, broken plural, accusative singular', () {
      expect(ar.accountsPhrase(1), 'حساب واحد');
      expect(ar.accountsPhrase(2), 'حسابين');
      expect(ar.accountsPhrase(3), '3 حسابات');
      expect(ar.accountsPhrase(10), '10 حسابات');
      expect(ar.accountsPhrase(11), '11 حساباً');
      expect(ar.accountsPhrase(100), '100 حساباً');
    });

    test('POS operators follow the same three-way agreement', () {
      expect(ar.posUsersPhrase(1), 'مستخدم نقطة بيع واحد');
      expect(ar.posUsersPhrase(2), 'مستخدمَين لنقاط البيع');
      expect(ar.posUsersPhrase(4), '4 مستخدمين لنقاط البيع');
      expect(ar.posUsersPhrase(30), '30 مستخدماً لنقاط البيع');
    });

    test('the audience chip reuses the same agreement', () {
      // It used to render "2 حسابات" / "12 حسابات" from one template.
      expect(ar.audAccounts(2), 'حسابين');
      expect(ar.audAccounts(12), '12 حساباً');
      expect(en.audAccounts(1), '1 account');
    });

    test('the two languages actually differ and Arabic is Arabic', () {
      final a = ar.sentSummary(
          alert: false, audience: 'x', accounts: 3, recipients: 3, posOnly: false);
      final e = en.sentSummary(
          alert: false, audience: 'x', accounts: 3, recipients: 3, posOnly: false);
      expect(a, isNot(e));
      expect(RegExp(r'[؀-ۿ]').hasMatch(a), isTrue);
      expect(a.contains(r'$audience'), isFalse, reason: 'raw placeholder leaked: $a');
      expect(a.contains(r'$reach'), isFalse, reason: 'raw placeholder leaked: $a');
    });
  });

  group('NotificationReach — a missing tally is not a zero tally', () {
    test('reads the counts the backend sends', () {
      final r = NotificationReach.fromJson(
          const {'accounts': 7, 'recipients': 12, 'notification': {'id': 'n-1'}});
      expect(r.hasTally, isTrue);
      expect(r.accounts, 7);
      expect(r.recipients, 12);
    });

    test('a pre-tally backend response reports no tally rather than zero', () {
      // A backend that has not been redeployed answers with the bare
      // notification; reading that as "reached 0 accounts" would announce a
      // failure over a broadcast that went out fine.
      final r = NotificationReach.fromJson(const {'id': 'n-1', 'title': 'x'});
      expect(r.hasTally, isFalse);
      expect(r.accounts, isNull);
    });

    test('a genuine zero is a tally', () {
      final r = NotificationReach.fromJson(const {'accounts': 0, 'recipients': 0});
      expect(r.hasTally, isTrue);
      expect(r.accounts, 0);
    });
  });
}
