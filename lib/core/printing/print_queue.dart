import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/printer_service.dart';

/// Sends one receipt to whichever transport is connected.
typedef JobSender = Future<void> Function(PrintJob job);

/// What the queue is doing right now, for the UI (UX-91).
///
/// A silent retry is indistinguishable from a hang: the operator sees a spinner
/// that has been spinning for four seconds and cannot tell whether the printer
/// is chewing through paper or the app is on attempt 2 of 3 after a failed
/// write. Both facts live here so a screen can say which.
@immutable
class PrintQueueStatus {
  /// Jobs queued or in flight.
  final int pending;

  /// Which attempt the job in flight is on (1 = first try). 0 when idle.
  final int attempt;

  /// How many attempts that job gets in total.
  final int maxAttempts;

  const PrintQueueStatus({
    this.pending = 0,
    this.attempt = 0,
    this.maxAttempts = 0,
  });

  /// True while a job is being re-sent after a failed write.
  bool get isRetrying => attempt > 1;

  /// Jobs waiting BEHIND the one currently printing.
  int get waiting => pending > 1 ? pending - 1 : 0;

  @override
  bool operator ==(Object other) =>
      other is PrintQueueStatus &&
      other.pending == pending &&
      other.attempt == attempt &&
      other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(pending, attempt, maxAttempts);
}

/// Serializes print jobs so rapid or concurrent prints never interleave on the
/// printer channel (the BLE path writes in 20-byte chunks and the SPP socket is
/// a single stream — two overlapping sends would corrupt the receipt). One job
/// prints at a time, FIFO; transient failures are retried with backoff; a failed
/// job never stalls the queue.
class PrintQueue {
  final JobSender _send;
  final int maxAttempts;
  PrintQueue(this._send, {this.maxAttempts = 3});

  Future<void> _tail = Future<void>.value();
  int _pending = 0;
  int _attempt = 0;
  int _attemptsForCurrent = 0;

  /// Number of jobs queued or in flight.
  int get pending => _pending;

  /// Live queue depth + retry state, for the UI. Never null; equal values do not
  /// notify, so a widget listening to it rebuilds only on a real change.
  final ValueNotifier<PrintQueueStatus> status =
      ValueNotifier<PrintQueueStatus>(const PrintQueueStatus());

  void _publish() {
    status.value = PrintQueueStatus(
      pending: _pending,
      attempt: _pending == 0 ? 0 : _attempt,
      maxAttempts: _pending == 0 ? 0 : _attemptsForCurrent,
    );
  }

  /// Enqueue [job] for printing. Returns a future that completes when THIS job
  /// has printed, or throws after [maxAttempts] failed tries. Jobs run strictly
  /// one at a time, in submission order.
  Future<void> enqueue(PrintJob job, {int? maxAttempts}) {
    final attempts = maxAttempts ?? this.maxAttempts;
    _pending++;
    if (_pending == 1) _attemptsForCurrent = attempts;
    _publish();
    final queued = _tail.then((_) => _runWithRetry(job, attempts));
    // Keep the chain alive regardless of this job's outcome so one failed print
    // doesn't block every subsequent print.
    _tail = queued.then((_) {}, onError: (_) {});
    return queued.whenComplete(() {
      _pending--;
      if (_pending == 0) _attempt = 0;
      _publish();
    });
  }

  Future<void> _runWithRetry(PrintJob job, int attempts) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      _attempt = attempt;
      _attemptsForCurrent = attempts;
      _publish();
      try {
        await _send(job);
        return;
      } catch (e) {
        lastErr = e;
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        }
      }
    }
    throw lastErr ?? Exception('Print failed');
  }
}

/// The app-wide serialized print queue, wrapping the printer service's send.
final printQueueProvider = Provider<PrintQueue>((ref) {
  final printer = ref.read(printerServiceProvider.notifier);
  return PrintQueue(printer.send);
});
