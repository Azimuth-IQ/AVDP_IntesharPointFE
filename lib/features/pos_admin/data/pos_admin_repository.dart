import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/pos_admin/domain/pos_slot_balance.dart';

/// POS-user quota + POS-user lifecycle (onboard / revoke / reset PIN / reset TOTP).
/// The backend enforces MANAGE_POS + self-or-descendant + quota; this is a thin client.
class PosAdminRepository {
  final ApiClient _api;
  PosAdminRepository(this._api);

  /// The entity's POS-slot quota (total / used / available). Null/'' entityId = the caller's own.
  Future<PosSlotBalance> quota({String? entityId}) async {
    final r = await _api.get(Endpoints.posQuota,
        params: {if (entityId != null && entityId.isNotEmpty) 'entityId': entityId});
    return _api.unwrap(r, (d) => PosSlotBalance.fromJson(d as Map<String, dynamic>));
  }

  /// Grant [count] POS-user slots to a DIRECT child. Source = the caller (server-side).
  Future<void> grantSlots({required String destId, required int count}) async {
    await _api.post(Endpoints.posQuotaGrant, data: {'destId': destId, 'count': count});
  }

  /// Onboard a POS user on [entityId] (consumes one slot).
  Future<void> onboard({
    required String entityId,
    required String phone,
    required String password,
    String? posName,
    String? posOwnerName,
    String? posGovernorate,
    String? posAddress,
  }) async {
    await _api.post(Endpoints.posUsersOnboard, params: {'entityId': entityId}, data: {
      'phone': phone,
      'password': password,
      if (posName != null && posName.isNotEmpty) 'posName': posName,
      if (posOwnerName != null && posOwnerName.isNotEmpty) 'posOwnerName': posOwnerName,
      if (posGovernorate != null && posGovernorate.isNotEmpty) 'posGovernorate': posGovernorate,
      if (posAddress != null && posAddress.isNotEmpty) 'posAddress': posAddress,
    });
  }

  /// Revoke a POS user (removes the login + releases the slot).
  Future<void> revoke({required String entityId, required String phone}) async {
    await _api.delete(Endpoints.posUsersRevoke, params: {'entityId': entityId, 'phone': phone});
  }

  Future<void> resetPin(String phone) async {
    await _api.post(Endpoints.posUsersResetPin, params: {'phone': phone});
  }

  Future<void> resetTotp(String phone) async {
    await _api.post(Endpoints.posUsersResetTotp, params: {'phone': phone});
  }
}
