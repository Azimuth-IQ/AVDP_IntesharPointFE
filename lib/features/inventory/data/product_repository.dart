import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';

class ProductRepository {
  final ApiClient _api;
  ProductRepository(this._api);

  /// Per-SKU rollup (counts per status + price) for an entity — one small,
  /// indexed aggregation that replaces downloading every voucher to group them.
  Future<List<SkuSummary>> summaryByEntity(String entityId) async {
    final response = await _api
        .get(Endpoints.productSummaryByEntity, params: {'entityId': entityId});
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => SkuSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// One page of a single SKU's vouchers for an entity (lazy expand).
  Future<List<Product>> readByEntityAndSku(
    String entityId,
    String sku, {
    int page = 0,
    int size = 50,
  }) async {
    final response = await _api.get(Endpoints.productReadByEntityAndSku, params: {
      'entityId': entityId,
      'sku': sku,
      'page': page,
      'size': size,
    });
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => Product.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<Product> create(Product product) async {
    final response =
        await _api.post(Endpoints.productCreate, data: product.toJson());
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
  }

  /// Bulk voucher import (HQ "الرفع"). Sends the parsed batch in chunks of [chunk]
  /// to `POST /api/inventory/product/batch` (the backend encrypts each PIN, dedups
  /// by serial, and bulk-inserts), aggregating the per-chunk results. [governorate]
  /// region-locks NEW/SEW batches; null leaves OTHER vouchers region-free.
  Future<BatchImportResult> batchImport({
    required String definitionId,
    required String ownerId,
    String? governorate,
    required String type,
    required List<ParsedVoucher> vouchers,
    int chunk = 1000,
    void Function(int done, int total)? onProgress,
  }) async {
    var agg = const BatchImportResult();
    for (var i = 0; i < vouchers.length; i += chunk) {
      final end = (i + chunk) < vouchers.length ? (i + chunk) : vouchers.length;
      final slice = vouchers.sublist(i, end);
      final body = <String, dynamic>{
        'definitionId': definitionId,
        'ownerId': ownerId,
        'type': type,
        if (governorate != null && governorate.isNotEmpty)
          'governorate': governorate,
        'vouchers': slice
            .map((v) => {
                  'serialNumber': v.serial,
                  'pin': v.pin,
                  if (v.expiry != null) 'expiryDate': v.expiry,
                  if (v.label != null) 'label': v.label,
                })
            .toList(),
      };
      final response = await _api.post(Endpoints.productBatch, data: body);
      final res = _api.unwrap(
          response, (d) => BatchImportResult.fromJson(d as Map<String, dynamic>));
      agg = agg.merge(res);
      onProgress?.call(end, vouchers.length);
    }
    return agg;
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

  /// The single channel that yields a decrypted PIN: flips the product to
  /// SENT_FOR_PRINTING (audited) and returns it with the PIN decrypted. Backend
  /// authorizes that the caller's entity is the product's current owner.
  Future<Product> sendForPrinting(String id) async {
    final response =
        await _api.post(Endpoints.productSendForPrinting, params: {'id': id});
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
  }

  /// Resolves an in-flight print: PRINTED when [printed] is true, else
  /// FAILED_PRINTING. Never returns a PIN.
  Future<void> confirmPrint(String id, {required bool printed}) async {
    await _api.post(Endpoints.productConfirmPrint,
        params: {'id': id, 'printed': printed});
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
