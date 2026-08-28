import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/presentation/batch_add_page.dart';

/// UX-11 — what a bulk action leaves behind when it half-succeeds.
///
/// The bulk levers on this screen are Pause and Withdraw, i.e. a supplier
/// RECALL, and a recall is never one batch. Half-success is therefore the normal
/// case worth designing for, not the edge: some batches will already be paused,
/// already withdrawn, or owned by someone who has since been deleted.
///
/// None of this is visible by clicking through with everything working, which is
/// why it is pinned here.
void main() {
  test('a clean run selects nothing and leaves selection mode', () {
    final o = bulkOutcome(attempted: 10, failedIds: {});
    expect(o.clean, isTrue);
    expect(o.succeeded, 10);
    expect(o.stillSelected, isEmpty);
    expect(o.keepSelecting, isFalse,
        reason: 'nothing left to act on — staying in selection mode is friction');
  });

  test('the rows that failed stay selected, and only those', () {
    // The point of the rule: "which three failed?" is answered by the list
    // still showing them ticked, and retrying is one more tap.
    final o = bulkOutcome(attempted: 10, failedIds: {'b3', 'b7', 'b9'});
    expect(o.stillSelected, {'b3', 'b7', 'b9'});
    expect(o.keepSelecting, isTrue);
    expect(o.clean, isFalse);
  });

  test('it reports what SUCCEEDED, not just the failures', () {
    // A recall that moved 7 of 10 has changed the world. A message that counts
    // only failures reads as "nothing happened" — which is the reading that
    // gets the whole recall run a second time.
    final o = bulkOutcome(attempted: 10, failedIds: {'b3', 'b7', 'b9'});
    expect(o.succeeded, 7);
  });

  test('a total failure still reports honestly and keeps everything', () {
    final ids = {'a', 'b', 'c'};
    final o = bulkOutcome(attempted: 3, failedIds: ids);
    expect(o.succeeded, 0);
    expect(o.stillSelected, ids);
    expect(o.keepSelecting, isTrue);
  });

  test('the returned selection is a copy, not the caller\'s set', () {
    // The caller clears `_selected` and re-adds from this, so aliasing the same
    // Set would clear the very thing being restored.
    final failed = {'b1'};
    final o = bulkOutcome(attempted: 2, failedIds: failed);
    failed.clear();
    expect(o.stillSelected, {'b1'},
        reason: 'outcome must not alias the caller\'s mutable set');
  });

  test('a single-row run behaves like any other', () {
    expect(bulkOutcome(attempted: 1, failedIds: {}).succeeded, 1);
    final one = bulkOutcome(attempted: 1, failedIds: {'x'});
    expect(one.succeeded, 0);
    expect(one.keepSelecting, isTrue);
  });
}
