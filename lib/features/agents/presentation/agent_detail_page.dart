import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/agents/presentation/agent_strings.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/entity_row_actions.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_slot_balance.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

/// UX-02: one page per agent.
///
/// Onboarding an agent was four unlinked screens — create here, load stock over
/// there, hand out POS slots on a third page, choose visible products from a
/// menu buried in a hierarchy row — and after the create form popped `true` back
/// to a list, nothing anywhere said the new account had no cards, no points and
/// no prices. A new admin could not derive the remaining steps from the UI, so
/// they were learned from a support ticket weeks later.
///
/// This is the answer to "how is this one agent doing": what is still missing,
/// what it holds, who is under it, and every action that applies to it — the
/// canonical [EntityRowActionsButton] set, not a fifth private menu.
///
/// Every panel loads independently and is allowed to fail on its own: a section
/// whose feed was refused says so rather than rendering a confident zero.
class AgentDetailPage extends ConsumerStatefulWidget {
  final String entityId;

  /// Shown in the app bar until the full document arrives, so the page has a
  /// title from the first frame instead of a spinner with no subject.
  final String entityName;

  const AgentDetailPage({super.key, required this.entityId, this.entityName = ''});

  @override
  ConsumerState<AgentDetailPage> createState() => _AgentDetailPageState();
}

class _AgentDetailPageState extends ConsumerState<AgentDetailPage> {
  Entity? _entity;
  Object? _error;
  bool _loading = true;

  /// True when anything on this page changed the account, so the directory that
  /// pushed us knows to re-fetch. Popped back as the route result.
  bool _dirty = false;

  List<EntitySummaryRow> _children = const [];
  bool _childrenMore = false;

  List<SkuSummary>? _stock;
  PricingCatalog? _pricing;
  AgentBalance? _balance;
  PosSlotBalance? _slots;

  @override
  void initState() {
    super.initState();
    _load();
  }

  EntityRepository get _entities => EntityRepository(ref.read(apiClientProvider));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final e = await _entities.read(widget.entityId);
      if (!mounted) return;
      setState(() {
        _entity = e;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
      return;
    }
    await _loadPanels();
  }

  /// The four side feeds. Each is separately try/caught: a section-gated agent
  /// (HQ can hide reporting for a subtree) must not take the whole page down.
  Future<void> _loadPanels() async {
    final api = ref.read(apiClientProvider);
    final id = widget.entityId;

    try {
      final res = await _entities.children(id, page: 0);
      if (mounted) {
        setState(() {
          _children = res.items;
          _childrenMore = res.hasMore;
        });
      }
    } catch (_) {/* section reports "not available" */}

    try {
      final s = await ReportsRepository(api).stockSummary(entityId: id);
      if (mounted) setState(() => _stock = s);
    } catch (_) {/* section reports "not available" */}

    try {
      final c = await PricingRepository(api).catalog(entityId: id);
      if (mounted) setState(() => _pricing = c);
    } catch (_) {/* section reports "not available" */}

    try {
      final b = await PricingRepository(api).balance(entityId: id);
      if (mounted) setState(() => _balance = b);
    } catch (_) {/* section reports "not available" */}

    try {
      final q = await PosAdminRepository(api).quota(entityId: id);
      if (mounted) setState(() => _slots = q);
    } catch (_) {/* section reports "not available" */}
  }

  void _markChanged() {
    _dirty = true;
    _load();
  }

  /// The projected row this page's actions operate on — the same shape every
  /// other directory hands to [runEntityRowAction], so the action set is
  /// literally identical here.
  EntitySummaryRow get _row {
    final e = _entity;
    return EntitySummaryRow(
      id: widget.entityId,
      name: e?.meta.name ?? widget.entityName,
      type: e?.type ?? EntityType.AGENT1,
      childrenCount: e?.childrenIds.length ?? 0,
      productsCount: e?.productsIds.length ?? 0,
      userCount: e?.liveUsers.length ?? 0,
      governorates: e?.meta.governorates ?? const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _entity;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    final title = e?.meta.name.isNotEmpty == true
        ? e!.meta.name
        : (widget.entityName.isNotEmpty ? widget.entityName : widget.entityId);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_dirty);
      },
      child: Scaffold(
        appBar: AppBar(
          // UX-127: was a hand-built TextStyle at 18 — a size on no scale.
          // AppBar ellipsizes its title, so the step up cannot overflow.
          title: Text(
            title,
            style: IntesharText.titleLg(
                color: cs.onSurface, w: IntesharWeight.heavy),
          ),
          actions: [
            if (e != null)
              EntityRowActionsButton(
                row: _row,
                onChanged: _markChanged,
                // We ARE the detail page — offering "Open agent" from here would
                // push a second copy of it onto the stack.
                showOpen: false,
                iconSize: 20,
              ),
          ],
        ),
        body: SafeArea(child: _body(ar)),
      ),
    );
  }

  Widget _body(bool ar) {
    if (_loading && _entity == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final e = _entity;
    if (e == null) return const SizedBox.shrink();

    final tier = agentTierOf(e.type);
    final s = tier == null ? null : AgentStrings.of(context, tier);

    return RefreshIndicator(
      onRefresh: _load,
      child: MaxWidthBox(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 32),
          children: [
            _identityCard(e, ar),
            const SizedBox(height: IntesharSpacing.md),
            if (s != null) ...[
              _readinessCard(e, s, ar),
              const SizedBox(height: IntesharSpacing.md),
            ],
            _stockCard(e, ar),
            const SizedBox(height: IntesharSpacing.md),
            _pricesCard(e, ar),
            const SizedBox(height: IntesharSpacing.md),
            _networkCard(e, ar),
            const SizedBox(height: IntesharSpacing.md),
            _usersCard(e, ar),
          ],
        ),
      ),
    );
  }

  // ── Identity ───────────────────────────────────────────────────────────────

  Widget _identityCard(Entity e, bool ar) {
    final cs = Theme.of(context).colorScheme;
    final locale = ar ? 'ar' : 'en';
    return InkCard(
      ruleColor: context.tones.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.meta.name.isEmpty ? e.id : e.meta.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(20, color: cs.onSurface, w: FontWeight.w800),
                ),
              ),
              const SizedBox(width: IntesharSpacing.sm),
              RoleBadge(type: e.type),
            ],
          ),
          const SizedBox(height: IntesharSpacing.xs),
          SelectableText(e.id,
              style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.3)),
          if (e.meta.slogan.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(e.meta.slogan, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          _label(ar ? 'التغطية' : 'Coverage'),
          const SizedBox(height: 6),
          if (e.meta.governorates.isEmpty)
            Text(ar ? 'لا توجد محافظات' : 'No governorates',
                style: IntesharType.sans(12, color: cs.onSurfaceVariant))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: e.meta.governorates
                  .map((c) => StampPill(
                      label: governorateLabel(c, locale),
                      color: context.tones.brand,
                      filled: false))
                  .toList(),
            ),
          const SizedBox(height: 14),
          const Hairline(),
          const SizedBox(height: IntesharSpacing.md),
          Wrap(
            spacing: 22,
            runSpacing: IntesharSpacing.sm2,
            children: [
              _figure(
                ar ? 'الرصيد' : 'Balance',
                _balance == null ? null : Formatters.money(_balance!.available),
                ar,
              ),
              _figure(
                ar ? 'نقاط البيع' : 'POS points',
                _slots == null
                    ? null
                    : (_slots!.root ? '∞' : '${_slots!.available} / ${_slots!.total}'),
                ar,
              ),
              _figure(
                ar ? 'الحسابات التابعة' : 'Accounts below',
                '${e.childrenIds.length}',
                ar,
              ),
              _figure(ar ? 'المستخدمون' : 'Users', '${e.liveUsers.length}', ar),
            ],
          ),
        ],
      ),
    );
  }

  // ── Readiness (the UX-02 checklist) ────────────────────────────────────────

  Widget _readinessCard(Entity e, AgentStrings s, bool ar) {
    final main = e.type == EntityType.AGENT1;
    final cards = e.productsIds.length;
    final unpriced = _pricing?.unpricedCount;

    return _Section(
      title: s.setupTitle,
      subtitle: ar
          ? 'ما تبقّى قبل أن يتمكن هذا الوكيل من البيع.'
          : 'What is still missing before this agent can sell.',
      child: Column(
        children: [
          // Cards on hand. Only a Main Agent ever holds stock — below that tier
          // vouchers are drawn at print time, so the step does not exist.
          if (main)
            _StepRow(
              icon: Icons.style_outlined,
              label: s.setupCards,
              value: cards > 0 ? s.setupCardsSome(cards) : s.setupCardsNone,
              state: cards > 0 ? _StepState.done : _StepState.todo,
              actionLabel: ar ? 'إضافة كروت' : 'Add cards',
              onAction: viewerCanManageEntities(ref) ? () => context.push('/hq/batch') : null,
            ),
          _StepRow(
            icon: Icons.point_of_sale_outlined,
            label: s.setupSlots,
            value: _slots == null
                ? s.setupUnknown
                : _slots!.total > 0
                    ? s.setupSlotsSome(_slots!.available, _slots!.total)
                    : s.setupSlotsNone,
            state: _slots == null
                ? _StepState.unknown
                : _slots!.total > 0
                    ? _StepState.done
                    : _StepState.todo,
            actionLabel: ar ? 'نقاط البيع' : 'POS points',
            onAction: viewerCanManageEntities(ref) ? () => context.push('/hq/pos-users') : null,
          ),
          if (main)
            _StepRow(
              icon: Icons.sell_outlined,
              label: s.setupPrices,
              value: unpriced == null
                  ? s.setupUnknown
                  : unpriced > 0
                      ? s.setupPricesMissing(unpriced)
                      : s.setupPricesOk,
              state: unpriced == null
                  ? _StepState.unknown
                  : unpriced > 0
                      ? _StepState.todo
                      : _StepState.done,
              // UX-01 landed `/hq/pricing`, but that screen has no per-agent deep
              // link yet — it resolves the caller's own tier and offers its own
              // agent picker. Sending the operator there with the agent
              // preselected needs a query parameter on that route
              // (`lib/features/pricing/presentation/pricing_page.dart` +
              // `lib/app/router.dart`), neither of which is reachable from here.
              actionLabel: ar ? 'الأسعار' : 'Pricing',
              onAction: viewerIsHq(ref) ? () => context.push('/hq/pricing') : null,
            ),
          _StepRow(
            icon: Icons.inventory_2_outlined,
            label: s.setupProducts,
            // No bulk source for "which SKUs are visible", so this is an entry
            // point rather than a verdict — it must not claim either state.
            value: s.setupProductsAction,
            state: _StepState.unknown,
            actionLabel: s.setupProductsAction,
            onAction: viewerCanManageEntities(ref)
                ? () => runEntityRowAction(
                      context,
                      ref,
                      EntityRowAction.visibleProducts,
                      _row,
                      onChanged: _markChanged,
                    )
                : null,
            last: true,
          ),
        ],
      ),
    );
  }

  // ── Stock ──────────────────────────────────────────────────────────────────

  Widget _stockCard(Entity e, bool ar) {
    if (!e.type.inventoryBacked) {
      return _Section(
        title: ar ? 'المخزون' : 'Stock',
        child: _note(
          ar
              ? 'هذا الحساب لا يحتفظ بكروت — يسحب من مخزون وكيله الرئيسي عند الطباعة.'
              : 'This account holds no cards — it draws from its main agent at print time.',
        ),
      );
    }
    final stock = _stock;
    if (stock == null) return _Section(title: ar ? 'المخزون' : 'Stock', child: _unavailable(ar));
    if (stock.isEmpty) {
      return _Section(
        title: ar ? 'المخزون' : 'Stock',
        child: _note(ar ? 'لا توجد كروت في المخزن.' : 'No cards in the warehouse.'),
      );
    }
    final shown = stock.take(8).toList();
    return _Section(
      title: ar ? 'المخزون' : 'Stock',
      // UX-104: the drill-in is READ-ONLY, while the same screen reached through
      // the `/hq/inventory` dropdown lets HQ withdraw. Until the two entry
      // points are reconciled the label at least says which one this is.
      trailing: inventoryRoutePrefix(ref) == null
          ? null
          : TextButton(
              onPressed: () => runEntityRowAction(
                context,
                ref,
                EntityRowAction.viewInventory,
                _row,
                onChanged: _markChanged,
              ),
              child: Text(ar ? 'عرض الكل (قراءة فقط)' : 'View all (read-only)'),
            ),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++)
            _kvRow(
              shown[i].name.isEmpty ? shown[i].sku : shown[i].name,
              ar ? '${Formatters.money(shown[i].available)} متاح' : '${Formatters.money(shown[i].available)} available',
              last: i == shown.length - 1,
            ),
          if (stock.length > shown.length)
            _note(ar
                ? 'و${stock.length - shown.length} أصناف أخرى.'
                : 'and ${stock.length - shown.length} more.'),
        ],
      ),
    );
  }

  // ── Prices ─────────────────────────────────────────────────────────────────

  Widget _pricesCard(Entity e, bool ar) {
    final p = _pricing;
    final title = ar ? 'الأسعار' : 'Prices';
    if (p == null) return _Section(title: title, child: _unavailable(ar));
    if (p.rows.isEmpty) {
      return _Section(
        title: title,
        child: _note(ar ? 'لا توجد أصناف مسعّرة لهذا الوكيل.' : 'No priced categories for this agent.'),
      );
    }
    final shown = p.rows.take(8).toList();
    return _Section(
      title: title,
      subtitle: p.unpricedCount > 0
          ? (ar ? '${p.unpricedCount} صنف بدون سعر' : '${p.unpricedCount} unpriced')
          : null,
      trailing: viewerIsHq(ref)
          ? TextButton(
              onPressed: () => context.push('/hq/pricing'),
              child: Text(ar ? 'تعديل' : 'Edit'),
            )
          : null,
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++)
            _kvRow(
              shown[i].name.isEmpty ? shown[i].sku : shown[i].name,
              shown[i].priced
                  ? Formatters.money(shown[i].effectivePrice)
                  : (ar ? 'بدون سعر' : 'unpriced'),
              danger: !shown[i].priced,
              last: i == shown.length - 1,
            ),
        ],
      ),
    );
  }

  // ── Network (shops / sub-agents) ───────────────────────────────────────────

  Widget _networkCard(Entity e, bool ar) {
    final title = e.type == EntityType.AGENT1
        ? (ar ? 'الوكلاء الفرعيون' : 'Sub agents')
        : (ar ? 'نقاط البيع' : 'Points of sale');
    if (_children.isEmpty) {
      return _Section(
        title: title,
        child: _note(ar ? 'لا توجد حسابات تابعة بعد.' : 'No accounts below this one yet.'),
      );
    }
    return _Section(
      title: title,
      subtitle: _childrenMore
          ? (ar ? 'أول ${_children.length} — افتح الهيكل للبقية.' : 'first ${_children.length} — open the hierarchy for the rest')
          : null,
      child: Column(
        children: [
          for (var i = 0; i < _children.length; i++)
            _ChildRow(
              row: _children[i],
              onChanged: _markChanged,
              last: i == _children.length - 1,
            ),
        ],
      ),
    );
  }

  // ── Users ──────────────────────────────────────────────────────────────────

  Widget _usersCard(Entity e, bool ar) {
    final cs = Theme.of(context).colorScheme;
    return _Section(
      title: ar ? 'المستخدمون' : 'Users',
      trailing: viewerCanManageEntities(ref)
          ? TextButton(
              onPressed: () => runEntityRowAction(
                context,
                ref,
                EntityRowAction.manageUsers,
                _row,
                onChanged: _markChanged,
              ),
              child: Text(ar ? 'إدارة' : 'Manage'),
            )
          : null,
      // UX-156: the roster is the users in SERVICE. /entity/read returns the
      // archived ones too, because the server keeps the record.
      child: e.liveUsers.isEmpty
          ? _note(ar ? 'لا يوجد مستخدمون.' : 'No users.')
          : Column(
              children: [
                for (var i = 0; i < e.liveUsers.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == e.liveUsers.length - 1 ? 0 : 10),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 17, color: cs.onSurfaceVariant),
                        const SizedBox(width: IntesharSpacing.sm2),
                        Expanded(
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(e.liveUsers[i].phone, style: IntesharType.mono(12)),
                            ),
                          ),
                        ),
                        StampPill(
                          label: e.liveUsers[i].role.name,
                          color: context.status.neutral,
                          filled: false,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // ── Small pieces ───────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: IntesharType.overline(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );

  /// A figure with no confirmed value shows an em-dash, never a zero: "we did
  /// not get this number" and "this number is nought" are different facts.
  Widget _figure(String label, String? value, bool ar) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: IntesharType.sans(11, color: cs.onSurfaceVariant, w: IntesharWeight.semibold)),
        const SizedBox(height: 2),
        Text(
          value ?? '—',
          style: IntesharType.mono(16,
              color: value == null ? cs.onSurfaceVariant : cs.onSurface),
        ),
      ],
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(text,
            style: IntesharType.sans(12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _unavailable(bool ar) => _note(ar
      ? 'غير متاح لهذا الحساب.'
      : 'Not available for this account.');

  Widget _kvRow(String k, String v, {bool danger = false, bool last = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 9),
      child: Row(
        children: [
          Expanded(
            child: Text(k,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.sans(12, color: cs.onSurface)),
          ),
          const SizedBox(width: IntesharSpacing.sm2),
          Text(v,
              style: IntesharType.mono(12,
                  color: danger ? context.status.warn : cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─── One child account, carrying the canonical action set ─────────────────────

class _ChildRow extends ConsumerWidget {
  final EntitySummaryRow row;
  final VoidCallback onChanged;
  final bool last;
  const _ChildRow({required this.row, required this.onChanged, this.last = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 4),
      child: InkWell(
        onTap: entityHasDetailPage(row.type)
            ? () => openAgentDetail(context, row.id, row.label, onChanged: onChanged)
            : null,
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        child: Padding(
          // UX-119: a two-line row at 6dp of padding is ~45dp; this is a
          // navigation target into a child account.
          padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text(row.type.label,
                        style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              EntityRowActionsButton(row: row, onChanged: onChanged, iconSize: 17),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section frame ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  const _Section({required this.title, this.subtitle, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w800)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: IntesharSpacing.md),
          child,
        ],
      ),
    );
  }
}

// ─── One onboarding step ──────────────────────────────────────────────────────

enum _StepState { done, todo, unknown }

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final _StepState state;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool last;

  const _StepRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.state,
    required this.actionLabel,
    this.onAction,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tone = switch (state) {
      _StepState.done => context.status.success,
      _StepState.todo => context.status.warn,
      _StepState.unknown => context.status.neutral,
    };
    final markIcon = switch (state) {
      _StepState.done => Icons.check_circle_outline,
      _StepState.todo => Icons.error_outline,
      _StepState.unknown => icon,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        children: [
          Icon(markIcon, size: 18, color: tone),
          const SizedBox(width: IntesharSpacing.sm2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: IntesharWeight.semibold)),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
              ],
            ),
          ),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}
