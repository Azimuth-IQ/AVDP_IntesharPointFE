import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';

class DefinitionRepository {
  final ApiClient _api;
  DefinitionRepository(this._api);

  Future<ProductDefinition> create(ProductDefinition def) async {
    final response =
        await _api.post(Endpoints.definitionCreate, data: def.toJson());
    return _api.unwrap(
        response, (d) => ProductDefinition.fromJson(d as Map<String, dynamic>));
  }

  Future<List<ProductDefinition>> readAll() async {
    final response = await _api.get(Endpoints.definitionReadAll);
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => ProductDefinition.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<ProductDefinition> read(String id) async {
    final response =
        await _api.get(Endpoints.definitionRead, params: {'id': id});
    return _api.unwrap(
        response, (d) => ProductDefinition.fromJson(d as Map<String, dynamic>));
  }

  Future<ProductDefinition> update(ProductDefinition def) async {
    final response =
        await _api.put(Endpoints.definitionUpdate, data: def.toJson());
    return _api.unwrap(
        response, (d) => ProductDefinition.fromJson(d as Map<String, dynamic>));
  }

  /// Delete a category. The backend refuses (409) when vouchers still reference the
  /// SKU; pass [force] to override (admin cleanup) after the user confirms.
  Future<void> delete(String id, {bool force = false}) async {
    await _api.delete(Endpoints.definitionDelete,
        params: {'id': id, if (force) 'force': true});
  }
}
