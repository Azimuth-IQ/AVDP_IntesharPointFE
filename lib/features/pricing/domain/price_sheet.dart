import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/pricing/domain/price_filter.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';

/// PROD-038 (client, 28 Nov 2026): pricing is per agent, never per governorate — no category is
/// "regional" any more, whatever an older server still sends. Kept as a function so every caller
/// reads the one rule.
bool isRegionalRow(CategoryPriceRow row) => false;

/// Builds the price sheet's data cells for [filter]'s scope.
///
/// B-117: this used to live inside the export callback and read the whole
/// catalog, so the sheet ignored the filters on screen. Pulled out so the
/// exported artifact itself can be asserted, rather than the code that makes it.
///
/// UX-42: the two price columns are real `num`s, so the operator can total,
/// sort and formula over them in Excel — and the upload still parses them,
/// because a numeric cell reads back as its plain digits. Identity columns
/// (sku, name, governorate) stay `String`.
///
/// Columns are `sku, name, governorate, official, your` — the same shape the
/// upload parses, so an exported sheet always re-imports.
List<List<Object>> buildPriceSheetCells({
  required List<CategoryPriceRow> rows,
  required PriceFilter filter,
  required String locale,
  required String allGovernoratesLabel,
}) {
  final out = <List<Object>>[];
  for (final row in filter.apply(rows)) {
    if (isRegionalRow(row)) {
      for (final g in filter.govLinesFor(row)) {
        out.add([
          row.sku,
          row.name,
          governorateLabel(g.governorate, locale),
          g.officialPrice,
          g.agentPrice ?? g.officialPrice,
        ]);
      }
    } else {
      // A SKU-wide category has no region of its own, so a governorate filter
      // excludes it upstream in [PriceFilter.matches] — same as the list on
      // screen, which is the point. It only reaches here when no governorate is
      // selected, and it must stay marked "all governorates": narrowing it to
      // one region on the way out would re-import as a region-only override and
      // silently strip the price from every other governorate.
      out.add([
        row.sku,
        row.name,
        allGovernoratesLabel,
        row.officialPrice,
        row.agentPrice ?? row.officialPrice,
      ]);
    }
  }
  return out;
}

/// The same sheet as text, for callers (and tests) that want the rendered
/// strings. [fmt] formats the two price columns.
List<List<String>> buildPriceSheetRows({
  required List<CategoryPriceRow> rows,
  required PriceFilter filter,
  required String locale,
  required String allGovernoratesLabel,
  required String Function(num) fmt,
}) =>
    [
      for (final r in buildPriceSheetCells(
          rows: rows,
          filter: filter,
          locale: locale,
          allGovernoratesLabel: allGovernoratesLabel))
        [for (final c in r) c is num ? fmt(c) : c as String],
    ];

/// Filename stem carrying the scope, so two exports taken minutes apart under
/// different filters don't land in Downloads as indistinguishable files.
String priceSheetFileName(PriceFilter filter, {String locale = 'en'}) {
  final parts = <String>['inteshar-prices'];
  if (filter.company.isNotEmpty) parts.add(_slug(filter.company));
  if (filter.governorate.isNotEmpty) {
    parts.add(_slug(governorateLabel(filter.governorate, 'en')));
  }
  if (filter.unpricedOnly) parts.add('unpriced');
  return parts.join('-');
}

String _slug(String s) {
  final cleaned = s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9؀-ۿ]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'filtered' : cleaned;
}

/// PROD-038: how many of [prices] (`{sku, price}` maps, as sent to set-bulk) are under their
/// category's floor in [rows] — Asiacell / Zain only; every other category is unbound.
int belowFloorCount(List<CategoryPriceRow> rows, List<Map<String, dynamic>> prices) {
  final floors = <String, num>{
    for (final r in rows)
      if (r.floor != null) r.sku: r.floor!,
  };
  var n = 0;
  for (final p in prices) {
    final f = floors[p['sku']];
    final v = p['price'];
    if (f != null && v is num && v < f) n++;
  }
  return n;
}

/// PROD-038: one price per category from an uploaded sheet. An older sheet lists a category once
/// per governorate: the row without a governorate wins, else the first; the governorate is
/// dropped. Order follows the sheet. [merged] = rows that folded into another.
({List<Map<String, dynamic>> rows, int merged}) onePricePerCategory(List<Map<String, dynamic>> parsed) {
  final bySku = <String, Map<String, dynamic>>{};
  final general = <String>{};
  var merged = 0;
  for (final p in parsed) {
    final sku = (p['sku'] as String?)?.trim() ?? '';
    if (sku.isEmpty) continue;
    final isGeneral = ((p['governorate'] as String?) ?? '').isEmpty;
    if (!bySku.containsKey(sku)) {
      bySku[sku] = {'sku': sku, 'governorate': '', 'price': p['price']};
      if (isGeneral) general.add(sku);
      continue;
    }
    merged++;
    if (isGeneral && !general.contains(sku)) {
      bySku[sku] = {'sku': sku, 'governorate': '', 'price': p['price']};
      general.add(sku);
    }
  }
  return (rows: bySku.values.toList(), merged: merged);
}
