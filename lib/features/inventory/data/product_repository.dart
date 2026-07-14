import 'dart:typed_data';

import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/domain/print_operation.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/inventory/domain/batch_withdraw_result.dart';
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

  /// Telecom company name (Company.name resolved via ProductDefinition.companyId).
  final String? companyName;

  /// Human-readable category name (the ProductDefinition.name).
  final String? categoryName;
  const RevealResult({
    required this.product,
    this.receiptNo = 0,
    this.agentLogoUrl,
    this.companyLogoUrl,
    this.companyName,
    this.categoryName,
  });
}

/// One sellable (SKU × governorate) option on the POS draw-on-print screen: a voucher kind
/// the store can draw from its parent Main Agent's pool. [price] is the store's cost (its
/// parent's effective price), [available] is the pool count, and [affordable] is how many of
/// those the store's withdrawal limit can cover.
class SellableSku {
  final String sku;
  final String name;
  final String? companyName;
  final String? companyLogoUrl; // telecom company logo (for the Companies step)
  final String? imageUrl;       // card-type artwork (ProductDefinition.imageUrl)
  final String? governorate; // null/"" = untagged (region-free)
  final num price;
  final int available;
  final int affordable;
  const SellableSku({
    required this.sku,
    required this.name,
    this.companyName,
    this.companyLogoUrl,
    this.imageUrl,
    this.governorate,
    this.price = 0,
    this.available = 0,
    this.affordable = 0,
  });

  factory SellableSku.fromJson(Map<String, dynamic> m) => SellableSku(
        sku: m['sku'] as String? ?? '',
        name: m['name'] as String? ?? '',
        companyName: m['companyName'] as String?,
        companyLogoUrl: m['companyLogoUrl'] as String?,
        imageUrl: m['imageUrl'] as String?,
        governorate: m['governorate'] as String?,
        price: (m['price'] as num?) ?? 0,
        available: (m['available'] as num?)?.toInt() ?? 0,
        affordable: (m['affordable'] as num?)?.toInt() ?? 0,
      );
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

  /// Draw-on-print: the SKUs this entity can sell from its parent Main Agent's pool — each
  /// with the store's cost, the pool's available count, and how many its withdrawal limit
  /// can afford. Pass [entityId] to view another account (HQ/ancestor); omit for the
  /// caller's own. Calls `GET /api/inventory/product/sellable`.
  Future<List<SellableSku>> sellable({String? entityId}) async {
    final response = await _api.get(Endpoints.productSellable, params: {
      if (entityId != null && entityId.isNotEmpty) 'entityId': entityId,
    });
    return _api.unwrap(response, (d) {
      final list = (d as List<dynamic>? ?? const []);
      return list
          .map((e) => SellableSku.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Draw + sell one voucher of [sku] (optional [governorate] bucket) from the parent pool:
  /// atomic claim + per-tier withdrawal-limit debit, returns the decrypted PIN + receipt
  /// (same shape as a reveal). [clientRef] is a per-attempt idempotency key so a retry over
  /// a flaky link returns the SAME sale instead of burning a second card.
  /// Calls `POST /api/inventory/product/draw`.
  Future<RevealResult> draw({
    required String sku,
    String? governorate,
    String? clientRef,
  }) async {
    final response = await _api.post(Endpoints.productDraw, params: {
      'sku': sku,
      if (governorate != null && governorate.isNotEmpty) 'governorate': governorate,
      if (clientRef != null && clientRef.isNotEmpty) 'clientRef': clientRef,
    });
    return _api.unwrap(response, _revealFromJson);
  }

  /// Recover a drawn voucher whose response was lost: re-returns the SAME PIN + receipt for
  /// the seller, never a new card or debit. Looks up by the idempotency [clientRef]
  /// (preferred) or the [productId] from a partial response.
  /// Calls `POST /api/inventory/product/draw/recover`.
  Future<RevealResult> drawRecover({String? clientRef, String? productId}) async {
    final response = await _api.post(Endpoints.productDrawRecover, params: {
      if (clientRef != null && clientRef.isNotEmpty) 'clientRef': clientRef,
      if (productId != null && productId.isNotEmpty) 'productId': productId,
    });
    return _api.unwrap(response, _revealFromJson);
  }

  RevealResult _revealFromJson(dynamic d) {
    final m = d as Map<String, dynamic>;
    return RevealResult(
      product: Product.fromJson(m['product'] as Map<String, dynamic>? ?? {}),
      receiptNo: (m['receiptNo'] as num?)?.toInt() ?? 0,
      agentLogoUrl: m['agentLogoUrl'] as String?,
      companyLogoUrl: m['companyLogoUrl'] as String?,
      companyName: m['companyName'] as String?,
      categoryName: m['categoryName'] as String?,
    );
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

  Future<Product> update(Product product) async {
    final response =
        await _api.put(Endpoints.productUpdate, data: product.toJson());
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
  }

  Future<void> delete(String id) async {
    await _api.delete(Endpoints.productDelete, params: {'id': id});
  }

  /// HQ-only stock reallocation. Moves up to [amount] of [sourceId]'s AVAILABLE,
  /// non-expired vouchers of [sku] in the [governorate] bucket to [destinationId]
  /// in one guarded server-side move. A `null`/blank [governorate] targets the
  /// untagged (region-free) bucket. A reverse "withdraw" is the same call with
  /// source/destination swapped — there is no separate endpoint. Calls
  /// `POST /api/inventory/agent-transfer` and returns the number actually moved.
  Future<int> agentTransfer({
    required String sourceId,
    required String destinationId,
    required String sku,
    String? governorate,
    required int amount,
  }) async {
    // Path is inlined (not in Endpoints) to keep this Wave-2 change self-contained.
    final response = await _api.post('/api/inventory/agent-transfer', data: {
      'sourceId': sourceId,
      'destinationId': destinationId,
      'sku': sku,
      if (governorate != null && governorate.isNotEmpty) 'governorate': governorate,
      'amount': amount,
    });
    return _api.unwrap(response, (d) {
      final m = d as Map<String, dynamic>;
      return (m['moved'] as num?)?.toInt() ?? 0;
    });
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

  /// Withdraws (reclaims) all still-AVAILABLE vouchers in a batch back to the
  /// batch origin (HQ), regardless of which descendant currently holds them.
  /// PRINTED (sold) vouchers are tallied but never blocked — only AVAILABLE
  /// codes move. Returns counts of [reclaimed], [used], and [total] so the
  /// caller can surface a meaningful summary.
  /// Calls `POST /api/inventory/batch/withdraw?batchId=`. HQ-only.
  Future<BatchWithdrawResult> withdrawBatch(String batchId) async {
    final response = await _api.post(
      Endpoints.productBatchWithdraw,
      params: {'batchId': batchId},
    );
    return _api.unwrap(
      response,
      (d) => BatchWithdrawResult.fromJson(d as Map<String, dynamic>),
    );
  }

  /// Downloads the original serial/pin TXT for a batch (raw bytes, not JSON).
  /// Uses [ApiClient.getBytes] with ResponseType.bytes. HQ-only.
  Future<Uint8List> exportBatchTxt(String batchId) async {
    return _api
        .getBytes(Endpoints.productBatchExport, params: {'batchId': batchId});
  }
}
