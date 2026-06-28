import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/printing/bluetooth_service.dart';

/// Sends raw ESC/POS bytes to the connected printer (Sunmi inner or Bluetooth).
typedef RawSender = Future<void> Function(List<int> bytes);

/// Serializes ESC/POS print jobs so rapid or concurrent prints never interleave
/// bytes on the printer channel (the BLE path writes in 20-byte chunks — two
/// overlapping sends would corrupt the receipt). One job prints at a time, FIFO;
/// transient failures are retried with backoff; a failed job never stalls the queue.
class PrintQueue {
  final RawSender _send;
  final int maxAttempts;
  PrintQueue(this._send, {this.maxAttempts = 3});

  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Number of jobs queued or in flight.
  int get pending => _pending;

  /// Enqueue [bytes] for printing. Returns a future that completes when THIS job
  /// has printed, or throws after [maxAttempts] failed tries. Jobs run strictly
  /// one at a time, in submission order.
  Future<void> enqueue(List<int> bytes, {int? maxAttempts}) {
    _pending++;
    final attempts = maxAttempts ?? this.maxAttempts;
    final job = _tail.then((_) => _runWithRetry(bytes, attempts));
    // Keep the chain alive regardless of this job's outcome so one failed print
    // doesn't block every subsequent print.
    _tail = job.then((_) {}, onError: (_) {});
    return job.whenComplete(() => _pending--);
  }

  Future<void> _runWithRetry(List<int> bytes, int attempts) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _send(bytes);
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

/// The app-wide serialized print queue, wrapping the printer service's raw send.
final printQueueProvider = Provider<PrintQueue>((ref) {
  final printer = ref.read(bluetoothServiceProvider.notifier);
  return PrintQueue((bytes) => printer.send(bytes));
});
