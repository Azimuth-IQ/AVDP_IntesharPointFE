import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';

/// Pricing + virtual-balance reads/writes. The backend enforces the capability +
/// own-entity / direct-child rules; this layer is a thin client.
class PricingRepository {
  final ApiClient _api;
  PricingRepository(this._api);

  Future<PricingCatalog> catalog({String? entityId}) async {
    final r = await _api.get(Endpoints.pricingCatalog,
        params: {if (entityId != null && entityId.isNotEmpty) 'entityId': entityId});
    return _api.unwrap(r, (d) => PricingCatalog.fromJson(d as Map<String, dynamic>));
  }

  /// Sets the entity's price for a category, optionally scoped to a [governorate]
  /// (the voucher subcategory). Null/'' governorate = the SKU-wide base price.
  Future<void> setPrice({required String entityId, required String sku, required num price, String? governorate}) async {
    await _api.post(Endpoints.pricingSet, data: {
      'entityId': entityId,
      'sku': sku,
      'price': price,
      'governorate': ?governorate,
    });
  }

  /// B-059: apply the same price list to one or more agents (Excel re-upload).
  /// [entityIds] empty = the caller itself. Each row = {sku, governorate?, price}.
  /// Returns per-agent applied counts.
  Future<Map<String, int>> setBulk({
    required List<Map<String, dynamic>> prices,
    List<String> entityIds = const [],
  }) async {
    final r = await _api.post(Endpoints.pricingSetBulk, data: {
      if (entityIds.isNotEmpty) 'entityIds': entityIds,
      'prices': prices,
    });
    return _api.unwrap(r, (d) {
      final m = (d as Map).cast<String, dynamic>();
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    });
  }

  Future<AgentBalance> balance({String? entityId}) async {
    final r = await _api.get(Endpoints.balance,
        params: {if (entityId != null && entityId.isNotEmpty) 'entityId': entityId});
    return _api.unwrap(r, (d) => AgentBalance.fromJson(d as Map<String, dynamic>));
  }

  Future<void> grant({required String destId, required num amount}) async {
    await _api.post(Endpoints.balanceGrant, data: {'destId': destId, 'amount': amount});
  }

  /// B-034: takes UNSPENT credit back from a direct child — the inverse a grant
  /// never had. The server refuses more than the child still holds and says how
  /// much that is, since money already turned into stock or sales cannot return.
  Future<void> reclaim({required String destId, required num amount}) async {
    await _api.post(Endpoints.balanceReclaim, data: {'destId': destId, 'amount': amount});
  }

  /// B-060 HQ oversight: Main Agents with unpriced stock.
  Future<List<UnpricedAgent>> unpricedAgents() async {
    final r = await _api.get(Endpoints.pricingUnpricedAgents);
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => UnpricedAgent.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<GrantRow>> grants({String? entityId}) async {
    final r = await _api.get(Endpoints.balanceGrants,
        params: {if (entityId != null && entityId.isNotEmpty) 'entityId': entityId});
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => GrantRow.fromJson(e as Map<String, dynamic>)).toList();
    });
  }
}
