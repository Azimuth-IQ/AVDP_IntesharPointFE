import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/stores/presentation/stores_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// Renders [StoreForm] under a minimal MaterialApp (LTR/English). Only the form
/// chrome is exercised — `_save` (the sole network path) is never triggered, so
/// no API/provider stubbing is needed.
Future<void> _pumpForm(WidgetTester tester, Widget form) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: form,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Entity _agent(String id, String name, EntityType type) =>
    Entity(id: id, meta: EntityMeta(name: name), type: type);

void main() {
  testWidgets('HQ create shows the parent-agent picker defaulting to the first option', (tester) async {
    final agents = [
      _agent('a1', 'Baghdad', EntityType.AGENT1),
      _agent('a2', 'Basra', EntityType.AGENT2),
    ];

    await _pumpForm(tester, StoreForm(parentId: 'a1', parentOptions: agents));

    // The picker label and the default (first) agent's display value are present.
    expect(find.text('Parent agent'), findsWidgets);
    expect(find.text('Baghdad (Main Agent)'), findsOneWidget);
    // The rest of the create form still renders.
    expect(find.text('Shop name (shown on the card)'), findsWidgets);
  });

  testWidgets('Agent create (no parentOptions) hides the parent-agent picker', (tester) async {
    await _pumpForm(tester, const StoreForm(parentId: 'self-agent'));

    expect(find.text('Parent agent'), findsNothing);
    // The create form is still rendered (login phone field is create-only).
    expect(find.text('Login phone (username)'), findsWidgets);
  });
}
