import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/print_queue.dart';

void main() {
  test('runs jobs strictly one at a time, in submission order', () async {
    final events = <String>[];
    var active = 0;
    final q = PrintQueue((bytes) async {
      active++;
      expect(active, 1, reason: 'only one print may run at a time');
      events.add('start-${bytes.first}');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      events.add('end-${bytes.first}');
      active--;
    });

    // Fire three without awaiting between them.
    final f1 = q.enqueue([1]);
    final f2 = q.enqueue([2]);
    final f3 = q.enqueue([3]);
    await Future.wait([f1, f2, f3]);

    expect(events, [
      'start-1', 'end-1',
      'start-2', 'end-2',
      'start-3', 'end-3',
    ]);
  });

  test('retries a transient failure and then succeeds', () async {
    var calls = 0;
    final q = PrintQueue((bytes) async {
      calls++;
      if (calls < 3) throw Exception('printer busy');
    });
    await q.enqueue([1]); // should not throw
    expect(calls, 3);
  });

  test('throws after exhausting attempts', () async {
    var calls = 0;
    final q = PrintQueue((bytes) async {
      calls++;
      throw Exception('disconnected');
    }, maxAttempts: 2);
    await expectLater(q.enqueue([1]), throwsException);
    expect(calls, 2);
  });

  test('a failed job does not stall the queue', () async {
    var second = false;
    final q = PrintQueue((bytes) async {
      if (bytes.first == 1) throw Exception('fail');
      if (bytes.first == 2) second = true;
    }, maxAttempts: 1);

    final f1 = q.enqueue([1]);
    final f2 = q.enqueue([2]);
    await expectLater(f1, throwsException);
    await f2; // must still run
    expect(second, isTrue);
  });
}
