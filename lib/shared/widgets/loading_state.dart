import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';

/// A wait that tells you it is still alive (UX-80).
///
/// The API client allows 10s to connect + 15s to receive and retries three
/// times, so a request against a dead backend can burn ~46 seconds. For all of
/// it, ~25 screens showed a bare `Center(CircularProgressIndicator())`: no
/// text, no elapsed time, no sign anything is being retried. It is
/// indistinguishable from a hang, so people force-quit or — worse, on a money
/// screen — tap submit again.
///
/// This escalates instead:
///
/// | elapsed | what it says |
/// |---|---|
/// | 0–4s   | the spinner, plus [message] if given |
/// | 4–12s  | "Still loading…" |
/// | 12s+   | "The connection is slow — retrying…", the elapsed seconds, and [onCancel] if given |
///
/// Drop-in for the bare spinner: `const LoadingState()`.
class LoadingState extends StatefulWidget {
  /// What is being fetched, shown from the first frame ("Loading vouchers…").
  final String? message;

  /// Offered from the third stage on. Wire it to whatever gets the user out —
  /// popping the sheet, or re-running the request.
  final VoidCallback? onCancel;
  final String? cancelLabel;

  /// Inline variant for a small slot (a card body, a list footer): smaller
  /// spinner, no vertical padding, text on one line.
  final bool compact;

  const LoadingState({
    super.key,
    this.message,
    this.onCancel,
    this.cancelLabel,
    this.compact = false,
  });

  @override
  State<LoadingState> createState() => _LoadingStateState();
}

/// Seconds after which the wait admits it is taking a while.
const int kLoadingSlowAfter = 4;

/// Seconds after which it admits the connection may be bad and offers a way out.
const int kLoadingStuckAfter = 12;

class _LoadingStateState extends State<LoadingState> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      // Stop counting at two minutes — past that the number stops being
      // information and the widget should not keep rebuilding forever.
      if (_seconds >= 120) {
        t.cancel();
        return;
      }
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Escalating copy for the current elapsed time, or null in the first stage.
  String? _status(bool ar) {
    if (_seconds >= kLoadingStuckAfter) {
      return ar
          ? 'الاتصال بطيء — تتم إعادة المحاولة…'
          : 'The connection is slow — retrying…';
    }
    if (_seconds >= kLoadingSlowAfter) {
      return ar ? 'ما زال التحميل جارياً…' : 'Still loading…';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final status = _status(ar);
    final stuck = _seconds >= kLoadingStuckAfter;

    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.tones.brandOnSurface,
            ),
          ),
          if (widget.message != null || status != null) ...[
            const SizedBox(width: IntesharSpacing.sm2),
            Flexible(
              child: Text(
                status ?? widget.message!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IntesharText.body(
                    color: cs.onSurfaceVariant, w: IntesharWeight.semibold),
              ),
            ),
          ],
        ],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: context.tones.brandOnSurface,
                ),
              ),
              if (widget.message != null) ...[
                const SizedBox(height: IntesharSpacing.lg),
                Text(
                  widget.message!,
                  textAlign: TextAlign.center,
                  style: IntesharText.bodyLg(
                      color: cs.onSurface, w: IntesharWeight.bold),
                ),
              ],
              if (status != null) ...[
                SizedBox(height: widget.message == null ? 16 : 6),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: IntesharText.body(
                      color: cs.onSurfaceVariant, w: IntesharWeight.semibold),
                ),
              ],
              if (stuck) ...[
                const SizedBox(height: 6),
                // The elapsed count is the proof that it has not frozen.
                Text(
                  ar ? 'منذ $_seconds ثانية' : '${_seconds}s elapsed',
                  style: IntesharType.mono(IntesharScale.body,
                      color: cs.onSurfaceVariant),
                ),
                if (widget.onCancel != null) ...[
                  const SizedBox(height: IntesharSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(widget.cancelLabel ?? (ar ? 'إلغاء' : 'Cancel')),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
