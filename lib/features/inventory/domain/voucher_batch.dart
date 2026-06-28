// ignore_for_file: constant_identifier_names

/// Status of a voucher batch — mirrors the backend `BatchStatus` enum.
enum BatchStatus { ACTIVE, PAUSED }

/// A group of vouchers uploaded together in one import operation.
/// Mirrors the backend `VoucherBatch` projection returned by
/// `GET /api/inventory/batches`.
class VoucherBatch {
  final String id;
  final String sku;
  final String productName;
  final String ownerId;
  final String? ownerName;

  /// Import format: 'NEW' (Asiacell / Zain, region-locked) or 'OTHER'.
  final String type;

  /// Governorate geo-lock tag, null for region-free (OTHER) batches.
  final String? governorate;

  final int totalCount;
  final int availableCount;

  /// Vouchers that have been revealed/sold (PRINTED status).
  final int printedCount;

  final BatchStatus status;
  final String createdAt;

  const VoucherBatch({
    required this.id,
    required this.sku,
    this.productName = '',
    required this.ownerId,
    this.ownerName,
    this.type = 'NEW',
    this.governorate,
    required this.totalCount,
    required this.availableCount,
    required this.printedCount,
    this.status = BatchStatus.ACTIVE,
    this.createdAt = '',
  });

  bool get paused => status == BatchStatus.PAUSED;

  /// A batch can only be deleted when no vouchers have been sold yet.
  bool get canDelete => printedCount == 0;

  factory VoucherBatch.fromJson(Map<String, dynamic> j) => VoucherBatch(
        id: j['id'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        productName: j['productName'] as String? ?? '',
        ownerId: j['ownerId'] as String? ?? '',
        ownerName: j['ownerName'] as String?,
        type: j['type'] as String? ?? 'NEW',
        governorate: j['governorate'] as String?,
        totalCount: (j['totalCount'] as num?)?.toInt() ?? 0,
        availableCount: (j['availableCount'] as num?)?.toInt() ?? 0,
        printedCount: (j['printedCount'] as num?)?.toInt() ?? 0,
        status: BatchStatus.values.firstWhere(
          (e) => e.name == (j['status'] as String? ?? 'ACTIVE'),
          orElse: () => BatchStatus.ACTIVE,
        ),
        createdAt: j['createdAt']?.toString() ?? '',
      );
}
