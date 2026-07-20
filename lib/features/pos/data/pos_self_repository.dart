import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';

/// One row of the POS account statement (`GET /api/pos/statement`, B-054):
/// a credit (balance grant from the agent) or a debit (card sold), with the
/// running balance after the event.
class StatementRow {
  final String at; // ISO instant
  final String type; // GRANT | SALE
  final String label; // agent name / product name
  final double? amount; // signed; null for pre-B054 sales without a price
  final double balanceAfter;
  final int? receiptNo; // SALE rows only
  final bool? printed; // SALE rows only

  const StatementRow({
    this.at = '',
    this.type = 'SALE',
    this.label = '',
    this.amount,
    this.balanceAfter = 0,
    this.receiptNo,
    this.printed,
  });

  factory StatementRow.fromJson(Map<String, dynamic> j) => StatementRow(
        at: j['at'] as String? ?? '',
        type: j['type'] as String? ?? 'SALE',
        label: j['label'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble(),
        balanceAfter: (j['balanceAfter'] as num?)?.toDouble() ?? 0,
        receiptNo: (j['receiptNo'] as num?)?.toInt(),
        printed: j['printed'] as bool?,
      );
}

/// The POS app's self endpoints (B-054): one-time location confirmation and the
/// الحسابات account statement. Both are hard-scoped server-side to the calling shop.
class PosSelfRepository {
  final ApiClient _api;
  PosSelfRepository(this._api);

  /// One-time mandatory at-the-shop location confirmation (سستم A92). 409 when
  /// already confirmed.
  Future<void> confirmLocation({required double latitude, required double longitude}) async {
    await _api.post(Endpoints.posConfirmLocation,
        data: {'latitude': latitude, 'longitude': longitude});
  }

  /// Account statement over a Baghdad-local day window (YYYY-MM-DD, inclusive).
  Future<List<StatementRow>> statement({String? from, String? to}) async {
    final r = await _api.get(Endpoints.posStatement, params: {
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    });
    return _api.unwrap(r, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => StatementRow.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }
}
