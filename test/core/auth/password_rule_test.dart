// PROD-008: the strong-password rule (6+ characters, capital, small, number, symbol) and the
// checklist every new-password field shows under it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/auth/password_rule.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/new_password_field.dart';

void main() {
  group('PasswordRule', () {
    test('a password with every point is strong', () {
      expect(PasswordRule.isStrong('Abcde1!'), isTrue);
      expect(PasswordRule.isStrong('xY9#zz'), isTrue);
      expect(PasswordRule.missing('Abcde1!'), isEmpty);
      expect(PasswordRule.validate('Abcde1!', ar: true), isNull);
    });

    test('names exactly what is missing, in order', () {
      expect(PasswordRule.missing('123456'),
          [PasswordNeed.upper, PasswordNeed.lower, PasswordNeed.symbol]);
      expect(PasswordRule.missing('rootroot'),
          [PasswordNeed.upper, PasswordNeed.digit, PasswordNeed.symbol]);
      expect(PasswordRule.missing('Ab1!'), [PasswordNeed.length]);
      expect(PasswordRule.missing('ABCDEF1!'), [PasswordNeed.lower]);
      expect(PasswordRule.missing(''), PasswordNeed.values);
      expect(PasswordRule.missing(null), PasswordNeed.values);
    });

    test('the length counts the trimmed value, like the server', () {
      expect(PasswordRule.missing('  Ab1!  '), [PasswordNeed.length]);
    });

    test('Arabic letters are letters, not symbols, and not capital or small', () {
      // «كلمة» has no case: the rule still needs an English capital and small letter.
      expect(PasswordRule.missing('كلمةسر1'),
          [PasswordNeed.upper, PasswordNeed.lower, PasswordNeed.symbol]);
      expect(PasswordRule.isStrong('كلمةAb1@'), isTrue);
    });

    test('a space is not a symbol', () {
      expect(PasswordRule.missing('Abc de1'), [PasswordNeed.symbol]);
    });

    test('the message is in the reader\'s language and lists the missing points', () {
      expect(PasswordRule.validate('123456', ar: false),
          'Weak password — missing: A capital letter (A-Z), A small letter (a-z), A symbol such as @ # ! \$ %');
      expect(PasswordRule.validate('123456', ar: true), startsWith('كلمة المرور ضعيفة — ينقصها: '));
    });
  });

  group('NewPasswordField', () {
    Future<void> pump(WidgetTester tester, TextEditingController c, GlobalKey<FormState> key,
        {Locale locale = const Locale('en'), bool allowEmpty = false}) {
      return tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildBrandThemes().light,
        home: Scaffold(
          body: Form(
            key: key,
            child: NewPasswordField(controller: c, label: 'New password', allowEmpty: allowEmpty),
          ),
        ),
      ));
    }

    int ticks(WidgetTester tester) => tester.widgetList(find.byIcon(Icons.check_circle)).length;

    testWidgets('shows the whole rule before anything is typed', (tester) async {
      final c = TextEditingController();
      await pump(tester, c, GlobalKey<FormState>());
      expect(find.text('The password must have:'), findsOneWidget);
      for (final n in PasswordNeed.values) {
        expect(find.text(PasswordRule.label(n, ar: false)), findsOneWidget);
      }
      expect(ticks(tester), 0);
    });

    testWidgets('ticks each point as it is met while typing', (tester) async {
      final c = TextEditingController();
      await pump(tester, c, GlobalKey<FormState>());
      await tester.enterText(find.byType(TextFormField), 'abc');
      await tester.pump();
      expect(ticks(tester), 1); // small letter
      await tester.enterText(find.byType(TextFormField), 'Abc1');
      await tester.pump();
      expect(ticks(tester), 3); // + capital, number
      await tester.enterText(find.byType(TextFormField), 'Abc1!x');
      await tester.pump();
      expect(ticks(tester), 5); // + symbol, length
    });

    testWidgets('Save is refused until every point is met', (tester) async {
      final c = TextEditingController();
      final key = GlobalKey<FormState>();
      await pump(tester, c, key);
      await tester.enterText(find.byType(TextFormField), '123456');
      expect(key.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.textContaining('Weak password'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Inteshar#2026');
      expect(key.currentState!.validate(), isTrue);
    });

    testWidgets('an edit form may leave it blank to keep the current password', (tester) async {
      final c = TextEditingController();
      final key = GlobalKey<FormState>();
      await pump(tester, c, key, allowEmpty: true);
      expect(key.currentState!.validate(), isTrue);
      await tester.enterText(find.byType(TextFormField), 'weak');
      expect(key.currentState!.validate(), isFalse);
    });

    testWidgets('Arabic: the heading and the points are in Arabic', (tester) async {
      final c = TextEditingController();
      await pump(tester, c, GlobalKey<FormState>(), locale: const Locale('ar'));
      expect(find.text('كلمة المرور يجب أن تحتوي على:'), findsOneWidget);
      expect(find.text('حرف إنجليزي كبير (A-Z)'), findsOneWidget);
    });
  });
}
