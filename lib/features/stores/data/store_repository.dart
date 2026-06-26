import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/stores/domain/pos_stats.dart';

/// Data access for the Stores / POS management screen. Lists the STORE points in
/// the caller's subtree (built from the `parent` field — immune to the backend
/// `childrenIds` bug) and wraps the point-management endpoints (enable/disable,
/// reset password, stats). Writes go through [EntityRepository] to honor its
/// `includeUsers` / parent-relink quirks.
class StoreRepository {
  final ApiClient _api;
  late final EntityRepository _entities = EntityRepository(_api);
  StoreRepository(this._api);

  /// All STORE points under [viewerId] (the logged-in entity), sorted by name.
  Future<List<Entity>> listStores(String viewerId) async {
    final tree = await _entities.readAllAsTree(viewerId);
    final stores = <Entity>[];
    for (final level in tree.values) {
      stores.addAll(level.where((e) => e.type == EntityType.STORE));
    }
    stores.sort((a, b) => a.meta.name.toLowerCase().compareTo(b.meta.name.toLowerCase()));
    return stores;
  }

  /// The AGENT1/AGENT2 points under [viewerId] that can parent a STORE, sorted by
  /// name. Used by HQ (which has no single implicit parent) to pick where a new
  /// POS point attaches.
  Future<List<Entity>> listParentAgents(String viewerId) async {
    final tree = await _entities.readAllAsTree(viewerId);
    final agents = <Entity>[];
    for (final level in tree.values) {
      agents.addAll(level.where((e) => e.type == EntityType.AGENT1 || e.type == EntityType.AGENT2));
    }
    agents.sort((a, b) => a.meta.name.toLowerCase().compareTo(b.meta.name.toLowerCase()));
    return agents;
  }

  Future<Entity> read(String id) => _entities.read(id);

  /// Create a new POS point (a single operator) under its parent agent.
  Future<Entity> createStore(Entity store) async {
    final created = await _entities.create(store, includeUsers: true);
    if (store.parent.isNotEmpty) {
      await _entities.relinkChildToParent(store.parent, created.id);
    }
    return created;
  }

  Future<Entity> update(Entity store) => _entities.updateWithUsers(store);

  Future<void> delete(String id) => _entities.delete(id);

  Future<void> setActive(String id, bool active) async {
    await _api.post(Endpoints.entitySetActive, params: {'id': id, 'active': active});
  }

  Future<void> resetPassword(String id, String phone, String newPassword) async {
    await _api.post(Endpoints.entityResetPassword,
        params: {'id': id, 'phone': phone, 'newPassword': newPassword});
  }

  Future<PosStats> posStats(String id) async {
    final r = await _api.get(Endpoints.entityPosStats, params: {'id': id});
    return _api.unwrap(r, (d) => PosStats.fromJson(d as Map<String, dynamic>));
  }
}
