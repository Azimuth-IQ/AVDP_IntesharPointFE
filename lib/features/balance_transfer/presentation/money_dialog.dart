import 'package:flutter/material.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// UX-26 — the shell every money dialog on the transfers page is presented in.
///
/// The transfer dialog is a form ~550-600dp tall (recipient segment, search, a
/// 260dp recipient list, the amount field and a four-line before→after readout).
/// It was an `AlertDialog` with `scrollable` never set, so on a 360dp phone with
/// the keyboard open it had roughly 320dp to render that in — and Flutter drops
/// what does not fit off the BOTTOM. The parts lost were the amount field and
/// the before→after readout: exactly the figures the arm-then-commit safety
/// (B-040) assumes the operator has read before the second press.
///
/// Agents are the population most likely to be on a phone, so:
///
/// * `ScreenSize.mobile` gets a **full-screen route** — the whole form scrolls,
///   the keyboard shrinks the body rather than clipping it, and the commit
///   button sits in a bottom bar that the keyboard pushes up instead of hiding.
///   The actions are stacked full-width there because the armed label spells out
///   the amount and the recipient, which does not fit a phone-width button row.
/// * Everything else keeps the familiar centred dialog, now with
///   `scrollable: true` so a short window (a laptop with the keyboard tray, a
///   split view) scrolls instead of clipping.
///
/// The `SizedBox(width:)` the callers pass is deliberately kept: `SizedBox`
/// clamps to the incoming constraints rather than overflowing, so it is a
/// desktop-width preference, not the overflow.
Future<bool?> showMoneyDialog({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext ctx, StateSetter setD) body,
  required List<Widget> Function(BuildContext ctx, StateSetter setD) actions,
  double width = 460,
}) {
  final fullScreen = context.isMobile;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final content = body(ctx, setD);
        final acts = actions(ctx, setD);
        if (!fullScreen) {
          return AlertDialog(
            title: Text(title),
            // Scrolls instead of clipping when the window is short.
            scrollable: true,
            content: SizedBox(width: width, child: content),
            actions: acts,
          );
        }
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              // UX-150: the only way out of a full-screen money dialog, unnamed.
              leading: IconButton(
                tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx, false),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: content,
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The primary (commit) action leads and takes the full
                    // width, so the armed "send <amount> to <name>" label has
                    // room to wrap rather than being clipped mid-figure.
                    SizedBox(width: double.infinity, child: acts.last),
                    for (var i = acts.length - 2; i >= 0; i--) ...[
                      const SizedBox(height: 4),
                      SizedBox(width: double.infinity, child: acts[i]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
