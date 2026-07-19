import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';

class TransactionRepository {
  final ApiClient _api;
  TransactionRepository(this._api);

  Future<AppTransaction> create(AppTransaction tx) async {
    final response =
        await _api.post(Endpoints.transactionCreate, data: tx.toJson());
    return _api.unwrap(
        response, (d) => AppTransaction.fromJson(d as Map<String, dynamic>));
  }

  Future<AppTransaction> read(String id) async {
    final response =
        await _api.get(Endpoints.transactionRead, params: {'id': id});
    return _api.unwrap(
        response, (d) => AppTransaction.fromJson(d as Map<String, dynamic>));
  }

  Future<List<AppTransaction>> readAll() async {
    final response = await _api.get(Endpoints.transactionReadAll);
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => AppTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Default page size for [page]; the backend caps it at 200.
  static const int pageSize = 50;

  /// Paged transactions list (B-023 P1) — same visibility as [readAll] (HQ all,
  /// others their own subtree) but paged + status-filterable, newest first.
  Future<Paged<AppTransaction>> page({
    String? status,
    int page = 0,
    int size = pageSize,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (status != null && status.isNotEmpty) params['status'] = status;
    final response = await _api.get(Endpoints.transactionPage, params: params);
    return _api.unwrap(response,
        (d) => Paged.from(d, AppTransaction.fromJson, size: size));
  }

  /// The newest [limit] transactions visible to the caller (dashboard card);
  /// the server clamps the limit to 50.
  Future<List<AppTransaction>> recent({int limit = 10}) async {
    final response =
        await _api.get(Endpoints.transactionRecent, params: {'limit': limit});
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => AppTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<AppTransaction> update(AppTransaction tx) async {
    final response =
        await _api.put(Endpoints.transactionUpdate, data: tx.toJson());
    return _api.unwrap(
        response, (d) => AppTransaction.fromJson(d as Map<String, dynamic>));
  }

  Future<void> delete(String id) async {
    // DELETE with JSON body per backend design.
    await _api.delete(Endpoints.transactionDelete, data: {'id': id});
  }
}
