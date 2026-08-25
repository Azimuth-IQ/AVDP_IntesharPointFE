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

/// One page of the statement (`GET /api/pos/statement/page`, UX-51), newest row
/// first, plus the balances that bracket it.
///
/// The balances are what make paging safe: a page of rows on its own cannot say
/// what the running total was when it started, so the server sends it. They are
/// NULLABLE on purpose — a missing figure is shown as unknown rather than as a
/// confident zero, which on a balance screen would read as "your account is
/// empty".
class StatementPage {
  final List<StatementRow> items;
  final int page;
  final int size;
  final bool hasMore;

  /// Running balance immediately BEFORE the oldest row on THIS page.
  final double? openingBalance;

  /// Running balance after the newest row on this page (= items.first.balanceAfter).
  final double? closingBalance;

  /// Running balance immediately before the window's first event — the figure
  /// the statement header opens with, which no single page could derive.
  final double? windowOpeningBalance;

  const StatementPage({
    this.items = const [],
    this.page = 0,
    this.size = 0,
    this.hasMore = false,
    this.openingBalance,
    this.closingBalance,
    this.windowOpeningBalance,
  });

  factory StatementPage.fromJson(Map<String, dynamic> j) => StatementPage(
        items: ((j['items'] as List<dynamic>?) ?? const [])
            .map((e) => StatementRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: (j['page'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        hasMore: j['hasMore'] as bool? ?? false,
        openingBalance: (j['openingBalance'] as num?)?.toDouble(),
        closingBalance: (j['closingBalance'] as num?)?.toDouble(),
        windowOpeningBalance: (j['windowOpeningBalance'] as num?)?.toDouble(),
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

  /// One page of the account statement over a Baghdad-local day window
  /// (YYYY-MM-DD, inclusive), newest row first.
  ///
  /// UX-51: replaces the unpaged `GET /api/pos/statement`, which handed a whole
  /// month — ~6,000 rows for a busy shop — to an Android 7.1 handheld in one
  /// JSON and then built a row for every one of them. [size] is clamped to
  /// [1, 200] server-side.
  Future<StatementPage> statementPage({
    String? from,
    String? to,
    int page = 0,
    int size = 50,
  }) async {
    final r = await _api.get(Endpoints.posStatementPage, params: {
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      'page': page,
      'size': size,
    });
    return _api.unwrap(
        r, (d) => StatementPage.fromJson(Map<String, dynamic>.from(d as Map)));
  }
}
