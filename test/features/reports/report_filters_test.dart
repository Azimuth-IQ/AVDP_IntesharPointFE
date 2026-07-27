import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/reports/domain/report_filters.dart';
import 'package:inteshar/features/reports/domain/report_rows.dart';

/// These decide which stock counts and which shops a user sees. A filter that
/// quietly counts the wrong bucket is exactly the bug an on-screen eyeball never
/// catches — the number looks plausible either way.
void main() {
  GovBucket bucket(String gov, {int total = 0, int available = 0, int printed = 0}) =>
      GovBucket(governorate: gov, total: total, available: available, printed: printed);

  SkuSummary sku({
    int total = 0,
    int available = 0,
    int printed = 0,
    List<GovBucket> govs = const [],
  }) =>
      SkuSummary(
        sku: 'SC1',
        name: 'Asia 5',
        total: total,
        available: available,
        printed: printed,
        governorates: govs,
      );

  group('govCount', () {
    final s = sku(
      total: 100,
      available: 70,
      printed: 30,
      govs: [
        bucket('BAGHDAD', total: 60, available: 40, printed: 20),
        bucket('BASRA', total: 30, available: 25, printed: 5),
      ],
    );

    test('no filter returns the SKU-wide count, not the sum of buckets', () {
      // The buckets total 90, the SKU 100 — the difference is untagged stock,
      // which lives outside the bucket list. Re-summing would silently lose it.
      expect(govCount(s, '', (g) => g.total, s.total), 100);
      expect(govCount(s, '', (g) => g.available, s.available), 70);
    });

    test('a filter sums only the matching bucket', () {
      expect(govCount(s, 'BAGHDAD', (g) => g.available, s.available), 40);
      expect(govCount(s, 'BASRA', (g) => g.available, s.available), 25);
      expect(govCount(s, 'BAGHDAD', (g) => g.printed, s.printed), 20);
    });

    test('a governorate with no stock is 0, not the SKU-wide fallback', () {
      expect(govCount(s, 'ERBIL', (g) => g.available, s.available), 0,
          reason: 'falling back here would report another region\'s stock as local');
    });

    test('a SKU with no buckets still reports its whole count when unfiltered', () {
      final flat = sku(total: 12, available: 12);
      expect(govCount(flat, '', (g) => g.available, flat.available), 12);
      expect(govCount(flat, 'BAGHDAD', (g) => g.available, flat.available), 0);
    });
  });

  group('rosterMatches', () {
    final row = BalanceRosterRow(
      entityId: 'st1',
      name: 'Saad Shop',
      ownerName: 'Ahmed Ali',
      userPhone: '07701234567',
      governorate: 'BAGHDAD',
      address: 'Karrada street',
      tier: 'STORE',
      mainAgentName: 'Baghdad Main',
      subAgentName: 'Russafa Sub',
    );
    String label(String g) => g == 'BAGHDAD' ? 'بغداد' : g;

    test('an empty query matches everything', () {
      expect(rosterMatches(row, '', govLabel: label), isTrue);
      expect(rosterMatches(row, '   ', govLabel: label), isTrue);
    });

    test('matches every field the card actually shows', () {
      for (final q in ['saad', 'ahmed', '0770123', 'karrada', 'baghdad main', 'russafa']) {
        expect(rosterMatches(row, q, govLabel: label), isTrue, reason: 'should match "$q"');
      }
    });

    test('matches the LOCALISED governorate, not the stored code', () {
      // An operator searches what they can see on the card.
      expect(rosterMatches(row, 'بغداد', govLabel: label), isTrue);
    });

    test('is case-insensitive and matches mid-string', () {
      expect(rosterMatches(row, 'SHOP', govLabel: label), isTrue);
      expect(rosterMatches(row, 'hmed', govLabel: label), isTrue);
    });

    test('rejects a genuine non-match', () {
      expect(rosterMatches(row, 'zzz', govLabel: label), isFalse);
    });

    test('an untagged governorate does not crash the label lookup', () {
      final untagged = BalanceRosterRow(entityId: 'x', name: 'No Region', governorate: '');
      expect(rosterMatches(untagged, 'region', govLabel: (_) => throw StateError('called')),
          isTrue,
          reason: 'an empty governorate must not be resolved at all');
    });
  });
}
