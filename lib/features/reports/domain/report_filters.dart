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

/// The SKUs the stock report actually SHOWS for [gov] ('' = every governorate):
/// the ones holding sellable stock in that region, in the grid's own order.
///
/// UX-43: the grid filtered by governorate while the export read the whole
/// summary, so a sheet taken under a Baghdad filter silently carried all
/// eighteen. One projection, asked by both.
List<SkuSummary> visibleStock(List<SkuSummary> summary, String gov) {
  final shown = summary
      .where((k) => govCount(k, gov, (g) => g.available, k.available) > 0)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return shown;
}

/// One exported stock line — a (SKU, governorate) bucket.
class StockLine {
  final String sku;
  final String name;

  /// '' = region-free stock (the grid's "No region").
  final String governorate;
  final int available;
  final int total;
  final int used;
  const StockLine({
    required this.sku,
    required this.name,
    required this.governorate,
    required this.available,
    required this.total,
    required this.used,
  });
}

/// The stock export's rows, over exactly the SKUs [visibleStock] renders.
///
/// With a governorate picked, each SKU contributes that ONE region — the same
/// number the card shows. Unfiltered, a SKU is broken into its regional buckets
/// (plus a region-free remainder when the buckets don't account for all of it),
/// so the sheet still sums back to the card on screen.
List<StockLine> stockExportLines(List<SkuSummary> summary, String gov) {
  final out = <StockLine>[];
  for (final k in visibleStock(summary, gov)) {
    if (gov.isNotEmpty) {
      out.add(StockLine(
        sku: k.sku,
        name: k.name,
        governorate: gov,
        available: govCount(k, gov, (g) => g.available, k.available),
        total: govCount(k, gov, (g) => g.total, k.total),
        used: govCount(k, gov, (g) => g.printed, k.printed),
      ));
      continue;
    }
    if (k.governorates.isEmpty) {
      out.add(StockLine(
        sku: k.sku,
        name: k.name,
        governorate: '',
        available: k.available,
        total: k.total,
        used: k.printed,
      ));
      continue;
    }
    for (final b in k.governorates) {
      out.add(StockLine(
        sku: k.sku,
        name: k.name,
        governorate: b.governorate,
        available: b.available,
        total: b.total,
        used: b.printed,
      ));
    }
    // Untagged stock lives OUTSIDE the buckets, so without this the sheet would
    // total less than the card it came from.
    final rest = StockLine(
      sku: k.sku,
      name: k.name,
      governorate: '',
      available: k.available - k.governorates.fold<int>(0, (a, b) => a + b.available),
      total: k.total - k.governorates.fold<int>(0, (a, b) => a + b.total),
      used: k.printed - k.governorates.fold<int>(0, (a, b) => a + b.printed),
    );
    if (rest.available > 0 || rest.total > 0 || rest.used > 0) {
      if (!k.governorates.any((b) => b.governorate.isEmpty)) out.add(rest);
    }
  }
  return out;
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
