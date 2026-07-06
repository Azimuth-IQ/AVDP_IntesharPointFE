import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/reports/domain/report_rows.dart';

/// Read-only aggregator for the Reports section.
///
/// Phase 1 (prices / stock / detailed) reuses the existing pricing-catalog and
/// inventory-summary endpoints — no new backend. Later phases add the
/// `/api/reports/*` aggregations (balances, transfers, sales, uploads); those
/// methods land here so every report screen has a single data entry point.
/// See `Docs/REPORTING-MODULE-BUILD-MAP.md`.
class ReportsRepository {
  final ApiClient _api;
  ReportsRepository(this._api);

  /// #7 Card prices + #9 Detailed: per (category × governorate) base/agent/effective
  /// price + available count + line value + the `inventoryWorth` grand total.
  /// `entityId` null/'' = the caller's own entity (backend resolves).
  Future<PricingCatalog> priceCatalog({String? entityId}) =>
      PricingRepository(_api).catalog(entityId: entityId);

  /// #8 Card stock: per-SKU counts by status, broken down per governorate bucket.
  Future<List<SkuSummary>> stockSummary({required String entityId}) =>
      ProductRepository(_api).summaryByEntity(entityId);

  /// #1 POS balances (type STORE) / #2 agent balances (type AGENT1/AGENT2): a roster
  /// of the caller's subtree with each entity's virtual balance + the "who" columns.
  /// `rootId` null/'' = the caller's own entity (backend scopes to the subtree).
  Future<List<BalanceRosterRow>> balancesRoster({String? rootId, String? type}) async {
    final r = await _api.get(Endpoints.reportsBalances, params: {
      if (rootId != null && rootId.isNotEmpty) 'rootId': rootId,
      if (type != null && type.isNotEmpty) 'type': type,
    });
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => BalanceRosterRow.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  /// #3 financial transfers: balance grants in the subtree within [from,to]
  /// (ISO yyyy-MM-dd), newest-first, with a per-dest running credit total.
  Future<List<TransferRow>> transfers({String? rootId, String? from, String? to}) async {
    final r = await _api.get(Endpoints.reportsTransfers, params: {
      if (rootId != null && rootId.isNotEmpty) 'rootId': rootId,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    });
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => TransferRow.fromJson(e as Map<String, dynamic>)).toList();
    });
  }
}
