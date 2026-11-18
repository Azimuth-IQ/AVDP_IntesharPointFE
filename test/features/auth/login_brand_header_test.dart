import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/features/auth/data/login_brand.dart';
import 'package:inteshar/features/auth/presentation/login_brand_header.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// PROD-006 — the real sign-in headers (phone and wide) in each of their three states.
void main() {
  Future<void> pump(WidgetTester tester, Widget header,
      {LoginBrand? remembered, required bool showInteshar}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rememberedLoginBrandProvider.overrideWith((ref) async => remembered),
        loginShowIntesharProvider.overrideWith((ref) async => showInteshar),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: appSupportedLocales,
        home: Scaffold(body: SizedBox(width: 800, child: header)),
      ),
    ));
    await tester.pump(); // let both providers resolve
    await tester.pump();
  }

  const agent = LoginBrand(logoUrl: 'https://media.test/agent.png');

  for (final header in const <Widget>[LoginMobileBrandHeader(), LoginBrandPanel()]) {
    final name = header.runtimeType.toString();

    testWidgets('$name: a device that signed in before shows its agent, not Inteshar', (tester) async {
      await pump(tester, header, remembered: agent, showInteshar: true);
      expect(find.text('Inteshar'), findsNothing);
      expect(find.byType(IntesharStar), findsNothing);
      expect(find.byType(Image), findsOneWidget, reason: 'the agent logo');
    });

    testWidgets('$name: a new device shows Inteshar while HQ allows it', (tester) async {
      await pump(tester, header, showInteshar: true);
      expect(find.text('Inteshar'), findsOneWidget);
      expect(find.byType(IntesharStar), findsOneWidget);
    });

    testWidgets('$name: HQ switched it off — a new device shows no brand at all', (tester) async {
      await pump(tester, header, showInteshar: false);
      expect(find.text('Inteshar'), findsNothing);
      expect(find.byType(IntesharStar), findsNothing);
      expect(find.byType(Image), findsNothing);
    });
  }
}
