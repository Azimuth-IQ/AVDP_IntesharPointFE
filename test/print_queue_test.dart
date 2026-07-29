import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/print_job.dart';
import 'package:inteshar/core/printing/print_queue.dart';

void main() {
  test('runs jobs strictly one at a time, in submission order', () async {
    final events = <String>[];
    var active = 0;
    final q = PrintQueue((job) async {
      active++;
      expect(active, 1, reason: 'only one print may run at a time');
      events.add('start-${job.bytes.first}');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      events.add('end-${job.bytes.first}');
      active--;
    });

    // Fire three without awaiting between them.
    final f1 = q.enqueue(const PrintJob.escPos([1]));
    final f2 = q.enqueue(const PrintJob.escPos([2]));
    final f3 = q.enqueue(const PrintJob.escPos([3]));
    await Future.wait([f1, f2, f3]);

    expect(events, [
      'start-1', 'end-1',
      'start-2', 'end-2',
      'start-3', 'end-3',
    ]);
  });

  test('retries a transient failure and then succeeds', () async {
    var calls = 0;
    final q = PrintQueue((job) async {
      calls++;
      if (calls < 3) throw Exception('printer busy');
    });
    await q.enqueue(const PrintJob.escPos([1])); // should not throw
    expect(calls, 3);
  });

  test('throws after exhausting attempts', () async {
    var calls = 0;
    final q = PrintQueue((job) async {
      calls++;
      throw Exception('disconnected');
    }, maxAttempts: 2);
    await expectLater(q.enqueue(const PrintJob.escPos([1])), throwsException);
    expect(calls, 2);
  });

  test('a failed job does not stall the queue', () async {
    var second = false;
    final q = PrintQueue((job) async {
      if (job.bytes.first == 1) throw Exception('fail');
      if (job.bytes.first == 2) second = true;
    }, maxAttempts: 1);

    final f1 = q.enqueue(const PrintJob.escPos([1]));
    final f2 = q.enqueue(const PrintJob.escPos([2]));
    await expectLater(f1, throwsException);
    await f2; // must still run
    expect(second, isTrue);
  });

  /// CR-06: a retry must resend the SAME bytes. The queue holds one immutable
  /// job, so a transient failure cannot cause a second, differently-built
  /// receipt to reach the paper.
  test('a retry resends the identical byte stream', () async {
    final seen = <List<int>>[];
    var calls = 0;
    final q = PrintQueue((job) async {
      seen.add(job.bytes);
      calls++;
      if (calls < 3) throw Exception('printer busy');
    });
    await q.enqueue(const PrintJob.escPos([27, 64, 65, 66]));
    expect(seen.length, 3);
    expect(seen[1], seen[0]);
    expect(seen[2], seen[0]);
  });
}
