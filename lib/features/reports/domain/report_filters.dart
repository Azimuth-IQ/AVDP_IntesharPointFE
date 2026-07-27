import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/reports/domain/report_rows.dart';

/// Pure filter/rollup logic for the Reports screen.
///
/// Lifted out of the private report widgets so it is directly testable — these
/// decide which stock counts and which shops a user sees, and a filter that
/// quietly counts the wrong bucket is the kind of bug an on-screen eyeball never
/// catches.

/// Per-governorate slice of a SKU's counts. [gov] empty = every governorate, in
/// which case the SKU-wide [whole] is returned rather than re-summing buckets
/// (untagged stock lives outside the bucket list).
int govCount(
  SkuSummary sku,
  String gov,
  int Function(GovBucket) pick,
  int whole,
) {
  if (gov.isEmpty) return whole;
  return sku.governorates
      .where((g) => g.governorate == gov)
      .fold(0, (a, g) => a + pick(g));
}

/// Free-text match for the balance roster (B-102). Matches on any of the fields
/// the card actually displays — searching for something you can see and getting
/// nothing back is worse than no search at all.
///
/// [govLabel] resolves a governorate code to its localised name, so a user can
/// search "Baghdad"/"بغداد" rather than the stored code.
bool rosterMatches(
  BalanceRosterRow r,
  String query, {
  required String Function(String) govLabel,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final fields = <String>[
    r.name,
    r.ownerName,
    r.userPhone,
    r.address,
    r.mainAgentName,
    r.subAgentName,
    if (r.governorate.isNotEmpty) govLabel(r.governorate),
  ];
  return fields.any((f) => f.toLowerCase().contains(q));
}
