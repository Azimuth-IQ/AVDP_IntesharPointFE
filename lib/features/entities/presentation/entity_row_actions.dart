import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_detail_page.dart';
import 'package:inteshar/features/agents/presentation/agent_form.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/confirm_code_dialog.dart';
import 'package:inteshar/features/entities/presentation/delete_agent_sheet.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/features/entities/presentation/visible_products_sheet.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/color_hex_field.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';

// ─── UX-93: one action set for one object ────────────────────────────────────
//
// HQ lists the same `Entity` objects on four surfaces — the hierarchy tree, the
// Main Agents page, the Sub Agents page, and System Activity's Entities tab —
// and each grew its OWN row menu. The tree could manage users, drill into stock
// and add a child; the tier directories could not, and neither said the other
// existed. "Where do I change X on this agent?" therefore had no learnable
// answer: it depended entirely on which of four doors the admin walked in
// through.
//
// Everything below is that menu, defined once. The tree's menu was the richest,
// so it is the canon; the tier pages and the oversight tab now render THIS and
// nothing of their own. A capability that hides an item hides it everywhere,
// which is the property the four private copies could never have.

/// Where the viewer may browse another entity's stock from, or null when the
/// role cannot (only HQ, Main Agent and Sub Agent can).
String? inventoryRoutePrefix(WidgetRef ref) {
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
bool viewerIsHq(WidgetRef ref) {
  final viewer = ref.read(authStateProvider).valueOrNull;
  return viewer is AuthAuthenticated && viewer.entity.type == EntityType.INTESHAR;
}

/// Whether the viewer may MUTATE entities: HQ **and** holding
/// [Capability.MANAGE_AGENTS].
///
/// Being HQ is necessary but not sufficient. The nav item leading to the
/// hierarchy is gated on `VIEW_REPORTS`, so an HQ supervisor holding only that
/// capability reaches the tree while the Main/Sub Agent pages (`MANAGE_AGENTS`)
/// stay hidden from them. Gating a row menu on entity TYPE alone then handed
/// that same supervisor edit, manage-users, visible-products, add-child and
/// delete — the capability model bypassed by a type check, with the most
/// destructive action in the app as the escape route.
///
/// The server enforces this independently; the point here is not to offer an
/// action the backend will refuse, and above all not to offer destruction to
/// someone the capability model deliberately excluded.
bool viewerCanManageEntities(WidgetRef ref) {
  final viewer = ref.read(authStateProvider).valueOrNull;
  return viewer is AuthAuthenticated &&
      viewer.entity.type == EntityType.INTESHAR &&
      viewer.can({Capability.MANAGE_AGENTS});
}

/// Whether [type] has an agent detail page to open.
bool entityHasDetailPage(EntityType type) =>
    type == EntityType.AGENT1 || type == EntityType.AGENT2;

AgentTier? agentTierOf(EntityType type) => switch (type) {
      EntityType.AGENT1 => AgentTier.main,
      EntityType.AGENT2 => AgentTier.sub,
      EntityType.INTESHAR || EntityType.STORE => null,
    };

/// The child tier an "Add child" creates, or null where the tree does not
/// onboard (a POS shop consumes a quota slot on the نقاط البيع screen instead).
EntityType? childTypeOf(EntityType parent) => switch (parent) {
      EntityType.INTESHAR => EntityType.AGENT1,
      EntityType.AGENT1 => EntityType.AGENT2,
      EntityType.AGENT2 => null,
      EntityType.STORE => null,
    };

enum EntityRowAction { open, edit, manageUsers, visibleProducts, viewInventory, addChild, delete }

/// The canonical row menu. Renders nothing at all when this viewer has no action
/// on this row, rather than a button that opens onto an empty list.
///
/// [onChanged] fires after anything that could have changed the row — the caller
/// re-fetches whatever list it is showing.
class EntityRowActionsButton extends ConsumerWidget {
  final EntitySummaryRow row;
  final VoidCallback onChanged;

  /// Set on a surface that IS the detail page (or that already opens it on tap),
  /// so the menu does not offer a hop to where the operator already is.
  final bool showOpen;

  final double iconSize;

  const EntityRowActionsButton({
    super.key,
    required this.row,
    required this.onChanged,
    this.showOpen = true,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';

    final items = availableActions(ref, row, showOpen: showOpen);
    if (items.isEmpty) return const SizedBox(width: 40);

    return PopupMenuButton<EntityRowAction>(
      tooltip: l.entityTreeActions,
      icon: Icon(Icons.more_horiz, size: iconSize, color: cs.onSurfaceVariant),
      onSelected: (a) => runEntityRowAction(context, ref, a, row, onChanged: onChanged),
      itemBuilder: (_) => [
        for (final a in items)
          PopupMenuItem(
            value: a,
            child: ListTile(
              leading: Icon(
                _iconFor(a),
                color: a == EntityRowAction.delete ? context.status.danger : null,
              ),
              title: Text(
                _labelFor(a, l, ar),
                style: a == EntityRowAction.delete
                    ? TextStyle(color: context.status.danger)
                    : null,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}

/// Which of the canonical actions this viewer may take on this row. Same answer
/// on every surface — that is the whole point of UX-93.
List<EntityRowAction> availableActions(
  WidgetRef ref,
  EntitySummaryRow row, {
  bool showOpen = true,
}) {
  final canManage = viewerCanManageEntities(ref);
  // Only HQ and Main Agents ever own a `Product` under draw-on-print, so the
  // drill-in below that tier would always land on an empty warehouse (B-068).
  final canDrillIn = inventoryRoutePrefix(ref) != null && row.type.inventoryBacked;

  return [
    if (showOpen && entityHasDetailPage(row.type)) EntityRowAction.open,
    if (canManage) EntityRowAction.edit,
    if (canManage) EntityRowAction.manageUsers,
    // B-081: which voucher definitions this account (and its whole subtree) may
    // see and sell. Meaningless on the root itself.
    if (canManage && row.type != EntityType.INTESHAR) EntityRowAction.visibleProducts,
    if (canDrillIn) EntityRowAction.viewInventory,
    if (canManage && childTypeOf(row.type) != null) EntityRowAction.addChild,
    // The platform root is never deletable. On 2026-08-25 an operator cleared the
    // tree bottom-up and finished on `inteshar-root`; the server accepted it, and
    // with no entity left holding anyone's phone, nobody could authenticate and
    // no account existed that could create one — recovery needed database access.
    // The server refuses this now; the menu should not offer it either.
    if (canManage && row.type != EntityType.INTESHAR) EntityRowAction.delete,
  ];
}

IconData _iconFor(EntityRowAction a) => switch (a) {
      EntityRowAction.open => Icons.open_in_new,
      EntityRowAction.edit => Icons.edit_outlined,
      EntityRowAction.manageUsers => Icons.manage_accounts_outlined,
      EntityRowAction.visibleProducts => Icons.inventory_2_outlined,
      EntityRowAction.viewInventory => Icons.style_outlined,
      EntityRowAction.addChild => Icons.add,
      EntityRowAction.delete => Icons.delete_outline,
    };

String _labelFor(EntityRowAction a, AppLocalizations l, bool ar) => switch (a) {
      EntityRowAction.open => ar ? 'فتح ملف الوكيل' : 'Open agent',
      EntityRowAction.edit => l.entityTreeEdit,
      EntityRowAction.manageUsers => l.entityTreeManageUsers,
      EntityRowAction.visibleProducts => ar ? 'المنتجات المتاحة' : 'Visible products',
      // UX-104: the SAME stock screen grants different powers depending on how it
      // was reached — HQ can withdraw from the `/hq/inventory` dropdown but not
      // from this drill-in, and nothing on either said which mode you were in.
      // Until the two entry points are actually reconciled (a change inside
      // `inventory_page.dart`), the door at least states what is behind it.
      EntityRowAction.viewInventory =>
        ar ? '${l.navInventory} (عرض فقط)' : '${l.navInventory} (view only)',
      EntityRowAction.addChild => l.entityTreeAddChild,
      EntityRowAction.delete => l.entityTreeDelete,
    };

/// Runs one canonical action. Every surface calls THIS — a fix or a new
/// safeguard lands on all four at once.
Future<void> runEntityRowAction(
  BuildContext context,
  WidgetRef ref,
  EntityRowAction action,
  EntitySummaryRow row, {
  required VoidCallback onChanged,
}) async {
  switch (action) {
    case EntityRowAction.open:
      await openAgentDetail(context, row.id, row.label, onChanged: onChanged);
    case EntityRowAction.edit:
      await showEntityEditor(context, ref, row, onChanged: onChanged);
    case EntityRowAction.manageUsers:
      await showEntityUsersSheet(context, ref, row, onChanged: onChanged);
    case EntityRowAction.visibleProducts:
      // UX-159: the sheet writes, so it reports whether it wrote and the caller
      // refreshes — the same contract every other mutating sheet here follows.
      final changed = await showVisibleProductsSheet(
        context,
        entityId: row.id,
        entityName: row.label,
      );
      if (changed) onChanged();
    case EntityRowAction.viewInventory:
      final prefix = inventoryRoutePrefix(ref);
      if (prefix == null) return;
      context.push(
        '$prefix/entities/${row.id}/inventory?name=${Uri.encodeComponent(row.name)}',
      );
    case EntityRowAction.addChild:
      await _addChild(context, row, onChanged: onChanged);
    case EntityRowAction.delete:
      final deleted = await showDeleteAgentSheet(
        context,
        ref,
        entityId: row.id,
        entityName: row.label,
      );
      if (deleted) onChanged();
  }
}

/// Pushes the per-agent detail page. Not a GoRoute: registering one lives in
/// `lib/app/router.dart`, so this is pushed the same way [AgentForm] is.
/// Follow-up: give it `/hq/agents/:id` so it can be linked to and deep-linked.
Future<void> openAgentDetail(
  BuildContext context,
  String entityId,
  String entityName, {
  VoidCallback? onChanged,
}) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AgentDetailPage(entityId: entityId, entityName: entityName),
    ),
  );
  if (changed == true) onChanged?.call();
}

/// Routes "Add child" to the proper validated onboarding form for the child
/// tier. POS shops are NOT created here (B-052): onboarding a POS consumes a
/// quota slot via the نقاط البيع screen.
Future<void> _addChild(
  BuildContext context,
  EntitySummaryRow row, {
  required VoidCallback onChanged,
}) async {
  final childTier = agentTierOf(childTypeOf(row.type) ?? row.type);
  if (childTier == null) return;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => AgentForm(tier: childTier)),
  );
  if (ok == true) onChanged();
}

// ─── Edit ────────────────────────────────────────────────────────────────────

/// Opens the ONE editor for [row].
///
/// UX-03: an agent has a single editor. The tree's own sheet and [AgentForm]
/// both edited the same account with disjoint field sets — the form owned
/// governorates, working hours, KYC and the capability ceiling; the sheet owned
/// slogan, description, low-stock and the bulk limits — and neither mentioned
/// the other. Those have moved into the form, so Main/Sub Agents open it from
/// every surface. HQ itself and shops have no agent form (a shop is onboarded
/// through the POS quota flow), so they keep the meta sheet.
Future<void> showEntityEditor(
  BuildContext context,
  WidgetRef ref,
  EntitySummaryRow row, {
  required VoidCallback onChanged,
}) async {
  final l = AppLocalizations.of(context)!;
  // The rows are light projections — fetch the full document only when an edit
  // actually starts (B-023).
  final Entity full;
  try {
    full = await EntityRepository(ref.read(apiClientProvider)).read(row.id);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
    return;
  }
  if (!context.mounted) return;

  final tier = agentTierOf(full.type);
  if (tier != null) {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AgentForm(tier: tier, existing: full)),
    );
    if (saved == true) onChanged();
    return;
  }

  await showEntityMetaSheet(
    context,
    ref,
    full,
    title: l.entityTreeAmendTitle(localizedEntityTypeLabel(full.type, l)),
    onChanged: onChanged,
  );
}

String localizedEntityTypeLabel(EntityType t, AppLocalizations l) => switch (t) {
      EntityType.INTESHAR => l.entityTypeInteshar,
      EntityType.AGENT1 => l.entityTypeAgent1,
      EntityType.AGENT2 => l.entityTypeAgent2,
      EntityType.STORE => l.entityTypeStore,
    };

/// Branding + operational limits for the tiers with no [AgentForm] (HQ, shops).
Future<void> showEntityMetaSheet(
  BuildContext context,
  WidgetRef ref,
  Entity full, {
  required String title,
  required VoidCallback onChanged,
}) async {
  final nameCtrl = TextEditingController(text: full.meta.name);
  final sloganCtrl = TextEditingController(text: full.meta.slogan);
  final descCtrl = TextEditingController(text: full.meta.description);
  final logoCtrl = TextEditingController(text: full.meta.logoUrl);
  final backgroundCtrl = TextEditingController(text: full.meta.backgroundUrl);
  final primaryCtrl = TextEditingController(text: full.meta.primaryColor);
  final secondaryCtrl = TextEditingController(text: full.meta.secondaryColor);
  final thresholdCtrl = TextEditingController(
      text: full.meta.lowStockThreshold > 0 ? full.meta.lowStockThreshold.toString() : '');
  // B-086: per-request bulk card limit + whether this account may manage limits.
  final bulkCtrl = TextEditingController(
      text: full.meta.maxBulkPrint > 0 ? full.meta.maxBulkPrint.toString() : '');
  var bulkLocked = full.meta.bulkLimitLocked;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => EntityMetaFormSheet(
      title: title,
      nameCtrl: nameCtrl,
      sloganCtrl: sloganCtrl,
      descCtrl: descCtrl,
      logoCtrl: logoCtrl,
      backgroundCtrl: backgroundCtrl,
      primaryCtrl: primaryCtrl,
      secondaryCtrl: secondaryCtrl,
      thresholdCtrl: thresholdCtrl,
      bulkCtrl: bulkCtrl,
      // Only HQ may delegate/revoke limit management (server-enforced too).
      showBulkLock: viewerIsHq(ref),
      bulkLocked: bulkLocked,
      onBulkLockChanged: (v) => bulkLocked = v,
      onSave: () async {
        final repo = EntityRepository(ref.read(apiClientProvider));
        // NOTE (C-10): this is a read-back entity going back out through a
        // whole-document PUT. It survives only because `password`/`totpSecret`/
        // `posPin` are restored server-side BY PHONE and nothing here can change
        // a phone. Do not add a user-editing field to this sheet.
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
            maxBulkPrint: int.tryParse(bulkCtrl.text.trim()) ?? 0,
            bulkLimitLocked: bulkLocked,
          ),
        );
        await repo.updateWithUsers(updated);
        if (ctx.mounted) Navigator.pop(ctx);
        onChanged();
      },
    ),
  );
}

// ─── Manage users ────────────────────────────────────────────────────────────

Future<void> showEntityUsersSheet(
  BuildContext context,
  WidgetRef ref,
  EntitySummaryRow row, {
  required VoidCallback onChanged,
}) async {
  // Users live on the full document, not the projected row (B-023).
  final Entity full;
  try {
    full = await EntityRepository(ref.read(apiClientProvider)).read(row.id);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
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
            .resetPassword(row.id, phone, newPass);
      },
      onResetTotp: (phone) async {
        await EntityRepository(ref.read(apiClientProvider)).resetUserTotp(phone);
      },
      onSave: (updatedUsers) async {
        final repo = EntityRepository(ref.read(apiClientProvider));

        // Fine-grained diff: avoids the full-entity PUT that clears childrenIds
        // on the backend (EntityHelper.updateEntity bug) — and, more to the
        // point, never round-trips a read-back user object (C-10).
        // UX-156: liveUsers — an archived user is not in the sheet's list, so
        // diffing against the raw array would call archive on it a second time.
        final originalByPhone = {for (final u in full.liveUsers) u.phone: u};
        final updatedByPhone = {for (final u in updatedUsers) u.phone: u};

        // UX-156: archiving takes someone's login away, so the server demands
        // the caller's own authenticator code — the same step-up as a POS
        // revoke. Asked ONCE for the whole batch, and asked BEFORE any mutation
        // runs: the adds and role edits below are already applied one call at a
        // time, so prompting mid-loop would leave the roster half-changed if
        // the operator backed out.
        final going = originalByPhone.keys
            .where((phone) => !updatedByPhone.containsKey(phone))
            .toList();
        String? code;
        if (going.isNotEmpty) {
          if (!ctx.mounted) return;
          final ar = Localizations.localeOf(ctx).languageCode == 'ar';
          code = await showConfirmCodeDialog(
            ctx,
            title: ar ? 'تأكيد الأرشفة' : 'Confirm archiving',
            warning: going.length == 1
                ? (ar
                    ? 'سيتم إيقاف دخول ${going.first} ونقله إلى الأرشيف. يمكن إرجاعه لاحقاً.'
                    : '${going.first} will be signed out and moved to the archive. They can be restored later.')
                : (ar
                    ? '${arArchiveUsersCount(going.length)}: سيتم إيقاف دخولهم ونقلهم إلى الأرشيف. يمكن إرجاعهم لاحقاً.'
                    : '${going.length} users will be signed out and moved to the archive. They can be restored later.'),
            confirmLabel: ar ? 'أرشفة' : 'Archive',
          );
          if (code == null) return;
        }

        for (final phone in going) {
          await repo.archiveUser(row.id, phone, totp: code);
        }

        for (final u in updatedUsers) {
          final orig = originalByPhone[u.phone];
          if (orig == null) {
            // New user — ManageUsersSheet populates u.password from the form.
            await repo.addUser(
              entityId: row.id,
              phone: u.phone,
              password: u.password,
              role: u.role,
              capabilities: u.capabilities,
            );
          } else if (orig.role != u.role ||
              orig.capabilities.length != u.capabilities.length ||
              !orig.capabilities.containsAll(u.capabilities)) {
            // Role or capabilities only; the password is deliberately not
            // re-sent so the backend does not re-hash an already-hashed value.
            await repo.updateUser(
              phone: u.phone,
              role: u.role,
              capabilities: u.capabilities,
            );
          }
        }

        if (ctx.mounted) Navigator.pop(ctx);
        onChanged();
      },
    ),
  );
}

// ─── Entity meta form sheet ──────────────────────────────────────────────────

class EntityMetaFormSheet extends StatefulWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController sloganCtrl;
  final TextEditingController descCtrl;
  final TextEditingController logoCtrl;
  final TextEditingController backgroundCtrl;
  final TextEditingController primaryCtrl;
  final TextEditingController secondaryCtrl;
  final TextEditingController thresholdCtrl;
  final TextEditingController bulkCtrl;
  final bool showBulkLock;
  final bool bulkLocked;
  final ValueChanged<bool> onBulkLockChanged;
  final Future<void> Function() onSave;

  const EntityMetaFormSheet({
    super.key,
    required this.title,
    required this.nameCtrl,
    required this.sloganCtrl,
    required this.descCtrl,
    required this.logoCtrl,
    required this.backgroundCtrl,
    required this.primaryCtrl,
    required this.secondaryCtrl,
    required this.thresholdCtrl,
    required this.bulkCtrl,
    this.showBulkLock = false,
    this.bulkLocked = true,
    required this.onBulkLockChanged,
    required this.onSave,
  });

  @override
  State<EntityMetaFormSheet> createState() => _EntityMetaFormSheetState();
}

class _EntityMetaFormSheetState extends State<EntityMetaFormSheet> {
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
                    color: cs.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel(l.entityTreeSectionLabel),
            Text(widget.title, style: IntesharType.display(28, color: cs.onSurface)),
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
              decoration: InputDecoration(labelText: l.entityTreeFieldSlogan),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.descCtrl,
              maxLines: 3,
              decoration: InputDecoration(labelText: l.entityTreeFieldDescription),
            ),
            const SizedBox(height: 12),

            // ── Brand fields ─────────────────────────────────────────────
            ImageUploadField(
              value: widget.logoCtrl.text.isEmpty ? null : widget.logoCtrl.text,
              // Not the ARB "Logo URL": this is an upload button and a
              // thumbnail, so a URL label sends the operator hunting for a link.
              label: ar ? 'الشعار' : 'Logo',
              kind: 'agent-branding',
              onChanged: (u) => setState(() => widget.logoCtrl.text = u),
            ),
            const SizedBox(height: 12),
            ImageUploadField(
              value: widget.backgroundCtrl.text.isEmpty ? null : widget.backgroundCtrl.text,
              label: ar ? 'صورة الخلفية' : 'Background Image',
              kind: 'agent-branding',
              onChanged: (u) => setState(() => widget.backgroundCtrl.text = u),
            ),
            const SizedBox(height: 12),
            ColorHexField(controller: widget.primaryCtrl, label: l.entityFieldPrimaryColor),
            const SizedBox(height: 12),
            ColorHexField(controller: widget.secondaryCtrl, label: l.entityFieldSecondaryColor),
            const SizedBox(height: 12),
            // B-086: how many cards this account may sell in one bulk request. Blank =
            // inherit. The server resolves the EFFECTIVE value as the minimum over the
            // chain, so this can only ever tighten what an ancestor already allows.
            TextField(
              controller: widget.bulkCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    ar ? 'حد البيع بالجملة (بطاقات/عملية)' : 'Bulk sale limit (cards per sale)',
                hintText: '10',
                helperText: ar
                    ? 'اتركه فارغًا للتوريث. 1 يعطّل البيع بالجملة.'
                    : 'Blank inherits. 1 disables bulk selling.',
              ),
            ),
            // Only HQ may delegate or revoke limit management (server-enforced).
            if (widget.showBulkLock)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: !widget.bulkLocked,
                onChanged: (v) => setState(() => widget.onBulkLockChanged(!v)),
                title: Text(
                  ar ? 'السماح للوكيل بتعديل الحد' : 'Let this agent edit the limit',
                  style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w600),
                ),
                subtitle: Text(
                  ar
                      ? 'عند التعطيل، الإدارة وحدها تحدد الحد لهذا الحساب وكل ما تحته.'
                      : 'When off, only HQ sets the limit for this account and everything under it.',
                  style: IntesharType.sans(11, color: cs.onSurfaceVariant),
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
                    onPressed: _saving ? null : () => Navigator.pop(context),
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
                                  SnackBar(content: Text(l.entityTreeErrorSaving)),
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
                            child: CircularProgressIndicator(strokeWidth: 2))
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
