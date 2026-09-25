import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/presentation/batch_add_page.dart';

/// The gate in front of a batch import.
///
/// Two customer-visible incidents came from this rule, not from the import: the
/// sale scope defaulting to "answered" (C-08, stock sellable in all 18
/// governorates), and the warehouse defaulting to the first agent in a truncated
/// list (UX-14, thousands of codes to whoever sorted first). A third followed on
/// 2026-09-24: the scope was asked only for the NEW format, so the OTHER format
/// shipped `governorate: null` and could not be region-locked at all. All three
/// were a required question that did not look required, so these tests assert on
/// what must BLOCK as hard as on what must pass.
void main() {
  /// Defaults leave the sale scope UNANSWERED — that is now a blocking gap for
  /// every file format, so each passing case has to answer it explicitly.
  List<BatchImportRequirement> missing({
    bool hasCategory = true,
    bool hasWarehouse = true,
    bool hasVouchers = true,
    bool? regionLockedScope,
    bool hasGovernorate = false,
  }) =>
      batchImportMissing(
        hasCategory: hasCategory,
        hasWarehouse: hasWarehouse,
        hasVouchers: hasVouchers,
        regionLockedScope: regionLockedScope,
        hasGovernorate: hasGovernorate,
      );

  test('a fully answered sell-everywhere import is not blocked', () {
    expect(missing(regionLockedScope: false), isEmpty);
  });

  group('the warehouse (UX-14)', () {
    test('blocks the import when nobody has been chosen', () {
      expect(missing(hasWarehouse: false),
          contains(BatchImportRequirement.warehouse));
    });

    test('is required even when everything else is perfect', () {
      // The regression shape: a default made this unreachable, so the import
      // sailed through with a warehouse the operator never looked at.
      expect(
        missing(hasWarehouse: false, regionLockedScope: true,
            hasGovernorate: true),
        [BatchImportRequirement.warehouse],
        reason: 'a chosen-by-default warehouse is the same bug as a '
            'chosen-by-default sale scope',
      );
    });
  });

  group('the sale scope (C-08)', () {
    test('an unanswered scope blocks the import', () {
      expect(missing(regionLockedScope: null),
          contains(BatchImportRequirement.saleScope));
    });

    test('deliberately region-free is an ANSWER, not a gap', () {
      // The whole point of C-08: sell-everywhere stays available, it just has to
      // be chosen. Blocking it here would push operators back to the default.
      expect(missing(regionLockedScope: false), isEmpty);
    });

    test('one governorate requires naming which one', () {
      expect(
        missing(regionLockedScope: true, hasGovernorate: false),
        contains(BatchImportRequirement.governorate),
      );
      expect(
        missing(regionLockedScope: true, hasGovernorate: true),
        isEmpty,
      );
    });

    test('the scope is asked regardless of the file format (2026-09-24)', () {
      // The rule deliberately takes NO format argument any more. It used to skip
      // the question for the OTHER format, which is how 25 PALY-10 cards went up
      // sellable in every governorate: the picker was never drawn and the upload
      // hard-coded `governorate: null`. A file layout says which columns to
      // parse; it must never decide who may sell the cards.
      expect(missing(regionLockedScope: null),
          contains(BatchImportRequirement.saleScope));
      expect(missing(regionLockedScope: true, hasGovernorate: false),
          contains(BatchImportRequirement.governorate));
      expect(missing(regionLockedScope: true, hasGovernorate: true), isEmpty);
    });
  });

  group('reporting', () {
    test('names every unanswered question at once, not one at a time', () {
      // The hint line lists what is missing; surfacing them one per attempt
      // turns one upload into four round trips.
      expect(
        missing(hasCategory: false, hasWarehouse: false, hasVouchers: false,
            regionLockedScope: null),
        [
          BatchImportRequirement.category,
          BatchImportRequirement.warehouse,
          BatchImportRequirement.vouchers,
          BatchImportRequirement.saleScope,
        ],
      );
    });

    test('a file that parsed to nothing blocks the import', () {
      expect(missing(hasVouchers: false),
          contains(BatchImportRequirement.vouchers));
    });

    test('scope and governorate are never both asked for at once', () {
      // They are the same decision at two depths; listing both reads as two
      // separate failures for one unanswered question.
      for (final scope in <bool?>[null, true, false]) {
        final m = missing(regionLockedScope: scope);
        expect(
          m.contains(BatchImportRequirement.saleScope) &&
              m.contains(BatchImportRequirement.governorate),
          isFalse,
        );
      }
    });
  });
}
