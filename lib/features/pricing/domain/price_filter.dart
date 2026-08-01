import 'package:inteshar/features/pricing/domain/pricing_models.dart';

/// What the pricing screen currently considers "in scope".
///
/// B-117: the list filtered inline inside `build` while `_exportXlsx` read the
/// whole catalog, so filtering to Baghdad and pressing Export still wrote every
/// governorate of every company. Two copies of the same idea drift; this is the
/// single one, and the list, the export and the upload all ask it.
class PriceFilter {
  /// Free text over category name, SKU and company — what the card shows.
  final String query;

  /// Exact company name, '' = every company.
  final String company;

  /// Exact governorate code, '' = every governorate.
  final String governorate;

  /// Only categories still sitting on the official default (B-080).
  final bool unpricedOnly;

  const PriceFilter({
    this.query = '',
    this.company = '',
    this.governorate = '',
    this.unpricedOnly = false,
  });

  static const none = PriceFilter();

  bool get isActive =>
      query.trim().isNotEmpty ||
      company.isNotEmpty ||
      governorate.isNotEmpty ||
      unpricedOnly;

  bool matches(CategoryPriceRow r) {
    if (unpricedOnly && r.priced) return false;
    if (company.isNotEmpty && r.companyName != company) return false;
    if (governorate.isNotEmpty &&
        !r.governorates.any((g) => g.governorate == governorate)) {
      return false;
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.name.toLowerCase().contains(q) ||
        r.sku.toLowerCase().contains(q) ||
        r.companyName.toLowerCase().contains(q);
  }

  List<CategoryPriceRow> apply(List<CategoryPriceRow> rows) =>
      rows.where(matches).toList();

  /// The governorate lines of [r] that are in scope.
  ///
  /// With a governorate selected, a regional SKU contributes ONLY that region —
  /// exporting "Baghdad" must not hand back all eighteen, which is the whole
  /// point of having filtered.
  List<GovPriceRow> govLinesFor(CategoryPriceRow r) {
    if (governorate.isEmpty) return r.governorates;
    return r.governorates.where((g) => g.governorate == governorate).toList();
  }

  /// True when a parsed upload row targets something this filter excludes.
  ///
  /// [knownRows] is the catalog, so an unknown SKU is judged only when a filter
  /// could actually exclude it — an unfiltered screen never rejects anything.
  bool excludesUpload({
    required String sku,
    required String governorate,
    required List<CategoryPriceRow> knownRows,
  }) {
    if (!isActive) return false;
    if (this.governorate.isNotEmpty &&
        governorate.isNotEmpty &&
        governorate != this.governorate) {
      return true;
    }
    CategoryPriceRow? row;
    for (final r in knownRows) {
      if (r.sku == sku) {
        row = r;
        break;
      }
    }
    // A SKU the catalog does not contain cannot be shown to be in scope.
    if (row == null) return true;
    return !matches(row);
  }
}
