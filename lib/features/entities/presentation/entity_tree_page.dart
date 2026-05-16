import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

class EntityTreePage extends ConsumerStatefulWidget {
  const EntityTreePage({super.key});

  @override
  ConsumerState<EntityTreePage> createState() => _EntityTreePageState();
}

class _EntityTreePageState extends ConsumerState<EntityTreePage> {
  Map<int, List<Entity>>? _tree;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authStateProvider).valueOrNull;
      String? entityId;
      if (auth is AuthAuthenticated) {
        entityId = auth.entity.id;
      } else {
        entityId = await sessionStorage.getCurrentEntityId();
      }
      if (entityId == null) throw Exception('No entity id in session');

      final api = ref.read(apiClientProvider);
      final repo = EntityRepository(api);
      final tree = await repo.readAllAsTree(entityId);
      if (mounted) setState(() => _tree = tree);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final tree = _tree ?? {};
    if (tree.isEmpty) {
      return EmptyState(message: 'No children found', actionLabel: 'Refresh', onAction: _load);
    }

    // Flatten into a level-ordered list for display
    final depths = tree.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: depths.length,
        itemBuilder: (context, di) {
          final depth = depths[di];
          final entities = tree[depth] ?? [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (depth > 0) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Text(
                    depth == 0 ? 'Root' : 'Level $depth',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              ...entities.map((entity) => _EntityCard(entity: entity, indentLevel: depth, onRefresh: _load)),
            ],
          );
        },
      ),
    );
  }
}

class _EntityCard extends ConsumerWidget {
  final Entity entity;
  final int indentLevel;
  final VoidCallback onRefresh;

  const _EntityCard({required this.entity, required this.indentLevel, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.only(left: indentLevel * 16.0, bottom: 4),
      child: Card(
        child: ExpansionTile(
          leading: RoleBadge(type: entity.type),
          title: Text(entity.meta.name.isNotEmpty ? entity.meta.name : entity.id, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${entity.type.label} • ${entity.childrenIds.length} children • ${entity.productsIds.length} products', style: Theme.of(context).textTheme.bodySmall),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                onSelected: (action) => _handleAction(context, ref, action),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'), contentPadding: EdgeInsets.zero),
                  ),
                  const PopupMenuItem(
                    value: 'manage_users',
                    child: ListTile(leading: Icon(Icons.manage_accounts), title: Text('Manage Users'), contentPadding: EdgeInsets.zero),
                  ),
                  if (entity.type != EntityType.STORE)
                    const PopupMenuItem(
                      value: 'add_child',
                      child: ListTile(leading: Icon(Icons.add), title: Text('Add Child'), contentPadding: EdgeInsets.zero),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Delete', style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            if (entity.meta.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(alignment: Alignment.centerLeft, child: Text(entity.meta.description)),
              ),
            if (entity.meta.slogan.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('"${entity.meta.slogan}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('ID: ${entity.id}', style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, String action) async {
    if (action == 'edit') {
      await _showEditSheet(context, ref);
    } else if (action == 'manage_users') {
      await _showManageUsersSheet(context, ref);
    } else if (action == 'add_child') {
      await _showAddChildSheet(context, ref);
    } else if (action == 'delete') {
      await _confirmDelete(context, ref);
    }
  }

  Future<void> _showEditSheet(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController(text: entity.meta.name);
    final sloganCtrl = TextEditingController(text: entity.meta.slogan);
    final descCtrl = TextEditingController(text: entity.meta.description);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EntityFormSheet(
        title: 'Edit Entity',
        nameCtrl: nameCtrl,
        sloganCtrl: sloganCtrl,
        descCtrl: descCtrl,
        onSave: () async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);
          final updated = entity.copyWith(
            meta: entity.meta.copyWith(name: nameCtrl.text.trim(), slogan: sloganCtrl.text.trim(), description: descCtrl.text.trim()),
          );
          await repo.updateWithUsers(updated);
          // Backend bug: entity PUT removes entity from parent's childrenIds.
          if (entity.parent.isNotEmpty) {
            await repo.relinkChildToParent(entity.parent, entity.id);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  Future<void> _showManageUsersSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ManageUsersSheet(
        entity: entity,
        onSave: (updatedUsers) async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);
          final updated = entity.copyWith(users: updatedUsers);
          await repo.updateWithUsers(updated);
          // Backend bug: entity PUT may drop the entity from parent's childrenIds.
          if (entity.parent.isNotEmpty) {
            await repo.relinkChildToParent(entity.parent, entity.id);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  Future<void> _showAddChildSheet(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final sloganCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    // Determine allowed child types
    final childType = _childType(entity.type);
    if (childType == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EntityFormSheet(
        title: 'Add ${childType.label}',
        nameCtrl: nameCtrl,
        sloganCtrl: sloganCtrl,
        descCtrl: descCtrl,
        onSave: () async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);
          final child = Entity(
            id: '${childType.name.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch}',
            meta: EntityMeta(name: nameCtrl.text.trim(), slogan: sloganCtrl.text.trim(), description: descCtrl.text.trim()),
            parent: entity.id,
            type: childType,
          );
          await repo.create(child);
          await repo.relinkChildToParent(entity.id, child.id);
          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  EntityType? _childType(EntityType parent) {
    return switch (parent) {
      EntityType.INTESHAR => EntityType.AGENT1,
      EntityType.AGENT1 => EntityType.AGENT2,
      EntityType.AGENT2 => EntityType.STORE,
      EntityType.STORE => null,
    };
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entity'),
        content: Text('Delete "${entity.meta.name.isNotEmpty ? entity.meta.name : entity.id}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    final api = ref.read(apiClientProvider);
    final repo = EntityRepository(api);
    try {
      await repo.delete(entity.id);
      onRefresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

class _EntityFormSheet extends StatefulWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController sloganCtrl;
  final TextEditingController descCtrl;
  final Future<void> Function() onSave;

  const _EntityFormSheet({required this.title, required this.nameCtrl, required this.sloganCtrl, required this.descCtrl, required this.onSave});

  @override
  State<_EntityFormSheet> createState() => _EntityFormSheetState();
}

class _EntityFormSheetState extends State<_EntityFormSheet> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: widget.nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.sloganCtrl,
              decoration: const InputDecoration(labelText: 'Slogan'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        try {
                          await widget.onSave();
                        } catch (e) {
                          if (mounted) {
                            // ignore: use_build_context_synchronously
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
