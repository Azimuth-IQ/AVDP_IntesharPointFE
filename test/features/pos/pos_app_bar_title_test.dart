import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/printing/printer_service.dart';
import 'package:inteshar/features/pos/presentation/pos_app_bar_title.dart';
import 'package:inteshar/features/pos/presentation/printer_status_chip.dart';

/// PROD-011: on a Sunmi V2 the shop's name showed as "العقل …" next to the printer's name, with a
/// second line ("العداد المباشر · حُدّث الآن") the client did not understand.
void main() {
  // The V2's screen is 360 dp wide; this is what the bar leaves the title after the
  // printer icon (48) and sign-out (48) and the paddings.
  const v2TitleWidth = 230.0;

  Widget bar({required String name, Widget? printer}) => MaterialApp(
        theme: intesharLightTheme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(
              title: SizedBox(
                width: v2TitleWidth,
                child: PosAppBarTitle(shopName: name, leading: const SizedBox(width: 26, height: 26)),
              ),
              actions: [?printer],
            ),
          ),
        ),
      );

  testWidgets('a shop name longer than one line wraps to a second line instead of being cut',
      (tester) async {
    const name = 'العقل 1 للاتصالات والهواتف';
    await tester.pumpWidget(bar(name: name));
    final text = tester.widget<Text>(find.text(name));
    expect(text.maxLines, 2);
    final height = tester.getSize(find.text(name)).height;
    final oneLine = (text.style?.fontSize ?? 17) * (text.style?.height ?? 1.15);
    expect(height, greaterThan(oneLine * 1.5), reason: 'the name should take two lines, not one');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no "live counter" line under the name', (tester) async {
    await tester.pumpWidget(bar(name: 'العقل 1'));
    expect(find.textContaining('العداد المباشر'), findsNothing);
    expect(find.textContaining('حُدّث'), findsNothing);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('the icon-only printer chip shows no words, but keeps them as its tooltip', (tester) async {
    await tester.pumpWidget(bar(
      name: 'العقل 1',
      printer: PrinterStatusChip(state: const PrinterState(), ar: true, iconOnly: true, onTap: () {}),
    ));
    expect(find.text('إعداد الطابعة'), findsNothing);
    expect(find.byTooltip('إعداد الطابعة'), findsOneWidget);
    expect(tester.getSize(find.byType(PrinterStatusChip)).width, lessThanOrEqualTo(48));
  });
}
