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

  Future<void> delete(String id) async {
    await _api.delete(Endpoints.companyDelete, params: {'id': id});
  }
}
