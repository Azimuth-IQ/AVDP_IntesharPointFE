import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/pos_admin/domain/archived_pos.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/pos_admin/domain/pos_network.dart';
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

  /// HQ network oversight (B-029): network-wide POS-slot totals.
  Future<PosNetworkSummary> networkSummary() async {
    final r = await _api.get(Endpoints.posQuotaNetworkSummary);
    return _api.unwrap(r, (d) => PosNetworkSummary.fromJson((d as Map).cast<String, dynamic>()));
  }

  /// HQ network oversight (B-029): a page of agent slot rows, optionally filtered by
  /// name [q] and [tier] (AGENT1|AGENT2).
  Future<PosNetworkPage> network({String? q, String? tier, int page = 0, int size = 20}) async {
    final r = await _api.get(Endpoints.posQuotaNetwork, params: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (tier != null && tier.isNotEmpty) 'tier': tier,
      'page': page,
      'size': size,
    });
    return _api.unwrap(r, (d) {
      final m = (d as Map).cast<String, dynamic>();
      final items = ((m['items'] as List?) ?? const [])
          .map((e) => PosNetworkRow.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      return PosNetworkPage(items, m['hasMore'] as bool? ?? false);
    });
  }

  /// The host agent's POS shops — its STORE children, PAGED (B-023 P2).
  ///
  /// `Paged.from` tolerates a bare array, so this still works against a backend
  /// that predates the paged route — it just comes back as one page.
  /// [q] searches the shop name OR its operator's phone, SERVER-side (B-129) —
  /// filtering the fetched page would only ever search the rows already on
  /// screen, which is the trap B-066 fixed elsewhere.
  Future<Paged<Entity>> listPaged({
    String? entityId,
    String q = '',
    int page = 0,
    int size = 50,
  }) async {
    final r = await _api.get(Endpoints.posUsersListPaged, params: {
      if (entityId != null && entityId.isNotEmpty) 'entityId': entityId,
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'page': page,
      'size': size,
    });
    return _api.unwrap(r, (d) => Paged.from(d, Entity.fromJson, size: size));
  }

  /// Unpaged variant. Kept for callers that genuinely need every shop at once.
  Future<List<Entity>> list({String? entityId}) async {
    final r = await _api.get(Endpoints.posUsersList,
        params: {if (entityId != null && entityId.isNotEmpty) 'entityId': entityId});
    return _api.unwrap(r, (d) {
      final list = d as List<dynamic>;
      return list.map((e) => Entity.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  /// Enable/disable a POS shop (its operator can no longer log in when disabled).
  Future<void> setActive(String storeId, bool active) async {
    await _api.post(Endpoints.entitySetActive, params: {'id': storeId, 'active': active});
  }

  /// Onboard a POS on [entityId] — creates a STORE child entity and consumes one slot (B-052).
  Future<void> onboard({
    required String entityId,
    required String phone,
    required String password,
    String? posName,
    String? posOwnerName,
    String? posGovernorate,
    String? posAddress,
    double? posLatitude,
    double? posLongitude,
  }) async {
    await _api.post(Endpoints.posUsersOnboard, params: {'entityId': entityId}, data: {
      'phone': phone,
      'password': password,
      if (posName != null && posName.isNotEmpty) 'posName': posName,
      if (posOwnerName != null && posOwnerName.isNotEmpty) 'posOwnerName': posOwnerName,
      if (posGovernorate != null && posGovernorate.isNotEmpty) 'posGovernorate': posGovernorate,
      if (posAddress != null && posAddress.isNotEmpty) 'posAddress': posAddress,
      // B-080: an optional location HINT — it pre-centres the shop's own confirm
      // map, it does NOT confirm the location (selling stays blocked until the
      // operator pins it on site).
      'posLatitude': ?posLatitude,
      'posLongitude': ?posLongitude,
    });
  }

  /// Edit an existing POS user's profile (B-045). Phone/password/PIN are unchanged.
  Future<void> update({
    required String phone,
    required String posName,
    required String posOwnerName,
    required String posGovernorate,
    required String posAddress,
  }) async {
    await _api.post(Endpoints.posUsersUpdate, params: {'phone': phone}, data: {
      'posName': posName,
      'posOwnerName': posOwnerName,
      'posGovernorate': posGovernorate,
      'posAddress': posAddress,
    });
  }

  /// The archive: shops retired under [entityId] (default the caller) and its
  /// subtree, newest first, each carrying how many days remain before it can be
  /// deleted for good. `GET /api/pos-users/archived`.
  Future<List<ArchivedPos>> archived({String? entityId}) async {
    final response = await _api.get(Endpoints.posUsersArchived,
        params: {'entityId': ?entityId});
    return _api.unwrap(
        response,
        (d) => (d as List<dynamic>)
            .map((e) => ArchivedPos.fromJson(e as Map<String, dynamic>))
            .toList());
  }

  /// Everything the platform holds about one shop, so it can be saved before
  /// archiving starts the countdown. `GET /api/pos-users/export`.
  Future<PosDataExport> exportPos(String entityId) async {
    final response =
        await _api.get(Endpoints.posUsersExport, params: {'entityId': entityId});
    return _api.unwrap(
        response, (d) => PosDataExport.fromJson(d as Map<String, dynamic>));
  }

  /// Permanently deletes an archived shop. The server refuses until the
  /// retention window has elapsed, and requires the caller's authenticator code.
  /// `DELETE /api/pos-users/purge`.
  Future<void> purge({required String entityId, String? totp}) async {
    await _api.delete(Endpoints.posUsersPurge, params: {
      'entityId': entityId,
      if (totp != null && totp.isNotEmpty) 'totp': totp,
    });
  }

  /// Revoke a POS user (removes the shop + its login, and releases the slot).
  ///
  /// [totp] is the caller's authenticator code. The server requires it whenever
  /// the caller has 2FA enrolled — this destroys the shop and its history and
  /// cannot be undone. Callers on a tier where HQ has switched 2FA off are waved
  /// through, so the code is optional on the wire.
  Future<void> revoke({
    required String entityId,
    required String phone,
    String? totp,
  }) async {
    await _api.delete(Endpoints.posUsersRevoke, params: {
      'entityId': entityId,
      'phone': phone,
      if (totp != null && totp.isNotEmpty) 'totp': totp,
    });
  }

  /// Reset a POS user's PIN and return the fresh manager-visible PIN (B-047).
  Future<String> resetPin(String phone) async {
    final r = await _api.post(Endpoints.posUsersResetPin, params: {'phone': phone});
    return _api.unwrap(r, (d) => d as String);
  }

  Future<void> resetTotp(String phone) async {
    await _api.post(Endpoints.posUsersResetTotp, params: {'phone': phone});
  }

  /// Reset a POS user's login password to [password] (B-047).
  Future<void> resetPassword(String phone, String password) async {
    await _api.post(Endpoints.posUsersResetPassword,
        params: {'phone': phone}, data: {'password': password});
  }
}
