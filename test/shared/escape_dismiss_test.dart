import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/confirm_dialog.dart';

/// UX-12 — Escape has to be a way OUT.
///
/// The framework maps Escape to `DismissIntent` app-wide, and `ModalRoute`'s
/// handler for it is gated on **`barrierDismissible`** — a per-call-site choice
/// that is ours, not Flutter's. So "Escape closes dialogs" is not something we
/// get for free forever; it is something one `barrierDismissible: false` takes
/// away, and the app already has five of those.
///
/// [showConfirm] is the app's single confirmation dialog (UX-129) and every
/// destructive flow in the product routes through it, so it is the one worth
/// pinning: Escape must close it, and closing it must mean **no**.
void main() {
  /// Opens a confirm from a live route and hands back the pending answer.
  Future<Future<bool>> open(
    WidgetTester tester, {
    bool destructive = false,
  }) async {
    late Future<bool> answer;
    await tester.pumpWidget(MaterialApp(
      theme: buildBrandThemes().light,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => answer = showConfirm(
              context,
              title: 'Delete agent?',
              body: 'This cannot be undone.',
              destructive: destructive,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete agent?'), findsOneWidget);
    return answer;
  }

  testWidgets('Escape closes the confirm dialog', (tester) async {
    await open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Delete agent?'), findsNothing,
        reason: 'the only way out was hunting for Cancel with a mouse');
  });

  testWidgets('and Escape answers NO, never yes', (tester) async {
    // The half-fix that would be worse than no fix: a dialog that closes on
    // Escape but resolves as if the confirm button was pressed would delete an
    // agent because someone reached for the key that means "get me out".
    final answer = await open(tester, destructive: true);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // Checked BEFORE the await: a dialog that ignored Escape leaves `answer`
    // pending forever, and a hung test reports nothing useful.
    expect(find.text('Delete agent?'), findsNothing);
    expect(await answer, isFalse);
  });
}
