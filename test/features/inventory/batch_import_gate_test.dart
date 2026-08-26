import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/presentation/batch_add_page.dart';

/// The gate in front of a batch import.
///
/// Two customer-visible incidents came from this rule, not from the import: the
/// sale scope defaulting to "answered" (C-08, stock sellable in all 18
/// governorates), and the warehouse defaulting to the first agent in a truncated
/// list (UX-14, thousands of codes to whoever sorted first). Both were a required
/// question that did not look required, so these tests assert on what must BLOCK
/// as hard as on what must pass.
void main() {
  /// Everything answered, region-free format — the baseline that must be clean.
  List<BatchImportRequirement> missing({
    bool hasCategory = true,
    bool hasWarehouse = true,
    bool hasVouchers = true,
    bool regionLockedFormat = false,
    bool? regionLockedScope,
    bool hasGovernorate = false,
  }) =>
      batchImportMissing(
        hasCategory: hasCategory,
        hasWarehouse: hasWarehouse,
        hasVouchers: hasVouchers,
        regionLockedFormat: regionLockedFormat,
        regionLockedScope: regionLockedScope,
        hasGovernorate: hasGovernorate,
      );

  test('a fully answered region-free import is not blocked', () {
    expect(missing(), isEmpty);
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
        missing(hasWarehouse: false, regionLockedFormat: true,
            regionLockedScope: true, hasGovernorate: true),
        [BatchImportRequirement.warehouse],
        reason: 'a chosen-by-default warehouse is the same bug as a '
            'chosen-by-default sale scope',
      );
    });
  });

  group('the sale scope (C-08)', () {
    test('an unanswered scope blocks a region-locked import', () {
      expect(missing(regionLockedFormat: true, regionLockedScope: null),
          contains(BatchImportRequirement.saleScope));
    });

    test('deliberately region-free is an ANSWER, not a gap', () {
      // The whole point of C-08: sell-everywhere stays available, it just has to
      // be chosen. Blocking it here would push operators back to the default.
      expect(missing(regionLockedFormat: true, regionLockedScope: false),
          isEmpty);
    });

    test('one governorate requires naming which one', () {
      expect(
        missing(regionLockedFormat: true, regionLockedScope: true,
            hasGovernorate: false),
        contains(BatchImportRequirement.governorate),
      );
      expect(
        missing(regionLockedFormat: true, regionLockedScope: true,
            hasGovernorate: true),
        isEmpty,
      );
    });

    test('a region-FREE format never asks about scope or governorate', () {
      // Asking would be noise, and worse, would train the operator to dismiss
      // the question on the format where it matters.
      final m = missing(regionLockedFormat: false, regionLockedScope: null,
          hasGovernorate: false);
      expect(m, isNot(contains(BatchImportRequirement.saleScope)));
      expect(m, isNot(contains(BatchImportRequirement.governorate)));
    });
  });

  group('reporting', () {
    test('names every unanswered question at once, not one at a time', () {
      // The hint line lists what is missing; surfacing them one per attempt
      // turns one upload into four round trips.
      expect(
        missing(hasCategory: false, hasWarehouse: false, hasVouchers: false,
            regionLockedFormat: true, regionLockedScope: null),
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
        final m = missing(regionLockedFormat: true, regionLockedScope: scope);
        expect(
          m.contains(BatchImportRequirement.saleScope) &&
              m.contains(BatchImportRequirement.governorate),
          isFalse,
        );
      }
    });
  });
}
