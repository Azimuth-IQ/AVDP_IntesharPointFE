
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_form.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/features/entities/presentation/visible_products_sheet.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
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

/// Avatar-badge initial matching the CURRENT role names (B-080): HQ, Main Agent,
/// Sub Agent, POS/Store — was the stale G/D (Governorate/Distributor).
String _typeInitial(EntityType t) {
  switch (t) {
    case EntityType.INTESHAR:
      return 'H';
    case EntityType.AGENT1:
      return 'M';
    case EntityType.AGENT2:
      return 'S';
    case EntityType.STORE:
      return 'P';
  }
}

// ─── Page ────────────────────────────────────────────────────────────────────

class EntityTreePage extends ConsumerStatefulWidget {
  const EntityTreePage({super.key});

  @override
  ConsumerState<EntityTreePage> createState() => _EntityTreePageState();
}

class _EntityTreePageState extends ConsumerState<EntityTreePage> {
  EntitySummaryRow? _root;
  Object? _error;
  bool _loading = true;

  /// Ids currently expanded in the tree. Root is expanded by default.
  final Set<String> _expanded = {};

  // Lazy children cache (B-023): one `GET /api/entity/children` page per
  // expanded node instead of downloading the whole forest up front.
  final Map<String, List<EntitySummaryRow>> _children = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, int> _page = {};
  final Set<String> _loadingNodes = {};

  EntityRepository get _repo => EntityRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _expanded.clear();
      _children.clear();
      _hasMore.clear();
      _page.clear();
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

      // The root row comes from the full entity read (cheap: one document).
      final me = await _repo.read(entityId);
      final root = EntitySummaryRow(
        id: me.id,
        name: me.meta.name,
        type: me.type,
        childrenCount: me.childrenIds.length,
        productsCount: me.productsIds.length,
      );
      if (!mounted) return;
      setState(() {
        _root = root;
        _expanded.add(root.id); // root expanded by default
      });
      await _loadChildren(root.id);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChildren(String parentId, {bool more = false}) async {
    if (_loadingNodes.contains(parentId)) return;
    setState(() => _loadingNodes.add(parentId));
    try {
      final nextPage = more ? (_page[parentId] ?? 0) + 1 : 0;
      final res = await _repo.children(parentId, page: nextPage);
      if (!mounted) return;
      setState(() {
        final current = more ? (_children[parentId] ?? const []) : const <EntitySummaryRow>[];
        _children[parentId] = [...current, ...res.items];
        _hasMore[parentId] = res.hasMore;
        _page[parentId] = nextPage;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _loadingNodes.remove(parentId));
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
    if (_expanded.contains(id) && !_children.containsKey(id)) {
      _loadChildren(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading && _root == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final root = _root;
    if (root == null) {
      return EmptyState(
        message: l.entityTreeNoChildren,
        actionLabel: l.entityTreeRefresh,
        onAction: _load,
      );
    }

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
                      // Recursive tree rows (children fetched on expand)
                      _TreeSubtree(
                        node: root,
                        depth: 0,
                        expanded: _expanded,
                        childrenOf: _children,
                        hasMore: _hasMore,
                        loadingNodes: _loadingNodes,
                        onToggle: _toggle,
                        onLoadMore: (id) => _loadChildren(id, more: true),
                        onRefresh: _load,
                        visitedIds: {root.id},
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

/// Renders a node and — if expanded — its lazily-fetched children (B-023):
/// the first expand triggers `GET /api/entity/children` for that node; a
/// spinner row shows while the page loads and a "load more" row appears for
/// nodes with more children than one page.
class _TreeSubtree extends ConsumerWidget {
  final EntitySummaryRow node;
  final int depth;
  final Set<String> expanded;
  final Map<String, List<EntitySummaryRow>> childrenOf;
  final Map<String, bool> hasMore;
  final Set<String> loadingNodes;
  final void Function(String id) onToggle;
  final void Function(String id) onLoadMore;
  final VoidCallback onRefresh;
  // Cycle guard: ids already rendered on the current root-to-leaf path.
  final Set<String> visitedIds;

  const _TreeSubtree({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.childrenOf,
    required this.hasMore,
    required this.loadingNodes,
    required this.onToggle,
    required this.onLoadMore,
    required this.onRefresh,
    required this.visitedIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = childrenOf[node.id];
    // Leaf: stores never expand; other tiers rely on the server-computed count
    // (or, once loaded, the actual children list).
    final isLeaf = node.type == EntityType.STORE ||
        (loaded == null ? node.childrenCount == 0 : loaded.isEmpty);
    final isExpanded = expanded.contains(node.id);
    final isLoading = loadingNodes.contains(node.id);

    final rows = <Widget>[];

    // Node row
    rows.add(_TreeNode(
      entity: node,
      depth: depth,
      isLeaf: isLeaf,
      isExpanded: isExpanded,
      childCount: loaded?.length ?? node.childrenCount,
      onToggle: () => onToggle(node.id),
      onRefresh: onRefresh,
    ));

    // Children (only when expanded and not a leaf)
    if (!isLeaf && isExpanded) {
      if (loaded == null) {
        // First fetch for this node still in flight.
        rows.add(const Hairline());
        rows.add(Padding(
          padding: EdgeInsetsDirectional.only(start: 44.0 + depth * 24.0, top: 10, bottom: 10),
          child: const Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ));
      } else {
        for (final child in loaded) {
          // Cycle guard
          if (visitedIds.contains(child.id)) continue;
          rows.add(const Hairline());
          rows.add(_TreeSubtree(
            node: child,
            depth: depth + 1,
            expanded: expanded,
            childrenOf: childrenOf,
            hasMore: hasMore,
            loadingNodes: loadingNodes,
            onToggle: onToggle,
            onLoadMore: onLoadMore,
            onRefresh: onRefresh,
            visitedIds: {...visitedIds, child.id},
          ));
        }
        if (hasMore[node.id] == true) {
          rows.add(const Hairline());
          rows.add(Padding(
            padding: EdgeInsetsDirectional.only(start: 44.0 + depth * 24.0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton.icon(
                      onPressed: () => onLoadMore(node.id),
                      icon: const Icon(Icons.expand_more, size: 16),
                      label: Text(
                          Localizations.localeOf(context).languageCode == 'ar'
                              ? 'تحميل المزيد'
                              : 'Load more'),
                    ),
            ),
          ));
        }
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
  final EntitySummaryRow entity;
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
                    entity.label,
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
                Formatters.money(childCount),
                textAlign: TextAlign.center,
                style: IntesharType.mono(12, color: cs.onSurface),
              ),
            ),
            // Vouchers count (server-computed on the summary row)
            SizedBox(
              width: 64,
              child: Text(
                Formatters.money(entity.productsCount),
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
                // B-081: HQ picks which voucher definitions this account (and its
                // whole subtree) can see & sell. Not for the root itself.
                if (_viewerIsHq(ref) && entity.type != EntityType.INTESHAR)
                  PopupMenuItem(
                    value: 'visible_products',
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(Localizations.localeOf(context).languageCode == 'ar'
                          ? 'المنتجات المتاحة'
                          : 'Visible products'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                // Only offer "View inventory" on nodes that actually hold stock
                // (HQ→Main Agent). Sub Agents and Stores draw-on-print and hold no
                // cards, so the drill-in would always be empty (B-068).
                if (_inventoryRoutePrefix(ref) != null && entity.type.inventoryBacked)
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
    } else if (action == 'visible_products') {
      await showVisibleProductsSheet(context, entityId: entity.id, entityName: entity.name);
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
      '$prefix/entities/${entity.id}/inventory?name=${Uri.encodeComponent(entity.name)}',
    );
  }

  Future<void> _showEditSheet(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    // The tree rows are light projections — fetch the full document only when
    // an edit actually starts (B-023).
    final Entity full;
    try {
      full = await EntityRepository(ref.read(apiClientProvider)).read(entity.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.entityTreeErrorSaving)));
      }
      return;
    }
    if (!context.mounted) return;
    final nameCtrl = TextEditingController(text: full.meta.name);
    final sloganCtrl = TextEditingController(text: full.meta.slogan);
    final descCtrl = TextEditingController(text: full.meta.description);
    final logoCtrl = TextEditingController(text: full.meta.logoUrl);
    final backgroundCtrl =
        TextEditingController(text: full.meta.backgroundUrl);
    final primaryCtrl = TextEditingController(text: full.meta.primaryColor);
    final secondaryCtrl =
        TextEditingController(text: full.meta.secondaryColor);
    final thresholdCtrl = TextEditingController(
        text: full.meta.lowStockThreshold > 0
            ? full.meta.lowStockThreshold.toString()
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
        primaryCtrl: primaryCtrl,
        secondaryCtrl: secondaryCtrl,
        thresholdCtrl: thresholdCtrl,
        onSave: () async {
          final api = ref.read(apiClientProvider);
          final repo = EntityRepository(api);
          final updated = full.copyWith(
            meta: full.meta.copyWith(
              name: nameCtrl.text.trim(),
              slogan: sloganCtrl.text.trim(),
              description: descCtrl.text.trim(),
              logoUrl: logoCtrl.text.trim(),
              backgroundUrl: backgroundCtrl.text.trim(),
              primaryColor: primaryCtrl.text.trim(),
              secondaryColor: secondaryCtrl.text.trim(),
              lowStockThreshold: int.tryParse(thresholdCtrl.text.trim()) ?? 0,
            ),
          );
          await repo.updateWithUsers(updated);
          if (full.parent.isNotEmpty) {
            await repo.relinkChildToParent(full.parent, full.id);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          onRefresh();
        },
      ),
    );
  }

  Future<void> _showManageUsersSheet(
      BuildContext context, WidgetRef ref) async {
    // Users live on the full document, not the projected row (B-023).
    final Entity full;
    try {
      full = await EntityRepository(ref.read(apiClientProvider)).read(entity.id);
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ManageUsersSheet(
        entity: full,
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
          final originalByPhone = {for (final u in full.users) u.phone: u};
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
  /// tier. AGENT1/AGENT2 → the two-step [AgentForm]. POS shops are NOT created
  /// here (B-052): onboarding a POS consumes a quota slot via the نقاط البيع
  /// screen, so the STORE case is intentionally absent.
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
      // POS shops are quota-onboarded from the نقاط البيع screen, not the tree.
      EntityType.AGENT2 => null,
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
            entity.label)),
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

// ─── Slider gallery ──────────────────────────────────────────────────────────


// ─── Entity form sheet ───────────────────────────────────────────────────────

class _EntityFormSheet extends StatefulWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController sloganCtrl;
  final TextEditingController descCtrl;
  final TextEditingController logoCtrl;
  final TextEditingController backgroundCtrl;
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
  String? _nameError;
  String? _thresholdError;

  /// Validate before persisting: a blank name would leave the entity showing its
  /// raw id everywhere, and a non-numeric/negative threshold is meaningless (B-073).
  bool _validate(bool ar) {
    String? nameErr;
    String? thErr;
    if (widget.nameCtrl.text.trim().isEmpty) {
      nameErr = ar ? 'الاسم مطلوب' : 'Name is required';
    }
    final th = widget.thresholdCtrl.text.trim();
    if (th.isNotEmpty) {
      final n = int.tryParse(th);
      if (n == null || n < 0) thErr = ar ? 'أدخل رقمًا صحيحًا' : 'Enter a valid number';
    }
    setState(() {
      _nameError = nameErr;
      _thresholdError = thErr;
    });
    return nameErr == null && thErr == null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';

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
              decoration: InputDecoration(
                labelText: l.entityTreeFieldName,
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
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
                errorText: _thresholdError,
              ),
              onChanged: (_) {
                if (_thresholdError != null) setState(() => _thresholdError = null);
              },
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
                            if (!_validate(ar)) return;
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
