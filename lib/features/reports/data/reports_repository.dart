import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';

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
}
