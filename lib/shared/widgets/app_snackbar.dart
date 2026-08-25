import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// The app's toasts (UX-82).
///
/// The 118 hand-rolled `SnackBar`s took Flutter's 4-second default, none of
/// them offered a close icon and none offered an action. On a POS the operator
/// is looking at the printer or at the customer, not at the screen — a 4s
/// Arabic toast naming a *failed money operation* is routinely missed, and
/// there is no log to recover it from. So:
///
/// - **errors last [kErrorSnackDuration] (9s)** and always carry a close icon,
///   so the message survives a glance away and can be dismissed early;
/// - **successes stay short** — a confirmation that lingers is just noise;
/// - the current toast is **replaced, not queued**: with 9s errors a queue
///   means the second failure shows up nine seconds after it happened.
///
/// [showError] takes the raw error object and runs it through [friendlyError],
/// so no call site has to remember not to print a `DioException`.

/// Error toasts are long on purpose — see the file comment.
const Duration kErrorSnackDuration = Duration(seconds: 9);

/// Confirmations are short on purpose.
const Duration kOkSnackDuration = Duration(seconds: 3);

/// Red toast for a failure. [error] may be a `String` or any thrown object.
///
/// Pass [onAction] to offer a one-tap recovery (retry the request, reopen the
/// sheet); it defaults its label to "إعادة المحاولة" / "Retry".
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showError(
  BuildContext context,
  Object error, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = kErrorSnackDuration,
}) {
  final ar = Localizations.localeOf(context).languageCode == 'ar';
  final cs = Theme.of(context).colorScheme;
  return _show(
    context,
    message: _messageFor(context, error),
    background: cs.error,
    foreground: cs.onError,
    icon: Icons.error_outline,
    duration: duration,
    closeIcon: true,
    actionLabel: onAction == null
        ? null
        : (actionLabel ?? (ar ? 'إعادة المحاولة' : 'Retry')),
    onAction: onAction,
  );
}

/// Ink toast with a green check — an action landed.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showOk(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = kOkSnackDuration,
}) {
  final cs = Theme.of(context).colorScheme;
  return _show(
    context,
    message: message,
    background: cs.onSurface,
    foreground: cs.surface,
    icon: Icons.check_circle_outline,
    // UX-124/128: was the raw `IntesharColors.sage` constant, which does not
    // track dark mode — in dark the toast background flips to a light ink and
    // the green check dropped to ~3:1 on it. The semantic tone plus the
    // background-aware correction in [_show] handles both modes.
    iconColor: context.status.success,
    duration: duration,
    closeIcon: false,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// Neutral ink toast — a statement of fact, no verdict ("Copied", "Queued").
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showInfo(
  BuildContext context,
  String message, {
  IconData icon = Icons.info_outline,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = kOkSnackDuration,
}) {
  final cs = Theme.of(context).colorScheme;
  return _show(
    context,
    message: message,
    background: cs.onSurface,
    foreground: cs.surface,
    icon: icon,
    duration: duration,
    closeIcon: false,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// Localized, non-technical text for [error]. Falls back to `toString()` only
/// when localizations are unavailable (a bare test pump).
String _messageFor(BuildContext context, Object error) {
  if (error is String) return error;
  final l = AppLocalizations.of(context);
  return l == null ? error.toString() : friendlyErrorL(error, l);
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _show(
  BuildContext context, {
  required String message,
  required Color background,
  required Color foreground,
  required IconData icon,
  required Duration duration,
  required bool closeIcon,
  Color? iconColor,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  // Replace rather than queue — a 9s error behind another 9s error arrives
  // after the operator has already moved on.
  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      duration: duration,
      backgroundColor: background,
      showCloseIcon: closeIcon,
      closeIconColor: foreground,
      behavior: SnackBarBehavior.floating,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A semantic tone is resolved against the PAGE surface, but a toast is
          // painted on ink — so re-correct it against the background it will
          // actually sit on before using it.
          Icon(
            icon,
            size: 20,
            color: iconColor == null
                ? foreground
                : contrastAdjusted(iconColor, background),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: IntesharText.bodyLg(
                color: foreground,
                w: IntesharWeight.semibold,
              ),
            ),
          ),
        ],
      ),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: foreground,
              onPressed: onAction,
            )
          : null,
    ),
  );
}
