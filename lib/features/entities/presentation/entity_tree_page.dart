import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
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
import 'package:file_picker/file_picker.dart';
import 'package:inteshar/core/upload/upload_repository.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
import 'package:inteshar/shared/widgets/slider_image_crop_dialog.dart';
import 'package:inteshar/shared/widgets/color_hex_field.dart';
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
    EntityType.AGENT1 => '/agent1', // Main Agent browses descendant inventory (BRD)
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
                // Editing an entity + managing its users are HQ-only (BRD: only the
                // platform admin creates/assigns accounts). Enforced server-side; mirrored
                // here so non-HQ viewers get a read-only hierarchy and never hit a 403.
                if (_viewerIsHq(ref))
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(l.entityTreeEdit),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                if (_viewerIsHq(ref))
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
    final backgroundCtrl =
        TextEditingController(text: entity.meta.backgroundUrl);
    final sliderImagesNotifier = ValueNotifier<List<SliderImage>>(
        List<SliderImage>.from(entity.meta.effectiveSliderImages));
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
        backgroundCtrl: backgroundCtrl,
        sliderImagesNotifier: sliderImagesNotifier,
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
              backgroundUrl: backgroundCtrl.text.trim(),
              // Structured slider (order + active) is the source of truth; also mirror
              // the active URLs into the legacy flat list for any old reader.
              sliderImages: sliderImagesNotifier.value,
              sliderImagesUrl: sliderImagesNotifier.value
                  .where((s) => s.active && s.url.trim().isNotEmpty)
                  .map((s) => s.url)
                  .toList(),
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
        onResetPassword: (phone, newPass) async {
          await EntityRepository(ref.read(apiClientProvider))
              .resetPassword(entity.id, phone, newPass);
        },
        onResetTotp: (phone) async {
          await EntityRepository(ref.read(apiClientProvider)).resetUserTotp(phone);
        },
        onSave: (updatedUsers) async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);

          // Fine-grained diff: avoids the full-entity PUT that clears
          // childrenIds on the backend (EntityHelper.updateEntity bug).
          final originalByPhone = {for (final u in entity.users) u.phone: u};
          final updatedByPhone = {for (final u in updatedUsers) u.phone: u};

          // Remove users dropped from the sheet.
          for (final phone in originalByPhone.keys) {
            if (!updatedByPhone.containsKey(phone)) {
              await repo.removeUser(entity.id, phone);
            }
          }

          // Add new users; update existing ones whose role/capabilities changed.
          for (final u in updatedUsers) {
            final orig = originalByPhone[u.phone];
            if (orig == null) {
              // New user — ManageUsersSheet populates u.password from the form.
              await repo.addUser(
                entityId: entity.id,
                phone: u.phone,
                password: u.password,
                role: u.role,
                capabilities: u.capabilities,
              );
            } else if (orig.role != u.role ||
                orig.capabilities.length != u.capabilities.length ||
                !orig.capabilities.containsAll(u.capabilities)) {
              // Role or capabilities changed; password is not re-sent here
              // so the backend does not re-hash an already-hashed value.
              await repo.updateUser(
                phone: u.phone,
                role: u.role,
                capabilities: u.capabilities,
              );
            }
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

// ─── Slider gallery ──────────────────────────────────────────────────────────

/// HQ home-slider manager for [EntityMeta.sliderImages]. Each row = one uploaded
/// image with: an order badge (#1 = shown first), a drag/move up-down control,
/// an active toggle (hide without deleting), and remove. An add tile uploads a
/// new image (appended, active). The list order IS the display order.
class _SliderGallery extends ConsumerStatefulWidget {
  final ValueNotifier<List<SliderImage>> notifier;
  const _SliderGallery({required this.notifier});

  @override
  ConsumerState<_SliderGallery> createState() => _SliderGalleryState();
}

class _SliderGalleryState extends ConsumerState<_SliderGallery> {
  bool _uploading = false;
  String? _error;

  void _update(List<SliderImage> next) => widget.notifier.value = next;

  void _move(int from, int to) {
    final list = List<SliderImage>.from(widget.notifier.value);
    if (to < 0 || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    _update(list);
  }

  void _toggleActive(int idx) {
    final list = List<SliderImage>.from(widget.notifier.value);
    list[idx] = list[idx].copyWith(active: !list[idx].active);
    _update(list);
  }

  void _remove(int idx) {
    final list = List<SliderImage>.from(widget.notifier.value)..removeAt(idx);
    _update(list);
  }

  Future<void> _addImage() async {
    setState(() => _error = null);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open file picker: $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (mounted) setState(() => _error = 'Could not read file bytes');
      return;
    }
    // Spec: slider images are 16:9 and at most 1 MB — crop first, then the
    // dialog re-encodes to a capped JPEG ready for the slider-image kind.
    if (!mounted) return;
    final Uint8List? cropped;
    try {
      cropped = await showSliderImageCropDialog(context, bytes);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context));
      return;
    }
    if (cropped == null) return; // cancelled
    setState(() => _uploading = true);
    try {
      final repo = UploadRepository(ref.read(apiClientProvider));
      final url = await repo.uploadFile(cropped, 'slide.jpg', 'slider-image');
      if (mounted) {
        _update([...widget.notifier.value, SliderImage(url: url)]);
        setState(() => _uploading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = friendlyError(e, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isAr ? 'صور الشريط (نقاط البيع)' : 'Home slider images (POS)',
          style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          isAr
              ? 'اسحب لإعادة الترتيب — الأول يظهر أولاً. فعّل/عطّل لإظهار أو إخفاء صورة.'
              : 'Reorder to set what shows first; toggle to activate/hide without deleting.',
          style: IntesharType.sans(11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<SliderImage>>(
          valueListenable: widget.notifier,
          builder: (context, images, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (images.isNotEmpty)
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: images.length,
                    // CI's newer Flutter deprecates onReorder in favor of
                    // onReorderItem, which doesn't exist yet on the local
                    // 3.38.x toolchain — keep onReorder until both align.
                    // ignore: deprecated_member_use
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      _move(oldIndex, newIndex);
                    },
                    itemBuilder: (context, i) {
                      final img = images[i];
                      return _SliderRow(
                        key: ValueKey('${img.url}#$i'),
                        index: i,
                        total: images.length,
                        image: img,
                        onToggle: () => _toggleActive(i),
                        onRemove: () => _remove(i),
                        onUp: i > 0 ? () => _move(i, i - 1) : null,
                        onDown: i < images.length - 1 ? () => _move(i, i + 1) : null,
                      );
                    },
                  ),
                const SizedBox(height: 8),
                if (_uploading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _addImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: Text(isAr ? 'إضافة صورة' : 'Add image'),
                  ),
              ],
            );
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: IntesharType.sans(12, color: cs.error)),
        ],
      ],
    );
  }
}

/// One row in the slider manager: order badge, thumbnail, active switch, move
/// up/down + drag handle, and remove.
class _SliderRow extends StatelessWidget {
  final int index;
  final int total;
  final SliderImage image;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  const _SliderRow({
    required super.key,
    required this.index,
    required this.total,
    required this.image,
    required this.onToggle,
    required this.onRemove,
    required this.onUp,
    required this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dim = !image.active;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: IntesharColors.saffron, borderRadius: BorderRadius.circular(11)),
            child: Text('${index + 1}', style: IntesharType.mono(11, color: IntesharColors.ink, w: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: dim ? 0.4 : 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(IntesharRadii.sm),
              child: Image.network(
                image.url,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 52,
                  height: 52,
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.broken_image_outlined, size: 20, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Active toggle
          Expanded(
            child: Row(
              children: [
                Switch(value: image.active, onChanged: (_) => onToggle()),
                Flexible(
                  child: Text(
                    image.active
                        ? (Localizations.localeOf(context).languageCode == 'ar' ? 'مُفعّلة' : 'Active')
                        : (Localizations.localeOf(context).languageCode == 'ar' ? 'مخفية' : 'Hidden'),
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(11, color: cs.onSurfaceVariant, w: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up, size: 20),
            onPressed: onUp,
            tooltip: 'Up',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down, size: 20),
            onPressed: onDown,
            tooltip: 'Down',
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle, size: 20, color: cs.onSurfaceVariant),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: cs.error),
            onPressed: onRemove,
            tooltip: 'Remove',
          ),
        ],
      ),
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
  final TextEditingController backgroundCtrl;
  final ValueNotifier<List<SliderImage>> sliderImagesNotifier;
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
    required this.backgroundCtrl,
    required this.sliderImagesNotifier,
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
            ImageUploadField(
              value: widget.logoCtrl.text.isEmpty ? null : widget.logoCtrl.text,
              label: l.entityFieldLogoUrl,
              kind: 'agent-branding',
              onChanged: (u) => setState(() => widget.logoCtrl.text = u),
            ),
            const SizedBox(height: 12),
            ImageUploadField(
              value: widget.backgroundCtrl.text.isEmpty
                  ? null
                  : widget.backgroundCtrl.text,
              label: Localizations.localeOf(context).languageCode == 'ar'
                  ? 'صورة الخلفية'
                  : 'Background Image',
              kind: 'agent-branding',
              onChanged: (u) =>
                  setState(() => widget.backgroundCtrl.text = u),
            ),
            const SizedBox(height: 12),
            _SliderGallery(notifier: widget.sliderImagesNotifier),
            const SizedBox(height: 12),
            ColorHexField(
              controller: widget.primaryCtrl,
              label: l.entityFieldPrimaryColor,
            ),
            const SizedBox(height: 12),
            ColorHexField(
              controller: widget.secondaryCtrl,
              label: l.entityFieldSecondaryColor,
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
