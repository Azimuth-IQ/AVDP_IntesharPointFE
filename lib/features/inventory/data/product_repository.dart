import 'dart:typed_data';

import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/inventory/domain/print_operation.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/inventory/domain/batch_withdraw_result.dart';
import 'package:inteshar/features/inventory/domain/stock_withdraw_result.dart';
import 'package:inteshar/features/inventory/domain/voucher_batch.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';

/// B-086 pre-flight quote for a bulk sale (no money moves, no cards claimed).
class BulkQuote {
  /// Most cards sellable right now = min(limit, cap headroom, stock, affordable).
  final int maxAllowed;

  /// This account's configured per-request ceiling, before the other clamps.
  final int configuredLimit;
  final double unitPrice;
  final double total;

  /// Which constraint bound [maxAllowed]: LIMIT | CAP | STOCK | BALANCE | NONE.
  final String limitedBy;

  /// Cards still allowed by the rolling withdrawal cap (-1 = uncapped).
  final int capRemaining;
  final int available;

  const BulkQuote({
    this.maxAllowed = 1,
    this.configuredLimit = 1,
    this.unitPrice = 0,
    this.total = 0,
    this.limitedBy = 'NONE',
    this.capRemaining = -1,
    this.available = 0,
  });

  /// True when this account may sell more than one card per request.
  bool get bulkEnabled => configuredLimit > 1;

  factory BulkQuote.fromJson(Map<String, dynamic> j) => BulkQuote(
        maxAllowed: (j['maxAllowed'] as num?)?.toInt() ?? 1,
        configuredLimit: (j['configuredLimit'] as num?)?.toInt() ?? 1,
        unitPrice: (j['unitPrice'] as num?)?.toDouble() ?? 0,
        total: (j['total'] as num?)?.toDouble() ?? 0,
        limitedBy: j['limitedBy'] as String? ?? 'NONE',
        capRemaining: (j['capRemaining'] as num?)?.toInt() ?? -1,
        available: (j['available'] as num?)?.toInt() ?? 0,
      );
}

/// B-086 result of a bulk sale. Each card is a fully committed sale with its own
/// receipt — [sold] may be < [requested] if the pool drained (the rest was refunded).
class BulkDrawResult {
  final String batchRef;
  final int requested;
  final int sold;
  final String? shortfallReason;
  final double unitPrice;
  final double total;
  final List<RevealResult> cards;

  const BulkDrawResult({
    required this.batchRef,
    required this.requested,
    required this.sold,
    this.shortfallReason,
    this.unitPrice = 0,
    this.total = 0,
    this.cards = const [],
  });

  bool get isPartial => sold < requested;
}

/// Enriched voucher-reveal payload: the consumed product (PIN decrypted), the
/// per-store sequential receipt number, and the resolved main-agent + company logo
/// URLs the POS prints on the receipt.
class RevealResult {
  final Product product;
  final int receiptNo;

  /// B-054: the sale's PrintOperation id — confirmPrint reports the physical
  /// print outcome against it.
  final String? operationId;
  final String? agentLogoUrl;
  final String? companyLogoUrl;

  /// Telecom company name (Company.name resolved via ProductDefinition.companyId).
  final String? companyName;

  /// Human-readable category name (the ProductDefinition.name).
  final String? categoryName;
  const RevealResult({
    required this.product,
    this.receiptNo = 0,
    this.operationId,
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

  /// B-086 pre-flight for a bulk sale — moves NO money and claims NO cards. Tells the
  /// POS the most cards sellable right now and which constraint bound it.
  Future<BulkQuote> bulkQuote({
    required String sku,
    String? governorate,
    int qty = 1,
  }) async {
    final r = await _api.get(Endpoints.productBulkQuote, params: {
      'sku': sku,
      if (governorate != null && governorate.isNotEmpty) 'governorate': governorate,
      'qty': qty,
    });
    return _api.unwrap(r, (d) => BulkQuote.fromJson((d as Map).cast<String, dynamic>()));
  }

  /// B-086: sell [qty] cards of one SKU in a single guarded request. [batchRef] is the
  /// batch idempotency key — replaying it re-serves the SAME cards, never a second charge.
  Future<BulkDrawResult> drawBulk({
    required String sku,
    String? governorate,
    required int qty,
    required String batchRef,
  }) async {
    final r = await _api.post(Endpoints.productDrawBulk, params: {
      'sku': sku,
      if (governorate != null && governorate.isNotEmpty) 'governorate': governorate,
      'qty': qty,
      'batchRef': batchRef,
    });
    return _api.unwrap(r, (d) => _bulkFromJson(d));
  }

  /// Recover a whole bulk sale whose response was lost (app killed mid-print).
  Future<BulkDrawResult> drawRecoverBatch(String batchRef) async {
    final r = await _api.post(Endpoints.productDrawRecoverBatch, params: {'batchRef': batchRef});
    return _api.unwrap(r, (d) => _bulkFromJson(d));
  }

  BulkDrawResult _bulkFromJson(dynamic d) {
    final m = (d as Map).cast<String, dynamic>();
    return BulkDrawResult(
      batchRef: m['batchRef'] as String? ?? '',
      requested: (m['requested'] as num?)?.toInt() ?? 0,
      sold: (m['sold'] as num?)?.toInt() ?? 0,
      shortfallReason: m['shortfallReason'] as String?,
      unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
      total: (m['total'] as num?)?.toDouble() ?? 0,
      cards: ((m['cards'] as List?) ?? const [])
          .map((e) => _revealFromJson(e))
          .toList(),
    );
  }

  RevealResult _revealFromJson(dynamic d) {
    final m = d as Map<String, dynamic>;
    return RevealResult(
      product: Product.fromJson(m['product'] as Map<String, dynamic>? ?? {}),
      receiptNo: (m['receiptNo'] as num?)?.toInt() ?? 0,
      operationId: m['operationId'] as String?,
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
    String? from, // YYYY-MM-DD Baghdad-local day (inclusive), B-054
    String? to,
    int page = 0,
    int size = 50,
  }) async {
    final response = await _api.get(Endpoints.productPrintOperations, params: {
      if (storeId != null && storeId.isNotEmpty) 'storeId': storeId,
      if (q != null && q.isNotEmpty) 'q': q,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
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

  /// Corrects a single voucher's status (HQ only).
  ///
  /// Only AVAILABLE and DAMAGED are accepted; the server refuses to move a sold
  /// voucher, whose code is already in a customer's hands. Never returns a PIN.
  /// `POST /api/inventory/product/setStatus?id=&status=`.
  Future<Product> setStatus(String id, ProductStatus status) async {
    final response = await _api.post(
      Endpoints.productSetStatus,
      params: {'id': id, 'status': status.name},
    );
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
  }

  /// Replaces the code on a voucher that is still available (HQ only).
  ///
  /// The server re-encrypts it and never echoes it back.
  /// `POST /api/inventory/product/setPin?id=` with `{pin}`.
  Future<Product> setPin(String id, String pin) async {
    final response = await _api.post(
      Endpoints.productSetPin,
      params: {'id': id},
      data: {'pin': pin},
    );
    return _api.unwrap(
        response, (d) => Product.fromJson(d as Map<String, dynamic>));
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

  /// Pulls [count] still-sellable vouchers of one SKU back from an agent's
  /// warehouse to HQ (C-09 — the reallocation removed in B-051).
  ///
  /// Returns how many actually moved, which can be fewer than asked: the agent may
  /// hold fewer, or some may have sold between looking and pressing.
  /// `POST /api/inventory/withdraw`.
  Future<StockWithdrawResult> withdrawStock({
    required String fromEntityId,
    required String sku,
    String? governorate,
    required int count,
  }) async {
    final response = await _api.post(Endpoints.productWithdrawStock, params: {
      'fromEntityId': fromEntityId,
      'sku': sku,
      if (governorate != null && governorate.isNotEmpty) 'governorate': governorate,
      'count': count,
    });
    return _api.unwrap(
        response, (d) => StockWithdrawResult.fromJson(d as Map<String, dynamic>));
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
