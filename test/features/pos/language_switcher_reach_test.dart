import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/language_switcher_row.dart';

/// B-096: the POS shell never imports `app_scaffold.dart`, so while the language
/// switcher was private to that file a POS operator could not change the language
/// at ALL — they were stuck on the default locale. These pin the switcher as a
/// shared, reachable control rather than a detail of one shell.
void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Locale locale = const Locale('ar')}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers both locales and marks the active one', (tester) async {
    await pump(tester, const LanguageSwitcherRow());

    final seg = tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(seg.segments.map((s) => s.value), containsAll(<String>['ar', 'en']));
    expect(seg.selected, {'ar'}, reason: 'the running locale is the selected segment');
  });

  testWidgets('picking a locale actually drives the controller', (tester) async {
    late WidgetRef captured;
    await pump(
      tester,
      Consumer(builder: (_, ref, _) {
        captured = ref;
        return const LanguageSwitcherRow();
      }),
    );

    expect(captured.read(localeControllerProvider).languageCode, 'ar');

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(
      captured.read(localeControllerProvider).languageCode,
      'en',
      reason: 'tapping a segment must change the app locale, not just the chip',
    );
  });

  group('the sidebar toggle label', () {
    testWidgets('names the language you would switch TO, in its own script', (tester) async {
      await pump(tester, Builder(builder: (ctx) => Text(otherLanguageLabel(ctx))));
      expect(find.text('English'), findsOneWidget);

      await pump(
        tester,
        Builder(builder: (ctx) => Text(otherLanguageLabel(ctx))),
        locale: const Locale('en'),
      );
      expect(find.text('العربية'), findsOneWidget);
    });
  });
}
