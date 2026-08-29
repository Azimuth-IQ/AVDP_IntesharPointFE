import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/shared/widgets/multi_select.dart';

/// UX-11 — the selection state machine.
///
/// Every one of these asserts a value the machine RETURNS. None of them
/// re-derives the answer from the same rule the code uses; where a rule has two
/// plausible readings (does "select all" mean the filtered rows or every row?
/// does a run cover ticks the filter is hiding?) the test states which one was
/// chosen and would fail on the other.
void main() {
  group('ticking', () {
    test('toggling a row turns selection mode on by itself', () {
      // So a long-press can start a selection without a trip to the toolbar.
      final s = SelectionState.off.toggle('a');
      expect(s.active, isTrue);
      expect(s.ids, {'a'});
    });

    test('toggling the same row twice leaves nothing ticked but stays on', () {
      final s = SelectionState.off.toggle('a').toggle('a');
      expect(s.ids, isEmpty);
      expect(s.active, isTrue,
          reason: 'unticking the last row must not silently close the bar '
              'the operator is still working in');
    });

    test('leaving selection mode drops the ticks', () {
      // Otherwise re-entering later arrives pre-armed with a selection nobody
      // remembers making.
      final s = SelectionState.off.toggle('a').toggle('b').exit();
      expect(s.active, isFalse);
      expect(s.ids, isEmpty);
    });

    test('the ticked set cannot be mutated behind the state s back', () {
      final s = SelectionState.off.toggle('a');
      expect(() => s.ids.add('b'), throwsUnsupportedError);
    });
  });

  group('select all is bounded by what is on screen', () {
    test('it ticks the visible rows and no others', () {
      final s = SelectionState.off.enter().selectAll(['a', 'b']);
      expect(s.ids, {'a', 'b'});
    });

    test('it leaves ticks on rows the filter is hiding', () {
      // 'z' was ticked before the search narrowed. Select-all over the two rows
      // now showing must not quietly untick it — see `targetsIn`.
      final s = SelectionState.off.toggle('z').selectAll(['a', 'b']);
      expect(s.ids, {'a', 'b', 'z'});
    });

    test('clear-shown only unticks the visible rows', () {
      final s = SelectionState.off
          .toggle('z')
          .selectAll(['a', 'b']).deselectAll(['a', 'b']);
      expect(s.ids, {'z'});
    });

    test('one tap flips between select-shown and clear-shown', () {
      final all = SelectionState.off.enter().toggleAll(['a', 'b']);
      expect(all.ids, {'a', 'b'});
      expect(all.toggleAll(['a', 'b']).ids, isEmpty);
    });
  });

  group('the tri-state affordance', () {
    test('reads none / some / all against the visible rows', () {
      const visible = ['a', 'b'];
      expect(SelectionState.off.allStateFor(visible), SelectAllState.none);
      expect(SelectionState.off.toggle('a').allStateFor(visible),
          SelectAllState.some);
      expect(SelectionState.off.toggle('a').toggle('b').allStateFor(visible),
          SelectAllState.all);
    });

    test('an empty list is "none", never "all"', () {
      // Vacuously every visible row is ticked; rendering that as a full
      // checkbox over an empty list reads as a rendering bug.
      expect(SelectionState.off.enter().allStateFor(const []),
          SelectAllState.none);
    });

    test('ticks on hidden rows do not make the visible ones look ticked', () {
      expect(SelectionState.off.toggle('z').allStateFor(['a', 'b']),
          SelectAllState.none);
    });
  });

  group('targets', () {
    test('run in the order the list shows them', () {
      final s = SelectionState.off.enter().selectAll(['c', 'a', 'b']);
      expect(s.targetsIn(['c', 'a', 'b']), ['c', 'a', 'b']);
    });

    test('include ticks the filter is hiding, because the bar counts them', () {
      // The bar says "3 selected". A run that did the two on screen and dropped
      // the third would make the most load-bearing number in the mechanism lie.
      final s = SelectionState.off.toggle('z').selectAll(['a', 'b']);
      expect(s.count, 3);
      expect(s.targetsIn(['a', 'b']), ['a', 'b', 'z']);
    });

    test('never repeat a row that appears twice in the visible list', () {
      final s = SelectionState.off.toggle('a');
      expect(s.targetsIn(['a', 'a']), ['a']);
    });
  });

  group('surviving a reload', () {
    test('rows that no longer exist stop being counted', () {
      // Otherwise the bar says "2 selected" over one row and the next run posts
      // an id the server has never heard of.
      final s = SelectionState.off.toggle('a').toggle('gone').retain(['a', 'b']);
      expect(s.ids, {'a'});
      expect(s.active, isTrue);
    });
  });

  group('what a finished run leaves behind', () {
    test('a clean run closes the bar and unticks everything', () {
      final s = SelectionState.off
          .enter()
          .selectAll(['a', 'b'])
          .applyOutcome(bulkOutcome(attempted: 2, failedIds: {}));
      expect(s.active, isFalse);
      expect(s.ids, isEmpty);
    });

    test('a partial run keeps exactly the failures ticked, and stays open', () {
      final s = SelectionState.off
          .enter()
          .selectAll(['a', 'b', 'c'])
          .applyOutcome(bulkOutcome(attempted: 3, failedIds: {'b'}));
      expect(s.ids, {'b'},
          reason: 'the still-ticked rows ARE the record of what needs a retry');
      expect(s.active, isTrue);
      expect(s.count, 1);
    });
  });

  group('the type-the-count gate', () {
    test('an empty box never passes', () {
      // This is the reflex tap the gate exists to stop.
      expect(bulkConfirmMatches('', 40), isFalse);
      expect(bulkConfirmMatches('   ', 40), isFalse);
    });

    test('close is not good enough', () {
      expect(bulkConfirmMatches('4', 40), isFalse);
      expect(bulkConfirmMatches('400', 40), isFalse);
      expect(bulkConfirmMatches('41', 40), isFalse);
    });

    test('the exact count passes', () {
      expect(bulkConfirmMatches('40', 40), isTrue);
    });

    test('Arabic-Indic digits pass — this app is typed on an Arabic keyboard',
        () {
      expect(bulkConfirmMatches('٤٠', 40), isTrue);
      expect(bulkConfirmMatches('۴۰', 40), isTrue); // extended (Persian) forms
    });

    test('a count copied back with its thousands separator passes', () {
      // The app prints counts through NumberFormat('#,###'), so the number on
      // screen may well carry a comma the operator copies.
      expect(bulkConfirmMatches('1,000', 1000), isTrue);
      expect(bulkConfirmMatches(' 40 ', 40), isTrue);
    });

    test('letters alone never pass', () {
      expect(bulkConfirmMatches('forty', 40), isFalse);
      expect(bulkConfirmMatches('yes', 40), isFalse);
    });
  });
}
