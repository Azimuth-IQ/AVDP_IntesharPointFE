import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/printer_service.dart';

/// Sends one receipt to whichever transport is connected.
typedef JobSender = Future<void> Function(PrintJob job);

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

  /// Number of jobs queued or in flight.
  int get pending => _pending;

  /// Enqueue [job] for printing. Returns a future that completes when THIS job
  /// has printed, or throws after [maxAttempts] failed tries. Jobs run strictly
  /// one at a time, in submission order.
  Future<void> enqueue(PrintJob job, {int? maxAttempts}) {
    _pending++;
    final attempts = maxAttempts ?? this.maxAttempts;
    final queued = _tail.then((_) => _runWithRetry(job, attempts));
    // Keep the chain alive regardless of this job's outcome so one failed print
    // doesn't block every subsequent print.
    _tail = queued.then((_) {}, onError: (_) {});
    return queued.whenComplete(() => _pending--);
  }

  Future<void> _runWithRetry(PrintJob job, int attempts) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= attempts; attempt++) {
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
