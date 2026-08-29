import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/auth/presentation/login_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UX-12 — the server-endpoint sheet on the sign-in screen.
///
/// One field, one button, and until now Enter did nothing in it: the tester who
/// had just typed a backend address had to go find the button with a mouse.
///
/// These drive the real key (`TextInputAction.done`, which is what Enter sends
/// on a single-line field) through the real page and check the real
/// consequence — what [SessionStorage] ends up holding — rather than asserting
/// that a callback was wired.
/// The endpoint field's hint — the one string that tells it apart from the
/// phone/password fields behind the sheet.
const hint = 'http://192.168.1.x:8080';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: appSupportedLocales,
        home: LoginPage(),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The endpoint sheet is deliberately behind a long-press on the CTA.
  Future<void> openEndpointSheet(WidgetTester tester) async {
    await tester.longPress(find.byType(BrandCTAButton));
    await tester.pumpAndSettle();
    expect(urlField(), findsOneWidget, reason: 'the endpoint sheet never opened');
  }

  testWidgets('Enter in the endpoint field saves and closes the sheet',
      (tester) async {
    await pumpLogin(tester);
    await openEndpointSheet(tester);

    await tester.enterText(urlField(), 'http://10.0.0.5:8080');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(await SessionStorage().getBaseUrl(), 'http://10.0.0.5:8080');
    expect(urlField(), findsNothing, reason: 'the sheet stayed open after Enter');
  });

  testWidgets('Enter runs the SAME validation the button does', (tester) async {
    // The dangerous half-fix: a key that skips the check the button performs
    // and points the whole app at an unreachable backend with no feedback
    // (B-080). A rejected URL must leave the sheet up and storage untouched.
    await pumpLogin(tester);
    await openEndpointSheet(tester);

    await tester.enterText(urlField(), 'not a url');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(await SessionStorage().getBaseUrl(), SessionStorage.defaultBaseUrl);
    expect(urlField(), findsOneWidget,
        reason: 'Enter accepted a URL the button would have refused');
  });
}

/// The endpoint sheet's field, identified by the hint only it carries.
Finder urlField() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );
