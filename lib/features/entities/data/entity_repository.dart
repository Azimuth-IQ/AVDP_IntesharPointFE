import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/entities/domain/branding.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

class EntityRepository {
  final ApiClient _api;
  EntityRepository(this._api);

  Future<Entity> create(Entity entity, {bool includeUsers = false}) async {
    final response = await _api.post(Endpoints.entityCreate, data: entity.toJson(includeUsers: includeUsers));
    return _api.unwrap(response, (d) => Entity.fromJson(d as Map<String, dynamic>));
  }

  /// Resolved white-label branding for the caller: the HQ home slider (active,
  /// ordered) + the caller's Main-Agent (AGENT1) logo/colours. `GET /api/entity/branding`.
  Future<BrandInfo> branding() async {
    final response = await _api.get(Endpoints.entityBranding);
    return _api.unwrap(response, (d) => BrandInfo.fromJson((d as Map).cast<String, dynamic>()));
  }

  Future<Entity> read(String id) async {
    final response = await _api.get(Endpoints.entityRead, params: {'id': id});
    return _api.unwrap(response, (d) => Entity.fromJson(d as Map<String, dynamic>));
  }

  /// The caller's own ancestor chain, nearest parent first, as display rows.
  ///
  /// Carries id/name/type only — no users, no KYC. A shop needs its agents' NAMES
  /// for the report header; it has no business reading their documents, and until
  /// the read guard landed it could read anyone's.
  Future<List<EntitySummaryRow>> chain() async {
    final response = await _api.get(Endpoints.entityChain);
    return _api.unwrap(response, (d) => (d as List<dynamic>)
        .map((e) => EntitySummaryRow.fromJson((e as Map).cast<String, dynamic>()))
        .toList());
  }

  /// The caller's own entity (B-023) — O(1); used at login instead of [readAll].
  Future<Entity> me() async {
    final response = await _api.get(Endpoints.entityMe);
    return _api.unwrap(response, (d) => Entity.fromJson(d as Map<String, dynamic>));
  }

  Future<List<Entity>> readAll() async {
    final response = await _api.get(Endpoints.entityReadAll);
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list.map((e) => Entity.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  /// Default page size for the paged entity reads; the backend caps it at 200.
  static const int pageSize = 50;

  /// Server-side picker search (B-023 P1): contains-match on name/id, optional
  /// tier filter. HQ searches globally; any other caller is scoped to its own
  /// subtree by the server — the replacement for feeding dropdowns via [readAll].
  Future<Paged<EntitySummaryRow>> search({
    String? q,
    List<EntityType>? types,
    int page = 0,
    int size = pageSize,
  }) async {
    final params = <String, dynamic>{'page': page, 'size': size};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (types != null && types.isNotEmpty) {
      params['type'] = types.map((t) => t.name).join(',');
    }
    final response = await _api.get(Endpoints.entitySearch, params: params);
    return _api.unwrap(
        response, (d) => Paged.from(d, EntitySummaryRow.fromJson, size: size));
  }

  /// Direct children of one node, paged (B-023 P1) — powers the load-on-expand
  /// hierarchy tree. Queries by the `parent` field server-side, so it is immune
  /// to the childrenIds-clearing bug that [readDirectChildren] works around.
  Future<Paged<EntitySummaryRow>> children(
    String parentId, {
    int page = 0,
    int size = pageSize,
  }) async {
    final response = await _api.get(Endpoints.entityChildren,
        params: {'parentId': parentId, 'page': page, 'size': size});
    return _api.unwrap(
        response, (d) => Paged.from(d, EntitySummaryRow.fromJson, size: size));
  }

  /// Returns Map keyed by BFS depth level.
  Future<Map<int, List<Entity>>> readWithChildren(String id) async {
    final response = await _api.get(Endpoints.entityReadWithChildren, params: {'id': id});
    return _api.unwrap(response, (d) {
      final map = d as Map<String, dynamic>;
      return map.map((key, value) {
        final depth = int.tryParse(key) ?? 0;
        final entities = (value as List<dynamic>).map((e) => Entity.fromJson(e as Map<String, dynamic>)).toList();
        return MapEntry(depth, entities);
      });
    });
  }

  /// Fetches all entities and builds the depth tree client-side using the
  /// parent field — avoids the backend bug where updateEntity clears childrenIds.
  Future<Map<int, List<Entity>>> readAllAsTree(String rootId) async {
    final all = await readAll();
    return _buildTree(all, rootId);
  }

  Map<int, List<Entity>> _buildTree(List<Entity> entities, String rootId) {
    final byId = <String, Entity>{for (final e in entities) e.id: e};
    final depths = <String, int>{rootId: 0};

    // Walk each entity's parent chain upward to assign depths.
    for (final e in entities) {
      if (depths.containsKey(e.id)) continue;
      final chain = <String>[];
      var cur = e.id;
      while (cur.isNotEmpty && !depths.containsKey(cur)) {
        if (chain.contains(cur)) break; // cycle guard
        chain.add(cur);
        cur = byId[cur]?.parent ?? '';
      }
      if (depths.containsKey(cur)) {
        var d = depths[cur]!;
        for (final id in chain.reversed) {
          depths[id] = ++d;
        }
      }
    }

    final result = <int, List<Entity>>{};
    for (final e in entities) {
      final d = depths[e.id];
      if (d != null) result.putIfAbsent(d, () => []).add(e);
    }
    return result;
  }

  /// Fetches direct children of [parentId] using the parent field — immune to
  /// the backend bug where updateEntity clears childrenIds.
  Future<List<Entity>> readDirectChildren(String parentId) async {
    final all = await readAll();
    return all.where((e) => e.parent == parentId).toList();
  }

  Future<Entity> update(Entity entity) async {
    // Omit users to avoid double-BCrypt re-hashing on the backend.
    final response = await _api.put(Endpoints.entityUpdate, data: entity.toJson(includeUsers: false));
    return _api.unwrap(response, (d) => Entity.fromJson(d as Map<String, dynamic>));
  }

  Future<Entity> updateWithUsers(Entity entity) async {
    final response = await _api.put(Endpoints.entityUpdate, data: entity.toJson(includeUsers: true));
    return _api.unwrap(response, (d) => Entity.fromJson(d as Map<String, dynamic>));
  }

  Future<void> delete(String id) async {
    await _api.delete(Endpoints.entityDelete, params: {'id': id});
  }

  // ---- HQ users / supervisors (single-user endpoints; avoid the buggy full-PUT) ----

  Future<List<EntityUser>> listUsers(String entityId) async {
    final response =
        await _api.get(Endpoints.entityUsers, params: {'entityId': entityId});
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list
          .map((e) => EntityUser.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> addUser({
    required String entityId,
    required String phone,
    required String password,
    required UserRole role,
    required Set<Capability> capabilities,
  }) async {
    await _api.post(Endpoints.entityUserAdd, data: {
      'entityId': entityId,
      'phone': phone,
      'password': password,
      'role': role.name,
      'capabilities': capabilitiesToJson(capabilities),
    });
  }

  Future<void> updateUser({
    required String phone,
    required UserRole role,
    required Set<Capability> capabilities,
  }) async {
    await _api.put(Endpoints.entityUserUpdate, data: {
      'phone': phone,
      'role': role.name,
      'capabilities': capabilitiesToJson(capabilities),
    });
  }

  Future<void> removeUser(String entityId, String phone) async {
    await _api.delete(Endpoints.entityUserRemove,
        params: {'entityId': entityId, 'phone': phone});
  }

  /// HQ recovery: reset a user's 2FA (clears the TOTP secret + enrollment, so they
  /// re-enroll on next login).
  Future<void> resetUserTotp(String phone) async {
    await _api.post(Endpoints.entityUserResetTotp, params: {'phone': phone});
  }

  /// Reset a user's password to [newPassword] (the backend hashes it + forces a change
  /// on next login). Used from the hierarchy's Manage-Users sheet.
  Future<void> resetPassword(String entityId, String phone, String newPassword) async {
    await _api.post(Endpoints.entityResetPassword,
        params: {'id': entityId, 'phone': phone, 'newPassword': newPassword});
  }

  /// Re-links a child to its parent's childrenIds list.
  /// The backend has a known bug where creating a child does not always append
  /// its id to the parent's childrenIds — this workaround handles that.
  Future<void> relinkChildToParent(String parentId, String childId) async {
    try {
      final parent = await read(parentId);
      if (!parent.childrenIds.contains(childId)) {
        final updated = parent.copyWith(childrenIds: [...parent.childrenIds, childId]);
        await updateWithUsers(updated);
      }
    } catch (_) {
      // Non-fatal; flag to backend team.
    }
  }
}
