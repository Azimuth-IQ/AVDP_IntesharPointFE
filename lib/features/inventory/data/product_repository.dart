import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/domain/product.dart';

class ProductRepository {
  final ApiClient _api;
  ProductRepository(this._api);

  Future<Product> create(Product product) async {
    final response =
        await _api.post(Endpoints.productCreate, data: product.toJson());
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
  }

  Future<List<Product>> readByEntity(String entityId) async {
    final response = await _api
        .get(Endpoints.productReadByEntity, params: {'entityId': entityId});
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Product> read(String id) async {
    final response =
        await _api.get(Endpoints.productRead, params: {'id': id});
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
  }

  Future<List<Product>> readAll() async {
    final response = await _api.get(Endpoints.productReadAll);
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Product> update(Product product) async {
    final response =
        await _api.put(Endpoints.productUpdate, data: product.toJson());
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
  }

  Future<void> delete(String id) async {
    await _api.delete(Endpoints.productDelete, params: {'id': id});
  }
}
