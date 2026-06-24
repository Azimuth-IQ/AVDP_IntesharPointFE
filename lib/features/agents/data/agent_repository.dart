import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';

/// Data access for the HQ agent-management pages (Main Agents + Sub Agents).
/// Reuses the existing entity CRUD + the projected `GET /api/entity/summary` feed
/// (ADMIN-only) — no new backend endpoints. All writes go through
/// [EntityRepository], honoring its `includeUsers` / parent-relink quirks. The
/// backend additionally enforces HQ-only create/delete and the per-tier user
/// invariants, so this layer stays thin.
class AgentRepository {
  final ApiClient _api;
  late final EntityRepository _entities = EntityRepository(_api);

  AgentRepository(this._api);

  /// Paged list of agents of [type] ('AGENT1' | 'AGENT2'), optional name/id search.
  Future<Paged<EntitySummaryRow>> list(String type, {String? search, int page = 0, int size = 50}) async {
    final params = <String, dynamic>{'type': type, 'page': page, 'size': size};
    if (search != null && search.isNotEmpty) params['search'] = search;
    final r = await _api.get(Endpoints.entitySummary, params: params);
    return _api.unwrap(r, (d) => Paged.from(d, EntitySummaryRow.fromJson, size: size));
  }

  /// All agents of [type] in one shot (used to populate the parent-agent picker).
  Future<List<EntitySummaryRow>> listAll(String type) async {
    final res = await list(type, page: 0, size: 200);
    return res.items;
  }

  /// Full entity (with users, including hashed passwords) for the edit form.
  Future<Entity> read(String id) => _entities.read(id);

  /// Create an agent with its users, then restore the parent→child link.
  Future<Entity> create(Entity entity) async {
    final created = await _entities.create(entity, includeUsers: true);
    if (entity.parent.isNotEmpty) {
      await _entities.relinkChildToParent(entity.parent, created.id);
    }
    return created;
  }

  /// Update including users (existing users keep their hashed password).
  Future<Entity> update(Entity entity) => _entities.updateWithUsers(entity);

  Future<void> delete(String id) => _entities.delete(id);
}
