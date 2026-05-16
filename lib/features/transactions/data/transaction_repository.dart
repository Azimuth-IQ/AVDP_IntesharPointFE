import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
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
