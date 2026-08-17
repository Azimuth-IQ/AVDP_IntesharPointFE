import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pos_admin/domain/archived_pos.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_archive.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// The archive list: the countdown the server sent, and the permanent-delete
/// button that must stay shut until the window has actually passed.
void main() {
  const waiting = ArchivedPos(
    id: 's1',
    name: 'Rusafa Mobiles',
    hostName: 'Baghdad Main',
    operatorPhone: '07813300001',
    daysRemaining: 12,
    purgeable: false,
  );

  const due = ArchivedPos(
    id: 's2',
    name: 'Al Noor',
    hostName: 'Baghdad Main',
    operatorPhone: '07813300002',
    daysRemaining: 0,
    purgeable: true,
  );

  Widget harness(List<ArchivedPos> rows, {
    Set<String> busy = const {},
    ValueChanged<ArchivedPos>? onPurge,
    ValueChanged<ArchivedPos>? onDownload,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PosArchiveList(
            rows: rows,
            busyIds: busy,
            onDownload: onDownload ?? (_) {},
            onPurge: onPurge ?? (_) {},
          ),
        ),
      ),
    );
  }

  ButtonStyleButton purgeButton(WidgetTester tester, String id) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key('purge-$id')));

  testWidgets('a shop still inside its window cannot be deleted', (tester) async {
    await tester.pumpWidget(harness([waiting]));
    expect(purgeButton(tester, 's1').onPressed, isNull,
        reason: 'the server refuses until the window elapses; offering it would just fail');
  });

  testWidgets('it shows the days the SERVER said remain', (tester) async {
    await tester.pumpWidget(harness([waiting]));
    expect(find.textContaining('12 days left'), findsOneWidget);
  });

  testWidgets('a shop past its window can be deleted permanently', (tester) async {
    await tester.pumpWidget(harness([due]));
    expect(purgeButton(tester, 's2').onPressed, isNotNull);
    expect(find.textContaining('Ready to delete'), findsOneWidget);
  });

  testWidgets('deleting fires for the row that was tapped', (tester) async {
    ArchivedPos? tapped;
    await tester.pumpWidget(harness([waiting, due], onPurge: (r) => tapped = r));
    await tester.tap(find.byKey(const Key('purge-s2')));
    await tester.pumpAndSettle();
    expect(tapped?.id, 's2');
  });

  testWidgets('the data download is offered whatever the countdown says',
      (tester) async {
    // Keeping the record must not depend on the shop being deletable yet.
    ArchivedPos? asked;
    await tester.pumpWidget(harness([waiting], onDownload: (r) => asked = r));
    await tester.tap(find.text('Download data'));
    await tester.pumpAndSettle();
    expect(asked?.id, 's1');
  });

  testWidgets('a row shows its host and operator so two branches are tellable apart',
      (tester) async {
    await tester.pumpWidget(harness([waiting]));
    expect(find.textContaining('under Baghdad Main'), findsOneWidget);
    expect(find.textContaining('07813300001'), findsOneWidget);
  });

  testWidgets('a row being worked on cannot be fired twice', (tester) async {
    await tester.pumpWidget(harness([due], busy: {'s2'}));
    expect(purgeButton(tester, 's2').onPressed, isNull);
  });

  testWidgets('every archived shop gets a row', (tester) async {
    await tester.pumpWidget(harness([waiting, due]));
    expect(find.text('Rusafa Mobiles'), findsOneWidget);
    expect(find.text('Al Noor'), findsOneWidget);
  });

  _arabicPlurals();

  group('ArchivedPos.fromJson', () {
    test('reads the server countdown rather than deriving one', () {
      final row = ArchivedPos.fromJson(const {
        'id': 's1',
        'name': 'Rusafa Mobiles',
        'daysRemaining': 7,
        'purgeable': false,
        'archivedAt': '2026-08-01T10:00:00Z',
      });
      expect(row.daysRemaining, 7);
      expect(row.purgeable, isFalse);
      expect(row.archivedAt, DateTime.utc(2026, 8, 1, 10));
    });

    test('a missing countdown does not silently read as deletable', () {
      final row = ArchivedPos.fromJson(const {'id': 's1', 'name': 'x'});
      expect(row.purgeable, isFalse,
          reason: 'defaulting to true would offer a permanent delete on no evidence');
    });
  });
}

/// Arabic counts days by band. "3 يوم" is what a machine writes; a native
/// speaker reads it as broken.
void _arabicPlurals() {
  group('daysLeftLabel in Arabic', () {
    Future<String> labelFor(WidgetTester tester, int days) async {
      late String out;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (ctx) {
          out = daysLeftLabel(ctx, days);
          return const SizedBox();
        }),
      ));
      return out;
    }

    testWidgets('one day is singular', (t) async {
      expect(await labelFor(t, 1), 'يتبقى يوم واحد');
    });
    testWidgets('two days uses the dual', (t) async {
      expect(await labelFor(t, 2), 'يتبقى يومان');
    });
    testWidgets('three to ten take the broken plural', (t) async {
      expect(await labelFor(t, 3), 'يتبقى 3 أيام');
      expect(await labelFor(t, 10), 'يتبقى 10 أيام');
    });
    testWidgets('eleven and up take the accusative singular', (t) async {
      expect(await labelFor(t, 11), 'يتبقى 11 يوماً');
      expect(await labelFor(t, 28), 'يتبقى 28 يوماً');
    });
  });
}
