import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/pricing/domain/price_filter.dart';
import 'package:inteshar/features/pricing/domain/price_sheet.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';

/// B-117: the pricing screen filtered its list inside `build` while the Excel
/// export read the whole catalog. Filtering to Baghdad and pressing Export still
/// produced every governorate of every company, so the file had to be
/// re-filtered in Excel to find the rows already on screen.
///
/// These assert the SHEET — the rows that actually get written — not the code
/// that assembles them.
void main() {
  CategoryPriceRow regional({
    String sku = 'ASC-5000',
    String name = 'Asiacell 5000',
    String company = 'Asiacell',
    bool priced = true,
  }) =>
      CategoryPriceRow(
        sku: sku,
        name: name,
        companyName: company,
        officialPrice: 5000,
        agentPrice: 5200,
        priced: priced,
        governorates: const [
          GovPriceRow(governorate: 'BAGHDAD', officialPrice: 5000, agentPrice: 5100),
          GovPriceRow(governorate: 'BASRA', officialPrice: 5000, agentPrice: 5300),
        ],
      );

  CategoryPriceRow skuWide({
    String sku = 'ZN-10000',
    String company = 'Zain',
    bool priced = true,
  }) =>
      CategoryPriceRow(
        sku: sku,
        name: 'Zain 10000',
        companyName: company,
        officialPrice: 10000,
        agentPrice: priced ? 10500 : null,
        priced: priced,
        governorates: const [],
      );

  List<List<String>> sheet(List<CategoryPriceRow> rows, PriceFilter f) =>
      buildPriceSheetRows(
        rows: rows,
        filter: f,
        locale: 'en',
        allGovernoratesLabel: 'All governorates',
        fmt: (n) => n.toString(),
      );

  group('the exported sheet follows the filters on screen', () {
    test('unfiltered still exports everything, every region', () {
      final rows = sheet([regional(), skuWide()], PriceFilter.none);
      expect(rows.length, 3); // 2 regions + 1 SKU-wide
      expect(rows.map((r) => r[2]),
          containsAll(['Baghdad', 'Basra', 'All governorates']));
    });

    test('BAGHDAD exports the Baghdad line and NOT Basra', () {
      // The reported bug, stated as a test.
      final rows = sheet([regional()], const PriceFilter(governorate: 'BAGHDAD'));
      expect(rows.length, 1);
      expect(rows.single[2], 'Baghdad');
      expect(rows.single[4], '5100', reason: 'the Baghdad price, not the SKU-wide one');
      expect(rows.toString(), isNot(contains('Basra')));
    });

    test('a company filter drops the other company entirely', () {
      final rows = sheet([regional(), skuWide()], const PriceFilter(company: 'Zain'));
      expect(rows.length, 1);
      expect(rows.single[0], 'ZN-10000');
    });

    test('company AND governorate compose', () {
      final rows = sheet(
        [regional(), skuWide()],
        const PriceFilter(company: 'Asiacell', governorate: 'BASRA'),
      );
      expect(rows.length, 1);
      expect(rows.single[2], 'Basra');
    });

    test('a governorate filter excludes untagged SKUs — exactly as the list does', () {
      // Judgement call, pinned so it cannot drift silently: a governorate filter
      // means "SKUs priced FOR that region", so region-free categories drop out.
      // That is the shipped list behaviour (B-114) and the sheet now matches it.
      // The alternative — treating untagged SKUs as present in every region —
      // would put the same row in all 18 sheets, where editing it in the Baghdad
      // file would silently change the price everywhere.
      expect(sheet([skuWide()], const PriceFilter(governorate: 'BAGHDAD')), isEmpty);
    });

    test('unfiltered, an untagged SKU is labelled "all governorates"', () {
      // Never narrowed to one region on the way out: re-importing that would
      // write a region-only override and strip the price from the rest.
      final rows = sheet([skuWide()], PriceFilter.none);
      expect(rows.single[2], 'All governorates');
    });

    test('the unpriced pill scopes the sheet too', () {
      final rows = sheet(
        [regional(priced: true), skuWide(priced: false)],
        const PriceFilter(unpricedOnly: true),
      );
      expect(rows.length, 1);
      expect(rows.single[0], 'ZN-10000');
    });

    test('a search term scopes the sheet', () {
      final rows = sheet([regional(), skuWide()], const PriceFilter(query: 'zain'));
      expect(rows.single[0], 'ZN-10000');
    });

    test('a filter matching nothing yields an empty sheet, not the whole catalog', () {
      expect(sheet([regional()], const PriceFilter(company: 'Korek')), isEmpty);
    });
  });

  group('the filename records the scope', () {
    test('unfiltered keeps the plain name', () {
      expect(priceSheetFileName(PriceFilter.none), 'inteshar-prices');
    });

    test('company and governorate both appear', () {
      final n = priceSheetFileName(
          const PriceFilter(company: 'Asiacell', governorate: 'BAGHDAD'));
      expect(n, contains('asiacell'));
      expect(n, contains('baghdad'));
    });
  });

  group('the upload obeys the same scope', () {
    final catalog = [regional(), skuWide()];

    test('an unfiltered screen rejects nothing', () {
      expect(
        PriceFilter.none.excludesUpload(
            sku: 'ANYTHING', governorate: 'BASRA', knownRows: catalog),
        isFalse,
      );
    });

    test('filtering Baghdad excludes a Basra row', () {
      expect(
        const PriceFilter(governorate: 'BAGHDAD').excludesUpload(
            sku: 'ASC-5000', governorate: 'BASRA', knownRows: catalog),
        isTrue,
      );
    });

    test('filtering Baghdad keeps the Baghdad row', () {
      expect(
        const PriceFilter(governorate: 'BAGHDAD').excludesUpload(
            sku: 'ASC-5000', governorate: 'BAGHDAD', knownRows: catalog),
        isFalse,
      );
    });

    test('a company filter excludes another company\'s SKU', () {
      expect(
        const PriceFilter(company: 'Zain').excludesUpload(
            sku: 'ASC-5000', governorate: '', knownRows: catalog),
        isTrue,
      );
    });

    test('a SKU the catalog does not know is excluded while filtering', () {
      // It cannot be shown to be in scope, and applying it blind would write a
      // price the operator could not see on screen.
      expect(
        const PriceFilter(company: 'Zain').excludesUpload(
            sku: 'UNKNOWN-1', governorate: '', knownRows: catalog),
        isTrue,
      );
    });
  });

  test('the list and the sheet always agree on what is in scope', () {
    // The original defect was two copies of "in scope". This pins them together:
    // every row the sheet contains must be a row the list would show.
    const f = PriceFilter(company: 'Asiacell', governorate: 'BAGHDAD');
    final catalog = [regional(), skuWide()];
    final visibleSkus = f.apply(catalog).map((r) => r.sku).toSet();
    final sheetSkus = sheet(catalog, f).map((r) => r[0]).toSet();
    expect(sheetSkus, visibleSkus);
  });
}
