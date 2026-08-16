import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/features/entities/domain/entity_dependents.dart';
import 'package:inteshar/features/entities/presentation/delete_agent_sheet.dart';

/// The clear-out sheet's states, asserted on the widgets an operator can act on
/// rather than on pixels: which rows offer a delete, and whether the account
/// itself is unlocked.
void main() {
  const blocked = EntityDependents(
    id: 'agent1-baghdad',
    name: 'Baghdad Main',
    type: 'AGENT1',
    subAgentCount: 2,
    storeCount: 2,
    deletable: false,
    subAgents: [
      DependentSubAgent(id: 'a2-1', name: 'Rusafa', storeCount: 2),
      DependentSubAgent(id: 'a2-2', name: 'Baquba', storeCount: 0),
    ],
    stores: [
      DependentStore(
          id: 's1', name: 'Rusafa Mobiles', hostName: 'Rusafa',
          operatorPhone: '07813300001'),
      DependentStore(
          id: 's2', name: 'Al Noor', hostName: 'Rusafa',
          operatorPhone: '07813300002'),
    ],
  );

  const cleared = EntityDependents(
    id: 'agent1-baghdad',
    name: 'Baghdad Main',
    type: 'AGENT1',
    deletable: true,
  );

  Widget harness(
    EntityDependents? deps, {
    Set<String> busy = const {},
    bool loading = false,
    Object? error,
    VoidCallback? onDeleteSelf,
    ValueChanged<DependentStore>? onDeleteStore,
    ValueChanged<DependentSubAgent>? onDeleteSubAgent,
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
        body: DeleteAgentSheetBody(
          entityName: 'Baghdad Main',
          entityId: 'agent1-baghdad',
          dependents: deps,
          loading: loading,
          error: error,
          busyIds: busy,
          onRetry: () {},
          onDeleteStore: onDeleteStore ?? (_) {},
          onDeleteSubAgent: onDeleteSubAgent ?? (_) {},
          onDeleteSelf: onDeleteSelf ?? () {},
        ),
      ),
    );
  }

  /// The final action, found by key: FilledButton.icon does not match byType.
  ButtonStyleButton finalButton(WidgetTester tester) => tester
      .widget<ButtonStyleButton>(find.byKey(const Key('deleteAgentFinalAction')));

  group('blocked', () {
    testWidgets('the account itself cannot be deleted yet', (tester) async {
      await tester.pumpWidget(harness(blocked));
      expect(finalButton(tester).onPressed, isNull,
          reason: 'the server would refuse it; offering it would just fail');
    });

    testWidgets('it says what is still attached', (tester) async {
      await tester.pumpWidget(harness(blocked));
      expect(find.textContaining('Still attached: 2 sub-agents and 2 points of sale'),
          findsOneWidget);
    });

    testWidgets('shops are listed before sub-agents, which is the order they must go in',
        (tester) async {
      await tester.pumpWidget(harness(blocked));
      final shops = tester.getTopLeft(find.text('Points of sale')).dy;
      final subs = tester.getTopLeft(find.text('Sub-agents')).dy;
      expect(shops, lessThan(subs));
    });

    testWidgets('a shop row can be deleted', (tester) async {
      DependentStore? tapped;
      await tester.pumpWidget(
          harness(blocked, onDeleteStore: (s) => tapped = s));
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      expect(tapped?.id, 's1');
    });

    testWidgets('a sub-agent still holding shops cannot be deleted', (tester) async {
      await tester.pumpWidget(harness(blocked));
      // Rusafa has 2 shops; Baquba has none.
      final buttons = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .toList();
      // Two shops (enabled), then Rusafa (disabled), then Baquba (enabled).
      expect(buttons[2].onPressed, isNull,
          reason: 'its own shops block it, and the row explains that');
      expect(buttons[3].onPressed, isNotNull);
    });

    testWidgets('a blocked sub-agent says why', (tester) async {
      await tester.pumpWidget(harness(blocked));
      expect(find.textContaining('2 points of sale must go first'), findsOneWidget);
    });

    testWidgets('a row being deleted shows progress instead of its button',
        (tester) async {
      await tester.pumpWidget(harness(blocked, busy: {'s1'}));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('cleared', () {
    testWidgets('the account can now be deleted', (tester) async {
      await tester.pumpWidget(harness(cleared));
      expect(finalButton(tester).onPressed, isNotNull);
    });

    testWidgets('the button names the account', (tester) async {
      await tester.pumpWidget(harness(cleared));
      expect(find.text('Delete Baghdad Main'), findsOneWidget);
    });

    testWidgets('it stops telling the operator to clear a list that is empty',
        (tester) async {
      await tester.pumpWidget(harness(cleared));
      expect(find.textContaining('Clear the list below first'), findsNothing);
      expect(find.textContaining('Nothing is attached'), findsOneWidget);
    });

    testWidgets('deleting the account fires once', (tester) async {
      var calls = 0;
      await tester.pumpWidget(harness(cleared, onDeleteSelf: () => calls++));
      await tester.tap(find.byKey(const Key('deleteAgentFinalAction')));
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('while the delete is in flight the button is not tappable again',
        (tester) async {
      await tester.pumpWidget(harness(cleared, busy: {'agent1-baghdad'}));
      expect(finalButton(tester).onPressed, isNull);
    });
  });

  group('loading and failure', () {
    testWidgets('a first load shows a spinner, not an empty sheet',
        (tester) async {
      await tester.pumpWidget(harness(null, loading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      await tester.pumpWidget(harness(null, error: Exception('boom')));
      expect(find.byKey(const Key('deleteAgentRetry')), findsOneWidget);
    });
  });
}
