import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pos/presentation/pos_home_page.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// B-095: the POS header puts the step title and the live balance on ONE row, on
/// a 360dp counter terminal. A shop with real money in it (`25,876,000 IQD`) used
/// to starve the title down to ~90px and clip "تأكيد البيع" → "تأكيد ال…" on the
/// CONFIRM step — the screen where the operator most needs to read what they're
/// selling. These pin the layout contract so that can't silently come back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The default test font draws every glyph as a square of the font size, which
  // makes "does this title fit?" meaningless — the whole point here is real
  // metrics. Load the shipped CodecPro so these assertions measure what a POS
  // operator actually sees.
  setUpAll(() async {
    final loader = FontLoader('CodecPro');
    for (final f in ['CodecPro-Heavy.ttf', 'CodecPro-ExtraBold.ttf', 'CodecPro-Regular.ttf']) {
      final bytes = await File('assets/fonts/$f').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  // A Sunmi V2 counter is ~360dp wide; that's the budget everything must fit in.
  Future<void> pumpHeader(
    WidgetTester tester, {
    required String title,
    num? available,
    bool withBack = false,
    Locale locale = const Locale('ar'),
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PosStepHeader(
            title: title,
            balance: available == null ? null : AgentBalance(available: available),
            onBack: withBack ? () {} : null,
            backTooltip: 'cancel',
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The laid-out title paragraph — `didExceedMaxLines` is true exactly when the
  /// ellipsis kicked in, which is the failure we're guarding against.
  RenderParagraph titleParagraph(WidgetTester tester, String title) =>
      tester.renderObject<RenderParagraph>(find.text(title));

  const bigBalance = 25876000;

  group('a large balance must not clip the title', () {
    testWidgets('confirm step (back arrow) keeps the Arabic title intact', (tester) async {
      await pumpHeader(tester, title: 'تأكيد البيع', available: bigBalance, withBack: true);

      expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow');
      expect(
        titleParagraph(tester, 'تأكيد البيع').didExceedMaxLines,
        isFalse,
        reason: 'the confirm-sale title must never ellipsise — this was the B-095 bug',
      );
    });

    testWidgets('English confirm step also survives the back arrow', (tester) async {
      await pumpHeader(
        tester,
        title: 'Confirm sale',
        available: bigBalance,
        withBack: true,
        locale: const Locale('en'),
      );

      expect(tester.takeException(), isNull);
      expect(titleParagraph(tester, 'Confirm sale').didExceedMaxLines, isFalse);
    });

    testWidgets('category step (no back arrow) keeps its title intact', (tester) async {
      await pumpHeader(tester, title: 'اختر الفئة', available: bigBalance);

      expect(tester.takeException(), isNull);
      expect(titleParagraph(tester, 'اختر الفئة').didExceedMaxLines, isFalse);
    });
  });

  group('the balance itself', () {
    testWidgets('renders in FULL — money shrinks, it never ellipsises', (tester) async {
      await pumpHeader(tester, title: 'تأكيد البيع', available: bigBalance, withBack: true);

      // The whole number is present; a truncated "25,876,0…" would be a worse lie
      // than smaller numerals on a screen used to decide whether a sale can happen.
      expect(find.text('25,876,000 IQD'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('25,876,000 IQD')).overflow,
        isNot(TextOverflow.ellipsis),
      );
      // It scales down instead.
      expect(
        find.ancestor(of: find.text('25,876,000 IQD'), matching: find.byType(FittedBox)),
        findsOneWidget,
      );
    });

    testWidgets('an absurd balance still does not overflow the row', (tester) async {
      await pumpHeader(tester, title: 'تأكيد البيع', available: 999999999999, withBack: true);

      expect(tester.takeException(), isNull);
      expect(find.text('999,999,999,999 IQD'), findsOneWidget);
    });

    testWidgets('a null balance shows a dash and takes almost no width', (tester) async {
      await pumpHeader(tester, title: 'اختر الفئة');

      expect(tester.takeException(), isNull);
      expect(find.text('—'), findsOneWidget);
      expect(titleParagraph(tester, 'اختر الفئة').didExceedMaxLines, isFalse);
    });
  });

  testWidgets('the title steps down a size on a narrow counter', (tester) async {
    await pumpHeader(tester, title: 'اختر الفئة', available: bigBalance);
    final narrowSize = titleParagraph(tester, 'اختر الفئة').text.style!.fontSize;

    await pumpHeader(
      tester,
      title: 'اختر الفئة',
      available: bigBalance,
      size: const Size(900, 800),
    );
    final wideSize = titleParagraph(tester, 'اختر الفئة').text.style!.fontSize;

    expect(narrowSize, lessThan(wideSize!));
  });
}
