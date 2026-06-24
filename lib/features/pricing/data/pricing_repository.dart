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

  Future<void> setPrice({required String entityId, required String sku, required num price}) async {
    await _api.post(Endpoints.pricingSet, data: {'entityId': entityId, 'sku': sku, 'price': price});
  }

  Future<AgentBalance> balance({String? entityId}) async {
    final r = await _api.get(Endpoints.balance,
        params: {if (entityId != null && entityId.isNotEmpty) 'entityId': entityId});
    return _api.unwrap(r, (d) => AgentBalance.fromJson(d as Map<String, dynamic>));
  }

  Future<void> grant({required String destId, required num amount}) async {
    await _api.post(Endpoints.balanceGrant, data: {'destId': destId, 'amount': amount});
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
