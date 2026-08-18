import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/companies/domain/company.dart';

/// Company CRUD. Reads are open; the backend enforces HQ-only on writes.
class CompanyRepository {
  final ApiClient _api;
  CompanyRepository(this._api);

  Future<List<Company>> readAll() async {
    final r = await _api.get(Endpoints.companyReadAll);
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => Company.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<Company> create(Company company) async {
    final r = await _api.post(Endpoints.companyCreate, data: company.toJson());
    return _api.unwrap(r, (d) => Company.fromJson(d as Map<String, dynamic>));
  }

  Future<Company> update(Company company) async {
    final r = await _api.put(Endpoints.companyUpdate, data: company.toJson());
    return _api.unwrap(r, (d) => Company.fromJson(d as Map<String, dynamic>));
  }

  /// Deleting a company orphans its categories, so the server refuses while it
  /// still has any and names the count; [force] confirms that specifically.
  Future<void> delete(String id, {bool force = false}) async {
    await _api.delete(Endpoints.companyDelete,
        params: {'id': id, if (force) 'force': true});
  }

  /// B-058: the agent ids a company is directly restricted for (HQ view).
  Future<List<String>> restrictions(String companyId) async {
    final r = await _api.get(Endpoints.companyRestrictions, params: {'companyId': companyId});
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list
          .map((e) => (e as Map<String, dynamic>)['entityId'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    });
  }

  /// Restrict or clear a company for one agent (cascades to its subtree).
  Future<void> setRestricted({required String companyId, required String entityId, required bool restricted}) async {
    await _api.post(Endpoints.companyRestrict,
        data: {'companyId': companyId, 'entityId': entityId, 'restricted': restricted});
  }
}
