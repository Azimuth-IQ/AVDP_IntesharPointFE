import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

class EntityRepository {
  final ApiClient _api;
  EntityRepository(this._api);

  Future<Entity> create(Entity entity, {bool includeUsers = false}) async {
    final response = await _api.post(Endpoints.entityCreate, data: entity.toJson(includeUsers: includeUsers));
    return _api.unwrap(response, (d) => Entity.fromJson(d as Map<String, dynamic>));
  }

  Future<Entity> read(String id) async {
    final response = await _api.get(Endpoints.entityRead, params: {'id': id});
    return _api.unwrap(response, (d) => Entity.fromJson(d as Map<String, dynamic>));
  }

  Future<List<Entity>> readAll() async {
    final response = await _api.get(Endpoints.entityReadAll);
    return _api.unwrap(response, (d) {
      final list = d as List<dynamic>;
      return list.map((e) => Entity.fromJson(e as Map<String, dynamic>)).toList();
    });
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
