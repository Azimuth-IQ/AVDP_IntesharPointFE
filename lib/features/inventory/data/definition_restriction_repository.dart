import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';

/// B-081: an account's voucher-definition visibility — which SKUs are hidden
/// directly on it (editable) vs inherited from an ancestor (locked).
class DefinitionVisibility {
  /// SKUs hidden directly on this entity (toggleable in the editor).
  final Set<String> restricted;

  /// SKUs hidden by an ancestor — they apply here too but are managed higher up.
  final Set<String> inherited;

  const DefinitionVisibility({required this.restricted, required this.inherited});
}

/// HQ-only client for the per-agent product-visibility hide-list.
class DefinitionRestrictionRepository {
  final ApiClient _api;
  DefinitionRestrictionRepository(this._api);

  Future<DefinitionVisibility> visibility(String entityId) async {
    final r = await _api.get(Endpoints.definitionRestrictions,
        params: {'entityId': entityId});
    return _api.unwrap(r, (d) {
      final m = (d as Map).cast<String, dynamic>();
      Set<String> list(String k) =>
          ((m[k] as List?) ?? const []).map((e) => e.toString()).toSet();
      return DefinitionVisibility(
        restricted: list('restrictedSkus'),
        inherited: list('inheritedRestrictedSkus'),
      );
    });
  }

  /// Hide ([restricted] = true) or show a single SKU for [entityId] (idempotent).
  Future<void> setRestricted({
    required String sku,
    required String entityId,
    required bool restricted,
  }) async {
    await _api.post(Endpoints.definitionRestrict,
        data: {'sku': sku, 'entityId': entityId, 'restricted': restricted});
  }
}
