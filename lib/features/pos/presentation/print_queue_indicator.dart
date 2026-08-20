import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/printing/print_queue.dart';

/// UX-91: what the print queue is actually doing, in one line.
///
/// [PrintQueue] serializes every receipt and retries a failed write up to three
/// times with backoff. Both facts were invisible: a job on attempt 2 of 3 looked
/// exactly like a hung printer, and a bulk run with four receipts still waiting
/// looked exactly like one slow receipt. On the ROVOO SPP transport — which is
/// known to accept bytes and print nothing — that guesswork is expensive.
///
/// Renders nothing when the queue is idle or on a plain first attempt with
/// nothing behind it, so the ordinary one-receipt sale is unchanged.
class PrintQueueLine extends ConsumerWidget {
  const PrintQueueLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.read(printQueueProvider);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<PrintQueueStatus>(
      valueListenable: queue.status,
      builder: (context, s, _) {
        final text = printQueueLineText(s, ar: ar);
        if (text == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: s.isRetrying ? IntesharColors.warn : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: s.isRetrying ? IntesharColors.warn : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The sentence for a queue state, or null when there is nothing worth saying.
///
/// Pure, so the wording can be checked without a printer or a widget tree.
String? printQueueLineText(PrintQueueStatus s, {required bool ar}) {
  if (s.pending == 0) return null;
  final parts = <String>[];
  if (s.isRetrying) {
    parts.add(ar
        ? 'إعادة محاولة الطباعة ${s.attempt}/${s.maxAttempts}'
        : 'Retrying print ${s.attempt}/${s.maxAttempts}');
  }
  if (s.waiting > 0) {
    parts.add(ar
        ? 'في الانتظار: ${s.waiting}'
        : '${s.waiting} waiting');
  }
  if (parts.isEmpty) return null;
  return parts.join(ar ? ' · ' : ' · ');
}
