/// A recorded voucher reveal/print ("sale") at a store — the searchable record behind
/// the Print-Operations screen. Carries a per-store sequential [receiptNo] and the
/// voucher [serialNumber] (the operation reference). No PIN is ever included.
class PrintOperation {
  final String id;
  final int receiptNo;
  final String storeId;
  final String storeName;
  final String productId;
  final String serialNumber;
  final String sku;
  final String productName;
  final String? expiryDate;
  final String? governorate;
  final String? agentLogoUrl;
  final String? companyLogoUrl;
  final String? operatorPhone;
  final String createdAt;

  const PrintOperation({
    required this.id,
    required this.receiptNo,
    required this.storeId,
    this.storeName = '',
    this.productId = '',
    this.serialNumber = '',
    this.sku = '',
    this.productName = '',
    this.expiryDate,
    this.governorate,
    this.agentLogoUrl,
    this.companyLogoUrl,
    this.operatorPhone,
    this.createdAt = '',
  });

  factory PrintOperation.fromJson(Map<String, dynamic> j) => PrintOperation(
        id: j['id'] as String? ?? '',
        receiptNo: (j['receiptNo'] as num?)?.toInt() ?? 0,
        storeId: j['storeId'] as String? ?? '',
        storeName: j['storeName'] as String? ?? '',
        productId: j['productId'] as String? ?? '',
        serialNumber: j['serialNumber'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        productName: j['productName'] as String? ?? '',
        expiryDate: j['expiryDate'] as String?,
        governorate: j['governorate'] as String?,
        agentLogoUrl: j['agentLogoUrl'] as String?,
        companyLogoUrl: j['companyLogoUrl'] as String?,
        operatorPhone: j['operatorPhone'] as String?,
        createdAt: j['createdAt']?.toString() ?? '',
      );
}
