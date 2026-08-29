import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/multi_select.dart';

/// UX-11 — the contextual action bar, driven end to end.
///
/// These press real controls and read what is really on screen, because the two
/// properties that matter cannot be seen from the state machine alone: whether a
/// half-failed run tells the truth, and whether a destructive batch is harder to
/// hit than a harmless one.
void main() {
  /// A host that owns the state exactly the way a page does, so the assertions
  /// can read what the bar handed BACK rather than what it was given.
  late SelectionState state;
  late int reloads;

  Future<void> pump(
    WidgetTester tester, {
    required List<String> visible,
    required List<BulkAction> actions,
    SelectionState? initial,
  }) async {
    state = initial ?? SelectionState.off.enter().selectAll(visible);
    reloads = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildBrandThemes().light,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setLocal) => SelectionBar(
            state: state,
            visibleIds: visible,
            actions: actions,
            unit: const BulkUnit(ar: 'دفعة', en: 'batches'),
            onChanged: (s) => setLocal(() => state = s),
            onCompleted: () async => reloads++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  BulkAction action(
    String label, {
    BulkSeverity severity = BulkSeverity.ordinary,
    Set<String> failOn = const {},
    List<String>? log,
  }) =>
      BulkAction(
        label: label,
        icon: Icons.bolt_outlined,
        severity: severity,
        title: (n) => '$label $n?',
        body: (_) => 'body',
        run: (id) async {
          log?.add(id);
          if (failOn.contains(id)) throw Exception('refused $id');
        },
      );

  /// Every `Text` inside the bar, in render order.
  List<String> barText(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
        of: find.byType(SelectionBar),
        matching: find.byType(Text),
      ))
      .map((t) => t.data ?? '')
      .toList();

  testWidgets('the bar states the live count', (tester) async {
    await pump(tester, visible: ['a', 'b', 'c'], actions: [action('Go')]);
    expect(find.text('3 selected'), findsOneWidget);

    // Untick one through the state the bar handed back.
    await tester.tap(find.byKey(const Key('selection-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('select-all covers exactly the rows on screen', (tester) async {
    await pump(
      tester,
      visible: ['a', 'b'],
      actions: [action('Go')],
      initial: SelectionState.off.enter(),
    );
    await tester.tap(find.byKey(const Key('selection-select-all')));
    await tester.pumpAndSettle();
    expect(state.ids, {'a', 'b'});
  });

  testWidgets('an action with nothing selected is dead', (tester) async {
    await pump(
      tester,
      visible: ['a'],
      actions: [action('Go')],
      initial: SelectionState.off.enter(),
    );
    final button = tester.widget<OutlinedButton>(find.ancestor(
      of: find.text('Go'),
      matching: find.byType(OutlinedButton),
    ));
    expect(button.onPressed, isNull);
  });

  testWidgets('a destructive action is rendered after the harmless ones',
      (tester) async {
    // The first slot is where a hurried thumb lands. It must not be Withdraw.
    await pump(tester, visible: ['a'], actions: [
      action('Withdraw', severity: BulkSeverity.danger),
      action('Resume'),
    ]);
    final text = barText(tester);
    expect(text.indexOf('Resume'), greaterThanOrEqualTo(0));
    expect(text.indexOf('Withdraw'), greaterThan(text.indexOf('Resume')),
        reason: 'the caller listed Withdraw first; the bar must still put the '
            'destructive action last');
  });

  testWidgets('a rule is really drawn before the destructive action',
      (tester) async {
    // The separation is the safety affordance, so assert it EXISTS and has a
    // size — a rule that is present in the tree but measures zero high would
    // separate nothing, and inside a `Wrap` (loose cross-axis constraints) that
    // is the easy way to get it wrong.
    await pump(tester, visible: ['a'], actions: [
      action('Resume'),
      action('Withdraw', severity: BulkSeverity.danger),
    ]);
    final rule = find.descendant(
        of: find.byType(SelectionBar), matching: find.byType(Hairline));
    expect(rule, findsOneWidget);
    expect(tester.getSize(rule).height, greaterThan(0));
  });

  testWidgets('a list with no destructive action gets no rule', (tester) async {
    await pump(tester, visible: ['a'], actions: [action('Resume')]);
    expect(
        find.descendant(
            of: find.byType(SelectionBar), matching: find.byType(Hairline)),
        findsNothing);
  });

  testWidgets('a clean run reports the count and closes the bar',
      (tester) async {
    final log = <String>[];
    await pump(tester, visible: ['a', 'b'], actions: [action('Go', log: log)]);

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(log, ['a', 'b']);
    expect(state.active, isFalse);
    expect(state.ids, isEmpty);
    expect(reloads, 1, reason: 'the rows changed; the list must re-fetch');
    expect(find.text('Done on 2 batches'), findsOneWidget);
  });

  testWidgets('a half-failed run says what landed and keeps the failures',
      (tester) async {
    // The whole point of UX-11: 7 of 10 is the normal case, and a blanket
    // "done" or a bare "3 failed" are both lies.
    final log = <String>[];
    await pump(tester, visible: ['a', 'b', 'c'], actions: [
      action('Go', failOn: {'b'}, log: log),
    ]);

    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(log, ['a', 'b', 'c'],
        reason: 'a refusal must not stop the rows after it');
    expect(state.active, isTrue);
    expect(state.ids, {'b'},
        reason: 'the failure stays ticked so retrying is one more tap');

    final snack = tester
        .widgetList<Text>(find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Text),
        ))
        .map((t) => t.data ?? '')
        .join();
    expect(snack, contains('Done on 2 of 3'),
        reason: 'it must lead with what DID happen');
    expect(snack, contains('1'));
    expect(find.text('Done on 3 batches'), findsNothing);
  });

  testWidgets('a run that fails everywhere still reports honestly',
      (tester) async {
    await pump(tester, visible: ['a', 'b'], actions: [
      action('Go', failOn: {'a', 'b'}),
    ]);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(state.ids, {'a', 'b'});
    expect(find.textContaining('Done on 0 of 2'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation touches nothing', (tester) async {
    final log = <String>[];
    await pump(tester, visible: ['a'], actions: [action('Go', log: log)]);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-dialog-cancel')));
    await tester.pumpAndSettle();

    expect(log, isEmpty);
    expect(state.ids, {'a'});
    expect(reloads, 0);
  });

  group('the irreversible gate', () {
    Future<void> openGate(WidgetTester tester, List<String> visible) async {
      await pump(tester, visible: visible, actions: [
        action('Delete', severity: BulkSeverity.irreversible),
      ]);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    FilledButton confirmButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('bulk-confirm-confirm')));

    testWidgets('the confirm button is dead until the count is typed',
        (tester) async {
      await openGate(tester, ['a', 'b', 'c']);
      expect(confirmButton(tester).onPressed, isNull,
          reason: 'deleting three rows must cost more than one reflex tap');

      await tester.enterText(
          find.byKey(const Key('bulk-confirm-count-field')), '2');
      await tester.pumpAndSettle();
      expect(confirmButton(tester).onPressed, isNull,
          reason: 'a near-miss is not a confirmation');

      await tester.enterText(
          find.byKey(const Key('bulk-confirm-count-field')), '3');
      await tester.pumpAndSettle();
      expect(confirmButton(tester).onPressed, isNotNull);
    });

    testWidgets('the dialog names the count itself', (tester) async {
      // Structural: the caller supplies a sentence, but the dialog prints the
      // number, so no batch confirmation in the app can end up countless.
      await openGate(tester, ['a', 'b', 'c']);
      expect(find.text('3 batches'), findsOneWidget);
    });
  });

  testWidgets('an ordinary confirmation also names the count', (tester) async {
    await pump(tester, visible: ['a', 'b'], actions: [action('Go')]);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 batches'), findsOneWidget);
  });
}
