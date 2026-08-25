import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// Removing a user from this sheet deletes a login, and the deletion is what
/// the operator is really committing to when they press Save. These assert the
/// commitment is legible and refusable — on the callback that actually reaches
/// the server, never on the sheet's private list.
void main() {
  const admin = EntityUser(id: 'u1', phone: '07700000001', role: UserRole.ADMIN);
  const second =
      EntityUser(id: 'u2', phone: '07700000002', role: UserRole.ADMIN);

  const entity = Entity(
    id: 'a2-rusafa',
    meta: EntityMeta(name: 'Rusafa Sub'),
    type: EntityType.AGENT2,
    users: [admin, second],
  );

  /// Captures what the sheet asks the caller to persist. Null while it has
  /// asked for nothing — which is the assertion that matters most here.
  late List<EntityUser>? saved;

  Widget harness() {
    saved = null;
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
        body: ManageUsersSheet(
          entity: entity,
          onSave: (users) async => saved = users,
          onResetPassword: (_, _) async {},
          onResetTotp: (_) async {},
        ),
      ),
    );
  }

  /// Opens the row menu and picks "Remove user" for [phone].
  Future<void> markForRemoval(WidgetTester tester, String phone) async {
    await tester.tap(find.byKey(Key('remove-$phone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove user').last);
    await tester.pumpAndSettle();
  }

  Future<void> pressSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save register').last);
    await tester.tap(find.text('Save register').last);
    await tester.pumpAndSettle();
  }

  testWidgets('a marked user stays visible, struck through, with a way back',
      (tester) async {
    await tester.pumpWidget(harness());
    await markForRemoval(tester, '07700000002');

    // Still on screen: vanishing would read as "already deleted" when in fact
    // nothing has been written yet.
    expect(find.text('07700000002'), findsOneWidget);
    expect(find.text('Removing'), findsOneWidget);
    expect(find.byKey(const Key('undo-remove-07700000002')), findsOneWidget);
  });

  testWidgets('undo puts the user back and clears the mark', (tester) async {
    await tester.pumpWidget(harness());
    await markForRemoval(tester, '07700000002');
    await tester.tap(find.byKey(const Key('undo-remove-07700000002')));
    await tester.pumpAndSettle();

    expect(find.text('Removing'), findsNothing);
    await pressSave(tester);
    // Saved intact — undo has to reach the server call, not just the pixels.
    expect(saved!.map((u) => u.phone), containsAll(['07700000001', '07700000002']));
  });

  testWidgets('save names the user before archiving them', (tester) async {
    await tester.pumpWidget(harness());
    await markForRemoval(tester, '07700000002');
    await pressSave(tester);

    // UX-156: the account is retired and restorable, so the prompt must not
    // offer to delete it. Asserting the absence too, because a stale "Delete"
    // left anywhere here promises destruction the server no longer performs.
    expect(find.text('Archive user?'), findsOneWidget);
    expect(find.text('Delete user?'), findsNothing);
    // The phone appears in the dialog, so the operator can check it is the
    // account they meant.
    expect(find.text('07700000002'), findsWidgets);
    expect(saved, isNull, reason: 'nothing may be written before confirming');
  });

  testWidgets('cancelling the confirmation writes nothing at all',
      (tester) async {
    await tester.pumpWidget(harness());
    await markForRemoval(tester, '07700000002');
    await pressSave(tester);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(saved, isNull);
    // The mark survives, so a mis-tap on Cancel does not silently un-plan the
    // removal the operator still wants.
    expect(find.text('Removing'), findsOneWidget);
  });

  testWidgets('confirming saves the survivors only', (tester) async {
    await tester.pumpWidget(harness());
    await markForRemoval(tester, '07700000002');
    await pressSave(tester);
    await tester.tap(find.byKey(const Key('confirm-user-removal')));
    await tester.pumpAndSettle();

    expect(saved!.map((u) => u.phone), ['07700000001']);
  });

  group('the Arabic count in the confirmation title', () {
    test('uses the dual for two rather than a digit', () {
      expect(arArchiveUsersCount(1), 'أرشفة مستخدم');
      expect(arArchiveUsersCount(2), 'أرشفة مستخدمين');
      expect(arArchiveUsersCount(2), isNot(contains('2')));
    });

    test('counts 3-10 with the plural and 11+ with the singular', () {
      expect(arArchiveUsersCount(3), 'أرشفة 3 مستخدمين');
      expect(arArchiveUsersCount(10), 'أرشفة 10 مستخدمين');
      expect(arArchiveUsersCount(11), 'أرشفة 11 مستخدماً');
    });

    // UX-156 retired the verb حذف: the account is archived and restorable, not
    // destroyed. A confirmation that still says "delete" would promise
    // something the server no longer does.
    test('no longer promises deletion', () {
      for (final n in [1, 2, 3, 10, 11]) {
        expect(arArchiveUsersCount(n), isNot(contains('حذف')));
      }
    });
  });

  testWidgets('marking every user is refused without asking the server',
      (tester) async {
    await tester.pumpWidget(harness());
    await markForRemoval(tester, '07700000001');
    await markForRemoval(tester, '07700000002');
    await pressSave(tester);

    expect(saved, isNull);
    expect(find.text('Delete user?'), findsNothing,
        reason: 'the at-least-one rule should stop it before the confirmation');
  });
}
