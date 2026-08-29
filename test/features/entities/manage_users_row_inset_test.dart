import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// UX-135 — the user row's inset has to follow the text direction.
///
/// The row is an `InkCard` with a `ruleColor`, and the card paints that ridge
/// with `PositionedDirectional(start: 0)`. Its padding, though, was
/// `EdgeInsets.fromLTRB(14, 10, 8, 10)` — *physical* edges. So in English the
/// ridge got 14px of clearance and in Arabic — the app's primary locale, and the
/// one every operator actually uses — the ridge moved to the right edge while
/// its clearance stayed on the left. The role stripe ended up 6px tighter
/// against the phone number than it was ever drawn to be, on every user row in
/// the sheet.
///
/// The assertion is the rendered distance from the card's START edge to the
/// row's first glyph, measured in both directions. It says nothing about *which*
/// number the padding is; it says the two locales get the same one.
void main() {
  setUpAll(() async {
    // The default test font draws every glyph as a square of the font size, so
    // any measurement that depends on where text lands is fiction without the
    // real faces (see `sku_row_render_test`).
    final codec = FontLoader('CodecPro');
    for (final f in [
      'CodecPro-Heavy.ttf',
      'CodecPro-Bold.ttf',
      'CodecPro-Regular.ttf',
      'CodecPro-News.ttf',
    ]) {
      codec.addFont(Future.value(
          ByteData.sublistView(await File('assets/fonts/$f').readAsBytes())));
    }
    await codec.load();

    final mono = FontLoader('JetBrainsMono');
    for (final f in ['JetBrainsMono-Regular.ttf', 'JetBrainsMono-Medium.ttf']) {
      mono.addFont(Future.value(ByteData.sublistView(
          await File('assets/fonts/mono/$f').readAsBytes())));
    }
    await mono.load();
  });

  const entity = Entity(
    id: 'a2-rusafa',
    meta: EntityMeta(name: 'Rusafa Sub'),
    type: EntityType.AGENT2,
    users: [
      EntityUser(id: 'u1', phone: '07700000001', role: UserRole.ADMIN),
      EntityUser(id: 'u2', phone: '07700000002', role: UserRole.USER),
    ],
  );

  /// Renders the sheet in [code] and returns the gap between the first user
  /// card's START edge and the person icon inside it.
  Future<double> startInset(WidgetTester tester, String code) async {
    await tester.pumpWidget(MaterialApp(
      locale: Locale(code),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ManageUsersSheet(
          entity: entity,
          onSave: (_) async {},
          onResetPassword: (_, _) async {},
          onResetTotp: (_) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final cardFinder = find.ancestor(
      of: find.byIcon(Icons.person_outline).first,
      matching: find.byType(InkCard),
    );
    expect(cardFinder, findsOneWidget,
        reason: 'the user row is the ruled InkCard this test is about');

    final card = tester.renderObject<RenderBox>(cardFinder);
    final icon =
        tester.renderObject<RenderBox>(find.byIcon(Icons.person_outline).first);
    final c0 = card.localToGlobal(Offset.zero);
    final i0 = icon.localToGlobal(Offset.zero);

    final rtl = Directionality.of(tester.element(cardFinder)) == TextDirection.rtl;
    return rtl
        ? (c0.dx + card.size.width) - (i0.dx + icon.size.width)
        : i0.dx - c0.dx;
  }

  testWidgets('the row opens the same distance from the start edge in ar and en',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final en = await startInset(tester, 'en');
    final ar = await startInset(tester, 'ar');

    expect(ar, en,
        reason: 'physical LTRB insets on a directional card: the role ridge '
            'and the clearance drawn for it end up on opposite edges in Arabic');
    expect(tester.takeException(), isNull);
  });
}
