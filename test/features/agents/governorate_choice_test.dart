import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/agents/domain/governorate_choice.dart';

/// B-127: a sub agent covers exactly one governorate; a main agent may span
/// several. The server rejects a second one, so the form must not let an
/// operator build a payload that will bounce.
void main() {
  group('sub agent — single choice', () {
    test('picking a second governorate replaces the first', () {
      final result = resolveGovernorateChoice(
        current: {'BAGHDAD'},
        next: {'BAGHDAD', 'BASRA'},
        singleChoice: true,
      );
      expect(result, {'BASRA'}, reason: 'the tap must win, not the old value');
    });

    test('the FIRST pick is kept', () {
      expect(
        resolveGovernorateChoice(
            current: {}, next: {'NAJAF'}, singleChoice: true),
        {'NAJAF'},
      );
    });

    test('deselecting to empty is allowed', () {
      // The form still requires one before save; clearing mid-edit is normal.
      expect(
        resolveGovernorateChoice(
            current: {'BAGHDAD'}, next: {}, singleChoice: true),
        isEmpty,
      );
    });

    test('a pre-existing multi-governorate row collapses to one on first edit', () {
      // Legacy data (B-136 deletes these on UAT, but the form must not choke).
      final result = resolveGovernorateChoice(
        current: {'BAGHDAD', 'BASRA'},
        next: {'BAGHDAD', 'BASRA', 'ERBIL'},
        singleChoice: true,
      );
      expect(result, {'ERBIL'});
    });

    test('with no discernible addition it still yields exactly one', () {
      // Defensive: if `next` somehow shares nothing with `current`, the result
      // must still be a single value rather than an invalid payload.
      final result = resolveGovernorateChoice(
        current: {'BAGHDAD', 'BASRA'},
        next: {'BAGHDAD', 'BASRA'},
        singleChoice: true,
      );
      expect(result.length, 1);
    });
  });

  group('main agent — untouched', () {
    test('may hold several governorates', () {
      // The load-bearing exemption: a Main Agent operates across regions.
      final result = resolveGovernorateChoice(
        current: {'BAGHDAD'},
        next: {'BAGHDAD', 'BASRA', 'NINEVEH'},
        singleChoice: false,
      );
      expect(result, {'BAGHDAD', 'BASRA', 'NINEVEH'});
    });

    test('selection passes through unchanged', () {
      expect(
        resolveGovernorateChoice(
            current: {'A', 'B'}, next: {'C'}, singleChoice: false),
        {'C'},
      );
    });
  });
}
