/// One row of the balance reports (#1 POS balances, #2 agent balances) from
/// `GET /api/reports/balances`. Mirrors backend `Pricing/DTOs/BalanceRosterRow`.
class BalanceRosterRow {
  final String entityId;
  final String name;
  final String ownerName;
  final String userPhone;
  final String governorate;
  final String address;
  final String tier;
  final num available;
  final num ordersSpent;
  final num grantsOut;
  final String mainAgentName;
  final String subAgentName;
  final int storeCount;

  const BalanceRosterRow({
    this.entityId = '',
    this.name = '',
    this.ownerName = '',
    this.userPhone = '',
    this.governorate = '',
    this.address = '',
    this.tier = '',
    this.available = 0,
    this.ordersSpent = 0,
    this.grantsOut = 0,
    this.mainAgentName = '',
    this.subAgentName = '',
    this.storeCount = 0,
  });

  factory BalanceRosterRow.fromJson(Map<String, dynamic> j) => BalanceRosterRow(
        entityId: j['entityId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        ownerName: j['ownerName'] as String? ?? '',
        userPhone: j['userPhone'] as String? ?? '',
        governorate: j['governorate'] as String? ?? '',
        address: j['address'] as String? ?? '',
        tier: j['tier'] as String? ?? '',
        available: (j['available'] as num?) ?? 0,
        ordersSpent: (j['ordersSpent'] as num?) ?? 0,
        grantsOut: (j['grantsOut'] as num?) ?? 0,
        mainAgentName: j['mainAgentName'] as String? ?? '',
        subAgentName: j['subAgentName'] as String? ?? '',
        storeCount: (j['storeCount'] as num?)?.toInt() ?? 0,
      );
}

/// One row of the financial-transfers report (#3) from `GET /api/reports/transfers`.
/// `balanceAfter` is the running credit total for the dest (credits only). Mirrors
/// backend `Pricing/DTOs/TransferReportRow`.
class TransferRow {
  final String id;
  final String date;
  final String time;
  final String sourceId;
  final String sourceName;
  final String destId;
  final String destName;
  final num amount;
  final num balanceAfter;
  final String destGovernorate;
  final String destOwnerName;
  final String destPhone;
  final String mainAgentName;
  final String subAgentName;

  const TransferRow({
    this.id = '',
    this.date = '',
    this.time = '',
    this.sourceId = '',
    this.sourceName = '',
    this.destId = '',
    this.destName = '',
    this.amount = 0,
    this.balanceAfter = 0,
    this.destGovernorate = '',
    this.destOwnerName = '',
    this.destPhone = '',
    this.mainAgentName = '',
    this.subAgentName = '',
  });

  factory TransferRow.fromJson(Map<String, dynamic> j) => TransferRow(
        id: j['id'] as String? ?? '',
        date: j['date'] as String? ?? '',
        time: j['time'] as String? ?? '',
        sourceId: j['sourceId'] as String? ?? '',
        sourceName: j['sourceName'] as String? ?? '',
        destId: j['destId'] as String? ?? '',
        destName: j['destName'] as String? ?? '',
        amount: (j['amount'] as num?) ?? 0,
        balanceAfter: (j['balanceAfter'] as num?) ?? 0,
        destGovernorate: j['destGovernorate'] as String? ?? '',
        destOwnerName: j['destOwnerName'] as String? ?? '',
        destPhone: j['destPhone'] as String? ?? '',
        mainAgentName: j['mainAgentName'] as String? ?? '',
        subAgentName: j['subAgentName'] as String? ?? '',
      );
}

/// One row of the sold-cards report (#4) from `GET /api/reports/sales`, per
/// (store × company × category × governorate). The FE rolls these up to #5
/// (total sold). Mirrors backend `Pricing/DTOs/SalesReportRow`.
class SalesRow {
  final String storeId;
  final String storeName;
  final String ownerName;
  final String userPhone;
  final String governorate;
  final String companyName;
  final String category;
  final String sku;
  final String mainAgentName;
  final String subAgentName;
  final int count;

  const SalesRow({
    this.storeId = '',
    this.storeName = '',
    this.ownerName = '',
    this.userPhone = '',
    this.governorate = '',
    this.companyName = '',
    this.category = '',
    this.sku = '',
    this.mainAgentName = '',
    this.subAgentName = '',
    this.count = 0,
  });

  factory SalesRow.fromJson(Map<String, dynamic> j) => SalesRow(
        storeId: j['storeId'] as String? ?? '',
        storeName: j['storeName'] as String? ?? '',
        ownerName: j['ownerName'] as String? ?? '',
        userPhone: j['userPhone'] as String? ?? '',
        governorate: j['governorate'] as String? ?? '',
        companyName: j['companyName'] as String? ?? '',
        category: j['category'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        mainAgentName: j['mainAgentName'] as String? ?? '',
        subAgentName: j['subAgentName'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// One row of the uploaded-cards report (#6) from `GET /api/reports/uploads`, per
/// (main agent × company × category × governorate). Mirrors backend `UploadsReportRow`.
class UploadsRow {
  final String agentId;
  final String agentName;
  final String governorate;
  final String companyName;
  final String category;
  final String sku;
  final int count;

  const UploadsRow({
    this.agentId = '',
    this.agentName = '',
    this.governorate = '',
    this.companyName = '',
    this.category = '',
    this.sku = '',
    this.count = 0,
  });

  factory UploadsRow.fromJson(Map<String, dynamic> j) => UploadsRow(
        agentId: j['agentId'] as String? ?? '',
        agentName: j['agentName'] as String? ?? '',
        governorate: j['governorate'] as String? ?? '',
        companyName: j['companyName'] as String? ?? '',
        category: j['category'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}
