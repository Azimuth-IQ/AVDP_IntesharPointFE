import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pos_admin/presentation/confirm_operator_reset.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// Both resets take effect immediately on someone who is usually mid-shift, so
/// the answer these return is what gates the call. Asserted on the returned
/// value rather than on the dialog's internals, because the returned value is
/// what the caller actually obeys.
void main() {
  late bool? answer;

  Widget harness(Future<bool> Function(BuildContext) ask,
      {Locale locale = const Locale('en')}) {
    answer = null;
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async => answer = await ask(ctx),
            child: const Text('go'),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  group('PIN reset', () {
    testWidgets('refuses by default when dismissed', (tester) async {
      await tester.pumpWidget(harness((c) => confirmResetPin(c)));
      await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('returns true only when explicitly confirmed', (tester) async {
      await tester.pumpWidget(harness((c) => confirmResetPin(c)));
      await open(tester);
      await tester.tap(find.byKey(const Key('confirm-operator-reset')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('names the shop and says selling stops', (tester) async {
      await tester
          .pumpWidget(harness((c) => confirmResetPin(c, posName: 'Al Noor')));
      await open(tester);
      // The admin has to know WHOSE PIN and that someone is now blocked from
      // selling — that is the whole reason for the prompt.
      expect(find.textContaining('Al Noor'), findsOneWidget);
      expect(find.textContaining('cannot sell'), findsOneWidget);
    });
  });

  group('two-factor reset', () {
    testWidgets('refuses by default when dismissed', (tester) async {
      await tester.pumpWidget(harness((c) => confirmResetTotp(c)));
      await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('warns the enrolment code is shown once', (tester) async {
      await tester.pumpWidget(harness((c) => confirmResetTotp(c)));
      await open(tester);
      // The once-only enrolment code is the part that strands people: miss it
      // and the account needs another reset to get back in.
      expect(find.textContaining('once'), findsOneWidget);
    });

    testWidgets('asks in Arabic under an Arabic locale', (tester) async {
      await tester.pumpWidget(
          harness((c) => confirmResetTotp(c), locale: const Locale('ar')));
      await open(tester);
      expect(find.text('إلغاء'), findsOneWidget);
      expect(find.textContaining('المصادقة الثنائية'), findsWidgets);
    });
  });
}
