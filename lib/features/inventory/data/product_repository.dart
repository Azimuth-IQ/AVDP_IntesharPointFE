import 'dart:typed_data';

import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/domain/print_operation.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/inventory/domain/voucher_batch.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';

/// Enriched voucher-reveal payload: the consumed product (PIN decrypted), the
/// per-store sequential receipt number, and the resolved main-agent + company logo
/// URLs the POS prints on the receipt.
class RevealResult {
  final Product product;
  final int receiptNo;
  final String? agentLogoUrl;
  final String? companyLogoUrl;
  const RevealResult({
    required this.product,
    this.receiptNo = 0,
    this.agentLogoUrl,
    this.companyLogoUrl,
  });
}

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

  /// The single channel that yields a decrypted PIN: atomically marks the voucher
  /// used (PRINTED) and returns it with the PIN decrypted, PLUS the per-store receipt
  /// number and the main-agent + company logo URLs for the receipt. Backend authorizes
  /// that the caller's entity is the product's current owner.
  Future<RevealResult> sendForPrinting(String id) async {
    final response =
        await _api.post(Endpoints.productSendForPrinting, params: {'id': id});
    return _api.unwrap(response, (d) {
      final m = d as Map<String, dynamic>;
      return RevealResult(
        product: Product.fromJson(m['product'] as Map<String, dynamic>? ?? {}),
        receiptNo: (m['receiptNo'] as num?)?.toInt() ?? 0,
        agentLogoUrl: m['agentLogoUrl'] as String?,
        companyLogoUrl: m['companyLogoUrl'] as String?,
      );
    });
  }

  /// Print-operations (sales) for the inspection screen. HQ may pass [storeId] to
  /// scope to one store (omit for all); other roles are scoped server-side to self.
  /// [q] matches a voucher serial (substring) or an exact receipt number.
  Future<List<PrintOperation>> printOperations({
    String? storeId,
    String? q,
    int page = 0,
    int size = 50,
  }) async {
    final response = await _api.get(Endpoints.productPrintOperations, params: {
      if (storeId != null && storeId.isNotEmpty) 'storeId': storeId,
      if (q != null && q.isNotEmpty) 'q': q,
      'page': page,
      'size': size,
    });
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => PrintOperation.fromJson(e as Map<String, dynamic>))
          .toList();
    });
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

  /// Lists all voucher batches (newest first). The endpoint is HQ-only and
  /// returns every batch the platform admin manages, so no owner filter is sent.
  /// Calls `GET /api/inventory/batches`.
  Future<List<VoucherBatch>> listBatches() async {
    final response = await _api.get(Endpoints.productBatches);
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => VoucherBatch.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Pauses or resumes a batch via the single toggle endpoint.
  /// `POST /api/inventory/batch/pause?batchId=&paused=` (paused true/false).
  Future<void> pauseBatch(String batchId, {required bool pause}) async {
    final response = await _api.post(
      Endpoints.productBatchPause,
      params: {'batchId': batchId, 'paused': pause},
    );
    _api.unwrap(response, (_) {});
  }

  /// Deletes all AVAILABLE vouchers in a batch.
  /// The backend rejects with 409 when any voucher in the batch is already
  /// PRINTED (sold), so [VoucherBatch.canDelete] should be checked first.
  Future<void> deleteBatch(String batchId) async {
    await _api
        .delete(Endpoints.productBatchDelete, params: {'batchId': batchId});
  }

  /// Downloads the original serial/pin TXT for a batch (raw bytes, not JSON).
  /// Uses [ApiClient.getBytes] with ResponseType.bytes. HQ-only.
  Future<Uint8List> exportBatchTxt(String batchId) async {
    return _api
        .getBytes(Endpoints.productBatchExport, params: {'batchId': batchId});
  }
}
