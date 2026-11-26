import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/company_portal/domain/company_portal_models.dart';

/// PROD-037: the company account's own screen. The server decides which company — a
/// company account cannot ask for another one; [companyId] is only honoured for HQ.
class CompanyPortalRepository {
  final ApiClient _api;
  CompanyPortalRepository(this._api);

  Future<CompanyPortalInfo> me({String? companyId}) async {
    final r = await _api.get(Endpoints.companyPortalMe, params: {
      if (companyId != null && companyId.isNotEmpty) 'companyId': companyId,
    });
    return _api.unwrap(r, (d) => CompanyPortalInfo.fromJson((d as Map<String, dynamic>?) ?? const {}));
  }

  Future<List<CompanyUploadRow>> uploads({required String from, required String to, String? companyId}) async {
    final r = await _api.get(Endpoints.companyPortalUploads, params: {
      'from': from,
      'to': to,
      if (companyId != null && companyId.isNotEmpty) 'companyId': companyId,
    });
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => CompanyUploadRow.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  /// Records a saved file in HQ's activity view of this account. Best effort.
  Future<void> exported({required String from, required String to, String? governorate, String? companyId}) async {
    try {
      await _api.post(Endpoints.companyPortalExported, params: {
        'from': from,
        'to': to,
        if (governorate != null) 'governorate': governorate.isEmpty ? 'NONE' : governorate,
        if (companyId != null && companyId.isNotEmpty) 'companyId': companyId,
      });
    } catch (_) {
      // Never block the file on the audit call.
    }
  }
}

/// PROD-037: HQ's side — create, switch off/on, set a password, delete, activity.
class CompanyAccountRepository {
  final ApiClient _api;
  CompanyAccountRepository(this._api);

  Future<List<CompanyAccount>> list() async {
    final r = await _api.get(Endpoints.companyAccounts);
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => CompanyAccount.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<void> create({
    required String companyId,
    required String name,
    required String phone,
    required String password,
  }) async {
    final r = await _api.post(Endpoints.companyAccounts, data: {
      'companyId': companyId,
      'name': name,
      'phone': phone,
      'password': password,
    });
    _api.unwrap(r, (_) => null);
  }

  Future<void> setActive(String id, bool active) async {
    final r = await _api.post(Endpoints.companyAccountsActive, params: {'id': id, 'active': active});
    _api.unwrap(r, (_) => null);
  }

  Future<void> setPassword(String id, String password) async {
    final r = await _api.post(Endpoints.companyAccountsPassword, params: {'id': id}, data: {'password': password});
    _api.unwrap(r, (_) => null);
  }

  Future<void> delete(String id) async {
    final r = await _api.delete(Endpoints.companyAccounts, params: {'id': id});
    _api.unwrap(r, (_) => null);
  }

  Future<List<CompanyActivity>> activity(String id, {int size = 100}) async {
    final r = await _api.get(Endpoints.companyAccountsActivity, params: {'id': id, 'size': size});
    return _api.unwrap(r, (d) {
      final list = (d as List<dynamic>?) ?? const [];
      return list.map((e) => CompanyActivity.fromJson(e as Map<String, dynamic>)).toList();
    });
  }
}
