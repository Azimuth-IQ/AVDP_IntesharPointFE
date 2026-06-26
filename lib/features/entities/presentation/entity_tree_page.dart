import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_form.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/features/stores/presentation/stores_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Inventory drill-in route prefix for the signed-in viewer, or null when the
/// role cannot browse another entity's inventory (only HQ + Distributor can).
String? _inventoryRoutePrefix(WidgetRef ref) {
  final viewer = ref.read(authStateProvider).valueOrNull;
  if (viewer is! AuthAuthenticated) return null;
  return switch (viewer.entity.type) {
    EntityType.INTESHAR => '/hq',
    EntityType.AGENT2 => '/agent2',
    _ => null,
  };
}

/// Whether the signed-in viewer is HQ (INTESHAR). Creating and deleting entities
/// is HQ-only per the BRD (enforced server-side too), so non-HQ viewers don't see
/// those actions.
bool _viewerIsHq(WidgetRef ref) {
  final viewer = ref.read(authStateProvider).valueOrNull;
  return viewer is AuthAuthenticated && viewer.entity.type == EntityType.INTESHAR;
}

String _localizedEntityTypeLabel(EntityType t, AppLocalizations l) {
  switch (t) {
    case EntityType.INTESHAR:
      return l.entityTypeInteshar;
    case EntityType.AGENT1:
      return l.entityTypeAgent1;
    case EntityType.AGENT2:
      return l.entityTypeAgent2;
    case EntityType.STORE:
      return l.entityTypeStore;
  }
}

/// Returns the single initial letter used in the avatar badge (H/G/D/S).
String _typeInitial(EntityType t) {
  switch (t) {
    case EntityType.INTESHAR:
      return 'H';
    case EntityType.AGENT1:
      return 'G';
    case EntityType.AGENT2:
      return 'D';
    case EntityType.STORE:
      return 'S';
  }
}

/// Parse a hex colour string (#RRGGBB) to a [Color], returning null on failure.
Color? _parseHex(String raw) {
  final clean = raw.trim().replaceAll('#', '');
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

// ─── Page ────────────────────────────────────────────────────────────────────

class EntityTreePage extends ConsumerStatefulWidget {
  const EntityTreePage({super.key});

  @override
  ConsumerState<EntityTreePage> createState() => _EntityTreePageState();
}

class _EntityTreePageState extends ConsumerState<EntityTreePage> {
  List<Entity>? _allEntities;
  String? _rootId;
  Object? _error;
  bool _loading = true;

  /// Ids currently expanded in the tree. Root is expanded by default.
  final Set<String> _expanded = {};

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
      final all = await repo.readAll();

      if (mounted) {
        setState(() {
          _allEntities = all;
          _rootId = entityId;
          _expanded.add(entityId!); // root expanded by default
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final all = _allEntities ?? [];
    final rootId = _rootId;
    if (rootId == null || all.isEmpty) {
      return EmptyState(
        message: l.entityTreeNoChildren,
        actionLabel: l.entityTreeRefresh,
        onAction: _load,
      );
    }

    // Find the root entity.
    final rootEntity = all.firstWhere(
      (e) => e.id == rootId,
      orElse: () => all.first,
    );

    // Build parent → children map (sorted by name).
    final childrenByParent = <String, List<Entity>>{};
    for (final e in all) {
      if (e.parent.isNotEmpty) {
        childrenByParent.putIfAbsent(e.parent, () => []).add(e);
      }
    }
    for (final list in childrenByParent.values) {
      list.sort((a, b) => a.meta.name.compareTo(b.meta.name));
    }

    final totalEntities = all.length;

    return MaxWidthBox(
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: PageHeader(
                eyebrow: l.navHierarchy,
                title: l.navHierarchy,
                subtitle: l.entityTreeSubtitle,
                trailing: _Tally(
                  l.entityTreeEntities,
                  totalEntities.toString(),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                child: InkCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Column header row
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                        child: _TableHeader(l: l),
                      ),
                      const Hairline(),
                      // Recursive tree rows
                      _TreeSubtree(
                        node: rootEntity,
                        childrenByParent: childrenByParent,
                        depth: 0,
                        expanded: _expanded,
                        onToggle: (id) => setState(() {
                          if (_expanded.contains(id)) {
                            _expanded.remove(id);
                          } else {
                            _expanded.add(id);
                          }
                        }),
                        onRefresh: _load,
                        isLast: true,
                        visitedIds: {rootEntity.id},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Table header ─────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final AppLocalizations l;
  const _TableHeader({required this.l});

  @override
  Widget build(BuildContext context) {
    final style = IntesharType.sans(11,
        color: IntesharColors.lichen, w: FontWeight.w700);
    return Row(
      children: [
        // Indent + expander space (24 px) + avatar (30 px) + gap (10 px)
        const SizedBox(width: 64),
        Expanded(child: Text(l.entityTreeColEntity, style: style)),
        SizedBox(
          width: 64,
          child: Text(l.entityTreeColChildren,
              textAlign: TextAlign.center, style: style),
        ),
        SizedBox(
          width: 64,
          child: Text(l.entityTreeColVouchers,
              textAlign: TextAlign.center, style: style),
        ),
        // Actions button placeholder width
        const SizedBox(width: 40),
      ],
    );
  }
}

// ─── Recursive subtree ───────────────────────────────────────────────────────

/// Renders a node and — if expanded — all of its children recursively.
class _TreeSubtree extends ConsumerWidget {
  final Entity node;
  final Map<String, List<Entity>> childrenByParent;
  final int depth;
  final Set<String> expanded;
  final void Function(String id) onToggle;
  final VoidCallback onRefresh;
  final bool isLast;
  // Cycle guard: ids already rendered on the current root-to-leaf path.
  final Set<String> visitedIds;

  const _TreeSubtree({
    required this.node,
    required this.childrenByParent,
    required this.depth,
    required this.expanded,
    required this.onToggle,
    required this.onRefresh,
    required this.isLast,
    required this.visitedIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = childrenByParent[node.id] ?? [];
    final isLeaf = children.isEmpty || node.type == EntityType.STORE;
    final isExpanded = expanded.contains(node.id);

    final rows = <Widget>[];

    // Node row
    rows.add(_TreeNode(
      entity: node,
      depth: depth,
      isLeaf: isLeaf,
      isExpanded: isExpanded,
      childCount: children.length,
      onToggle: () => onToggle(node.id),
      onRefresh: onRefresh,
    ));

    // Children (only when expanded and not a leaf)
    if (!isLeaf && isExpanded) {
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        // Cycle guard
        if (visitedIds.contains(child.id)) continue;
        rows.add(const Hairline());
        rows.add(_TreeSubtree(
          node: child,
          childrenByParent: childrenByParent,
          depth: depth + 1,
          expanded: expanded,
          onToggle: onToggle,
          onRefresh: onRefresh,
          isLast: i == children.length - 1,
          visitedIds: {...visitedIds, child.id},
        ));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

// ─── Single tree row ─────────────────────────────────────────────────────────

class _TreeNode extends ConsumerWidget {
  final Entity entity;
  final int depth;
  final bool isLeaf;
  final bool isExpanded;
  final int childCount;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;

  const _TreeNode({
    required this.entity,
    required this.depth,
    required this.isLeaf,
    required this.isExpanded,
    required this.childCount,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final roleColor = RoleBadge.colorFor(context, entity.type);

    final startPad = 12.0 + depth * 24.0;

    return InkWell(
      onTap: isLeaf ? null : onToggle,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: startPad,
          end: 4,
          top: 10,
          bottom: 10,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Expander chevron or blank spacer
            SizedBox(
              width: 20,
              height: 20,
              child: isLeaf
                  ? null
                  : AnimatedRotation(
                      duration: const Duration(milliseconds: 200),
                      turns: isExpanded ? 0.25 : 0,
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            // Type avatar (30 × 30 rounded square)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Text(
                _typeInitial(entity.type),
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: roleColor,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Name + type label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entity.meta.name.isNotEmpty ? entity.meta.name : entity.id,
                    style: IntesharType.sans(13,
                        color: cs.onSurface, w: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _localizedEntityTypeLabel(entity.type, l),
                    style: IntesharType.sans(11,
                        color: IntesharColors.lichen),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Children count
            SizedBox(
              width: 64,
              child: Text(
                childCount.toString(),
                textAlign: TextAlign.center,
                style: IntesharType.mono(12, color: cs.onSurface),
              ),
            ),
            // Vouchers count
            SizedBox(
              width: 64,
              child: Text(
                entity.productsIds.length.toString(),
                textAlign: TextAlign.center,
                style: IntesharType.mono(12, color: cs.onSurface),
              ),
            ),
            // Actions menu
            PopupMenuButton<String>(
              tooltip: l.entityTreeActions,
              icon: Icon(Icons.more_horiz, size: 18, color: cs.onSurfaceVariant),
              onSelected: (action) =>
                  _handleAction(context, ref, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(l.entityTreeEdit),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'manage_users',
                  child: ListTile(
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: Text(l.entityTreeManageUsers),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (_inventoryRoutePrefix(ref) != null)
                  PopupMenuItem(
                    value: 'view_inventory',
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(l.navInventory),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                // Creating accounts / assigning agents is HQ-only (BRD); enforced
                // server-side, mirrored here so non-HQ viewers don't see dead actions.
                if (_viewerIsHq(ref) && entity.type != EntityType.STORE)
                  PopupMenuItem(
                    value: 'add_child',
                    child: ListTile(
                      leading: const Icon(Icons.add),
                      title: Text(l.entityTreeAddChild),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (_viewerIsHq(ref))
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline,
                          color: Colors.red),
                      title: Text(l.entityTreeDelete,
                          style: const TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    if (action == 'edit') {
      await _showEditSheet(context, ref);
    } else if (action == 'manage_users') {
      await _showManageUsersSheet(context, ref);
    } else if (action == 'view_inventory') {
      _viewInventory(context, ref);
    } else if (action == 'add_child') {
      await _addChild(context, ref);
    } else if (action == 'delete') {
      await _confirmDelete(context, ref);
    }
  }

  void _viewInventory(BuildContext context, WidgetRef ref) {
    final prefix = _inventoryRoutePrefix(ref);
    if (prefix == null) return;
    context.push(
      '$prefix/entities/${entity.id}/inventory?name=${Uri.encodeComponent(entity.meta.name)}',
    );
  }

  Future<void> _showEditSheet(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: entity.meta.name);
    final sloganCtrl = TextEditingController(text: entity.meta.slogan);
    final descCtrl = TextEditingController(text: entity.meta.description);
    final logoCtrl = TextEditingController(text: entity.meta.logoUrl);
    final primaryCtrl = TextEditingController(text: entity.meta.primaryColor);
    final secondaryCtrl =
        TextEditingController(text: entity.meta.secondaryColor);
    final thresholdCtrl = TextEditingController(
        text: entity.meta.lowStockThreshold > 0
            ? entity.meta.lowStockThreshold.toString()
            : '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EntityFormSheet(
        title: l.entityTreeAmendTitle(
            _localizedEntityTypeLabel(entity.type, l)),
        nameCtrl: nameCtrl,
        sloganCtrl: sloganCtrl,
        descCtrl: descCtrl,
        logoCtrl: logoCtrl,
        primaryCtrl: primaryCtrl,
        secondaryCtrl: secondaryCtrl,
        thresholdCtrl: thresholdCtrl,
        onSave: () async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);
          final updated = entity.copyWith(
            meta: entity.meta.copyWith(
              name: nameCtrl.text.trim(),
              slogan: sloganCtrl.text.trim(),
              description: descCtrl.text.trim(),
              logoUrl: logoCtrl.text.trim(),
              primaryColor: primaryCtrl.text.trim(),
              secondaryColor: secondaryCtrl.text.trim(),
              lowStockThreshold: int.tryParse(thresholdCtrl.text.trim()) ?? 0,
            ),
          );
          await repo.updateWithUsers(updated);
          if (entity.parent.isNotEmpty) {
            await repo.relinkChildToParent(entity.parent, entity.id);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  Future<void> _showManageUsersSheet(
      BuildContext context, WidgetRef ref) async {
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
          if (entity.parent.isNotEmpty) {
            await repo.relinkChildToParent(entity.parent, entity.id);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  /// Routes "Add child" to the proper validated onboarding form for the child
  /// tier instead of the bare meta-only sheet (which produced user-less,
  /// region-less, non-functional entities). AGENT1/AGENT2 → the two-step
  /// [AgentForm]; STORE → [StoreForm]. Refreshes the tree on a successful save.
  Future<void> _addChild(BuildContext context, WidgetRef ref) async {
    final childType = _childType(entity.type);
    if (childType == null) return;

    Widget page;
    switch (childType) {
      case EntityType.AGENT1:
        page = const AgentForm(tier: AgentTier.main);
      case EntityType.AGENT2:
        page = const AgentForm(tier: AgentTier.sub);
      case EntityType.STORE:
        page = StoreForm(parentId: entity.id);
      case EntityType.INTESHAR:
        return;
    }

    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => page),
    );
    if (ok == true) onRefresh();
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
    final l = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.entityTreeDeleteTitle),
        content: Text(l.entityTreeDeleteConfirm(
            entity.meta.name.isNotEmpty ? entity.meta.name : entity.id)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.entityTreeCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(l.entityTreeDelete),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.entityTreeDeleteFailed)));
      }
    }
  }
}

// ─── Tally chip ──────────────────────────────────────────────────────────────

class _Tally extends StatelessWidget {
  final String label;
  final String value;
  const _Tally(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: IntesharColors.saffron.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: IntesharColors.saffronDeep,
              height: 1,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label.toLowerCase(),
            style: const TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: IntesharColors.saffronDeep,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Colour swatch suffix ────────────────────────────────────────────────────

class _HexSwatch extends StatelessWidget {
  final TextEditingController ctrl;
  const _HexSwatch({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final color = _parseHex(ctrl.text);
        if (color == null) return const SizedBox(width: 24, height: 24);
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
              width: 1,
            ),
          ),
        );
      },
    );
  }
}

// ─── Entity form sheet ───────────────────────────────────────────────────────

class _EntityFormSheet extends StatefulWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController sloganCtrl;
  final TextEditingController descCtrl;
  final TextEditingController logoCtrl;
  final TextEditingController primaryCtrl;
  final TextEditingController secondaryCtrl;
  final TextEditingController thresholdCtrl;
  final Future<void> Function() onSave;

  const _EntityFormSheet({
    required this.title,
    required this.nameCtrl,
    required this.sloganCtrl,
    required this.descCtrl,
    required this.logoCtrl,
    required this.primaryCtrl,
    required this.secondaryCtrl,
    required this.thresholdCtrl,
    required this.onSave,
  });

  @override
  State<_EntityFormSheet> createState() => _EntityFormSheetState();
}

class _EntityFormSheetState extends State<_EntityFormSheet> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel(l.entityTreeSectionLabel),
            Text(widget.title,
                style: IntesharType.display(28, color: cs.onSurface)),
            const SizedBox(height: 20),

            // ── Core fields ──────────────────────────────────────────────
            TextField(
              controller: widget.nameCtrl,
              decoration:
                  InputDecoration(labelText: l.entityTreeFieldName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.sloganCtrl,
              decoration:
                  InputDecoration(labelText: l.entityTreeFieldSlogan),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.descCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: l.entityTreeFieldDescription),
            ),
            const SizedBox(height: 12),

            // ── New brand fields ─────────────────────────────────────────
            TextField(
              controller: widget.logoCtrl,
              decoration:
                  InputDecoration(labelText: l.entityFieldLogoUrl),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.primaryCtrl,
              decoration: InputDecoration(
                labelText: l.entityFieldPrimaryColor,
                suffix: _HexSwatch(ctrl: widget.primaryCtrl),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.secondaryCtrl,
              decoration: InputDecoration(
                labelText: l.entityFieldSecondaryColor,
                suffix: _HexSwatch(ctrl: widget.secondaryCtrl),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.thresholdCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.entityFieldLowStockThreshold,
                hintText: EntityMeta.defaultLowStockThreshold.toString(),
                helperText: l.entityFieldLowStockThresholdHelp,
              ),
            ),
            const SizedBox(height: 20),

            // ── Action buttons ───────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
                    child: Text(l.entityTreeCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text(l.entityTreeErrorSaving)),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2))
                        : Text(l.entityTreeSave),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
