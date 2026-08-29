import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/chat/presentation/supply_request.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

// ─── Data container ─────────────────────────────────────────────────────────

class _DashData {
  final List<SkuSummary> stock;
  // Newest balance transfers touching this account (B-051: the transaction
  // flow is retired — HQ uploads stock directly; value moves as balance).
  final List<GrantRow> recentTransfers;
  final int childCount; // direct children
  final List<EntitySummaryRow>
  children; // direct children (for the balance transfer picker)
  final AgentBalance balance;

  /// UX-25: each DIRECT child's current balance. The dashboard already fetched
  /// the children and threw them away; "which of my shops has run out of
  /// credit" was unanswerable anywhere in the app. Null = the roster feed is
  /// unavailable to this caller (it is VIEW_REPORTS-gated), which must render
  /// as "not shown", never as a confident zero.
  final List<_ChildCredit>? childCredit;

  /// Net credit this account has granted out in the current calendar month
  /// (take-backs are negative ledger rows, so they net off).
  final num grantedThisMonth;

  const _DashData({
    required this.stock,
    required this.recentTransfers,
    required this.childCount,
    required this.children,
    required this.balance,
    required this.childCredit,
    required this.grantedThisMonth,
  });
}

/// One direct child and what it currently has to spend.
class _ChildCredit {
  final String id;
  final String name;
  final num available;
  const _ChildCredit({required this.id, required this.name, required this.available});
}

// ─── Page ────────────────────────────────────────────────────────────────────

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  _DashData? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// entityId → available balance, across the caller's subtree. Best-effort:
  /// the roster feed is VIEW_REPORTS-gated and an agent may hold
  /// CREATE_TRANSACTIONS without it, so a 403 returns null (= "don't show it")
  /// rather than an empty map that would read as "everyone is at zero".
  Future<Map<String, num>?> _rosterBalances(dynamic api, String rootId) async {
    try {
      final out = <String, num>{};
      var page = 0;
      while (true) {
        final res = await ReportsRepository(api)
            .balancesRoster(rootId: rootId, page: page, size: 200);
        for (final r in res.items) {
          out[r.entityId] = r.available;
        }
        if (!res.hasMore || page > 20) break;
        page++;
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// UX-84: [silent] refreshes the tiles in place instead of blanking them.
  ///
  /// `_loading` swaps the whole dashboard for a centred spinner, so a
  /// pull-to-refresh destroyed every KPI tile and card and drew a second
  /// spinner under the refresh arc — scroll position lost, and the tiles that
  /// were meant to change flashed away instead of changing. Only the first load
  /// blanks; the refresh arc is already the progress indicator for the rest.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authStateProvider).valueOrNull;
      final entity = (auth is AuthAuthenticated) ? auth.entity : null;
      if (entity == null) {
        setState(() => _loading = false);
        return;
      }
      final api = ref.read(apiClientProvider);
      // B-051: the recent-activity card shows balance transfers (the ledger
      // already carries resolved names), not the retired transaction flow.
      final results = await Future.wait([
        // B-023 P2: the KPI row needs COUNTS, not documents. readByEntity
        // downloaded every voucher in the account to compute four numbers the
        // server already aggregates.
        ProductRepository(api).summaryByEntity(entity.id),
        PricingRepository(api).grants(),
        EntityRepository(api).children(entity.id, size: 200),
        _rosterBalances(api, entity.id),
      ]);
      final stock = results[0] as List<SkuSummary>;
      final grants = results[1] as List<GrantRow>;
      final transfers = grants.toList()
        ..sort((a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'));
      final children = (results[2] as Paged<EntitySummaryRow>).items;
      final roster = results[3] as Map<String, num>?;
      // Balance is best-effort: a failure here must not blank the dashboard.
      AgentBalance balance = const AgentBalance();
      try {
        balance = await PricingRepository(api).balance();
      } catch (_) {}
      // Direct children only — the roster covers the whole subtree, and "my
      // shops" means the ones I can actually top up.
      final credit = roster == null
          ? null
          : (children
              .where((c) => roster.containsKey(c.id))
              .map((c) => _ChildCredit(
                  id: c.id, name: c.label, available: roster[c.id] ?? 0))
              .toList()
            ..sort((a, b) => a.available.compareTo(b.available)));
      final now = DateTime.now();
      final monthPrefix =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
      final granted = grants
          .where((g) => g.sourceId == entity.id && g.date.startsWith(monthPrefix))
          .fold<num>(0, (a, g) => a + g.amount);
      setState(() {
        _data = _DashData(
          stock: stock,
          recentTransfers: transfers.take(5).toList(),
          childCount: entity.childrenIds.length,
          children: children,
          balance: balance,
          childCredit: credit,
          grantedThisMonth: granted,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final entity = (auth is AuthAuthenticated) ? auth.entity : null;

    if (entity == null) return const SizedBox.shrink();

    final canTransfer =
        auth is AuthAuthenticated &&
        auth.can({Capability.CREATE_TRANSACTIONS, Capability.MANAGE_POS});

    return MaxWidthBox(
      child: RefreshIndicator(
        // UX-84: the arc IS the progress indicator — don't also tear the page down.
        onRefresh: () => _load(silent: true),
        child: (_loading || _data == null)
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [ErrorState(error: _error!, onRetry: _load)],
              )
            : _DashContent(
                entity: entity,
                data: _data!,
                onRefresh: () => _load(silent: true),
                canTransfer: canTransfer,
              ),
      ),
    );
  }
}

// ─── Main content ────────────────────────────────────────────────────────────

class _DashContent extends StatelessWidget {
  final Entity entity;
  final _DashData data;
  final VoidCallback onRefresh;
  final bool canTransfer;

  const _DashContent({
    required this.entity,
    required this.data,
    required this.onRefresh,
    required this.canTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    // KPI values, straight off the server-side aggregation (B-023 P2).
    final withStock = data.stock.where((k) => k.available > 0).toList();
    final availableCount = withStock.fold<int>(0, (a, k) => a + k.available);
    final availableSkuCount = withStock.length;

    // Low stock: SKUs below this account's configured threshold (falls back to
    // EntityMeta.defaultLowStockThreshold when the entity hasn't set one).
    // Only SKUs the account actually holds count — a SKU at 0 is out of stock,
    // which the empty-inventory state covers, not "low".
    final lowStockThreshold = entity.meta.effectiveLowStockThreshold;
    final lowSkus = <String, ({String name, int count})>{
      for (final k in withStock)
        if (k.available < lowStockThreshold) k.sku: (name: k.name, count: k.available),
    };


    final isStore = entity.type == EntityType.STORE;
    // For a STORE the KPI row would be a single meaningless "Direct children: 0"
    // tile (stock KPIs are already hidden for non-inventory tiers), so skip it.
    final showKpis = !isStore || entity.type.inventoryBacked;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
      children: [
        // UX-136: this is the landing route for /agent1, /agent2 AND /store —
        // three of the four roles — and it was the one screen that hand-rolled
        // its header: display 28 against PageHeader's 32, no brand underline,
        // no eyebrow, and its own 24/28 padding against the shared 16. So most
        // people's first screen was the one that looked least like the product.
        // The role badge moves into PageHeader's `trailing` slot; the eyebrow is
        // what the nav itself calls this destination, and PageHeader suppresses
        // it automatically if it ever reads as redundant against the title.
        PageHeader(
          eyebrow: l.navDashboard,
          title: entity.meta.name,
          subtitle: entity.type == EntityType.INTESHAR
              ? l.dashPlatformOverview
              : entity.meta.slogan.isNotEmpty
                  ? entity.meta.slogan
                  : entity.type.label,
          trailing: RoleBadge(type: entity.type),
        ),

        // ── Store-admin note: selling is a SEPARATE POS login ────────────
        // A STORE-ADMIN can't sell from this console (the counter lives in the
        // /pos USER session); say so plainly instead of leaving a dead end.
        if (isStore)
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
            child: _StorePosNote(),
          ),

        // ── Virtual balance ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
          child: _BalanceCard(
            entity: entity,
            balance: data.balance,
            children: data.children,
            canTransfer: canTransfer,
            onGranted: onRefresh,
          ),
        ),

        // ── KPI tiles ────────────────────────────────────────────────────
        if (showKpis)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 0),
            child: _KpiRow(
              childCount: data.childCount,
              availableCount: availableCount,
              availableSkuCount: availableSkuCount,
              lowStockCount: lowSkus.length,
              lowStockThreshold: lowStockThreshold,
              showInventory: entity.type.inventoryBacked,
              childCredit: data.childCredit,
              grantedThisMonth: data.grantedThisMonth,
              showCredit: entity.type.transfersRoute != null,
            ),
          ),

        // ── Two-column body ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
          child: _BodyRow(
            entity: entity,
            transfers: data.recentTransfers,
            lowSkus: lowSkus,
            lowStockThreshold: lowStockThreshold,
            childCredit: data.childCredit,
            l: l,
          ),
        ),
      ],
    );
  }
}

// ─── Slim header ─────────────────────────────────────────────────────────────


// ─── Store-admin POS note ──────────────────────────────────────────────────────

/// Shown only on a STORE-ADMIN dashboard: this console manages the shop, but the
/// actual selling counter is a separate point-of-sale login (the USER-role
/// account on `/pos`). Prevents an owner who signed in with the admin account
/// from concluding the app can't sell.
///
/// UX-107: it now also says where MESSAGES live. HQ, AGENT1 and AGENT2 all have
/// a Conversations destination and a sub-agent can start a thread with a shop —
/// but there is no `/store/chat` route and no store nav entry, so the thread
/// lands only on the counter operator's device while the person the agent
/// actually needs (the owner, about balance and stock) has no inbox at all.
/// Adding the route is `lib/app/router.dart` + `lib/shared/widgets/app_scaffold.dart`;
/// until then, silence here reads as "the app has no messaging", which is worse
/// than a plain statement of where to look.
class _StorePosNote extends StatelessWidget {
  const _StorePosNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';

    Widget line(IconData icon, String title, String body) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: context.tones.brandInk),
            const SizedBox(width: IntesharSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: IntesharType.sans(14,
                          color: cs.onSurface, w: FontWeight.w800)),
                  const SizedBox(height: IntesharSpacing.xs),
                  Text(body,
                      style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(IntesharSpacing.lg),
      decoration: BoxDecoration(
        color: context.tones.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: context.tones.brand.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(
            Icons.point_of_sale_outlined,
            ar ? 'هذه شاشة إدارة المتجر' : 'This is the shop management console',
            ar
                ? 'للبيع والطباعة، سجّل الدخول بحساب نقطة البيع (حساب المستخدم) على تطبيق نقطة البيع.'
                : 'To sell and print, sign in with your point-of-sale account (the USER login) in the POS app.',
          ),
          const SizedBox(height: IntesharSpacing.md),
          line(
            Icons.forum_outlined,
            ar ? 'المحادثات مع وكيلك' : 'Messages from your agent',
            ar
                ? 'تصل رسائل وكيلك إلى تبويب "التواصل" في تطبيق نقطة البيع، وليس إلى هذه الشاشة. أما إشعارات الإدارة فتجدها في "الإشعارات" هنا.'
                : 'Your agent\'s messages arrive in the "Conversations" tab of the POS app, not on this console. Headquarters announcements are under Notifications here.',
          ),
        ],
      ),
    );
  }
}

// ─── KPI tile row ─────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final int childCount;
  final int availableCount;
  final int availableSkuCount;
  final int lowStockCount;
  final int lowStockThreshold;
  final bool showInventory;
  final List<_ChildCredit>? childCredit;
  final num grantedThisMonth;
  final bool showCredit;

  const _KpiRow({
    required this.childCount,
    required this.availableCount,
    required this.availableSkuCount,
    required this.lowStockCount,
    required this.lowStockThreshold,
    required this.showInventory,
    required this.childCredit,
    required this.grantedThisMonth,
    required this.showCredit,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final credit = childCredit;
    final dry = credit == null ? 0 : credit.where((c) => c.available <= 0).length;
    final tiles = [
      _KpiTile(
        label: l.navChildren,
        value: Formatters.money(childCount),
        caption: l.dashKpiDirectChildren,
        icon: Icons.account_tree_outlined,
        tint: context.tones.brand,
      ),
      // Stock / low-stock KPIs only for inventory-backed tiers (HQ, Main Agent).
      // Sub Agents & Stores draw-on-print and hold no cards (B-042).
      if (showInventory)
        _KpiTile(
          label: l.dashKpiStock,
          value: Formatters.money(availableCount),
          caption: l.dashKpiSkusCount(availableSkuCount),
          icon: Icons.inventory_2_outlined,
          tint: IntesharColors.azure,
        ),
      if (showInventory)
        _KpiTile(
          label: l.dashKpiLowStock,
          value: Formatters.money(lowStockCount),
          // UX-47: "12 left" told you nothing without the line it fell below.
          // The threshold is what makes the count mean anything.
          caption: lowStockCount == 0
              ? '${l.dashKpiAllHealthy} · ${ar ? 'الحد $lowStockThreshold' : 'threshold $lowStockThreshold'}'
              : (ar
                  ? 'أقل من $lowStockThreshold بطاقة'
                  : 'below $lowStockThreshold cards'),
          icon: Icons.warning_amber_rounded,
          // UX-128: low stock is `warn` — it needs attention and nothing has
          // broken yet. Danger red is kept for the account that has actually
          // STOPPED (out of credit, below), so the two are told apart at a
          // glance instead of both shouting.
          tint: context.status.warn,
        ),
      // UX-25: the wallet tiers' equivalent of the stock KPIs. A Sub Agent held
      // exactly one tile ("branches: 3") on the screen they open every morning.
      // Hidden entirely when the roster feed is unavailable — a confident "0
      // accounts out of credit" would be worse than no tile.
      if (showCredit && credit != null && credit.isNotEmpty)
        _KpiTile(
          label: ar ? 'حسابات بلا رصيد' : 'Accounts out of credit',
          value: Formatters.money(dry),
          caption: ar ? 'من ${credit.length} حساب' : 'of ${credit.length} accounts',
          icon: Icons.account_balance_wallet_outlined,
          tint: dry == 0 ? context.status.success : context.status.danger,
        ),
      if (showCredit)
        _KpiTile(
          label: ar ? 'رصيد مُحوَّل' : 'Credit sent',
          value: Formatters.money(grantedThisMonth),
          caption: ar ? 'هذا الشهر' : 'this month',
          icon: Icons.north_east,
          tint: IntesharColors.azure,
        ),
    ];

    return LayoutBuilder(
      builder: (ctx, c) {
        final cols = c.maxWidth >= 980
            ? 4
            : c.maxWidth >= 560
            ? 2
            : 1;
        if (cols == 1) {
          // Stretch each card to the full column width. Without this the Column
          // centers cards at their own content width, so on phones they render
          // ragged — different widths and heights per card.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: tiles
                .map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: IntesharSpacing.md),
                    child: t,
                  ),
                )
                .toList(),
          );
        }
        // Build wrapped rows
        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += cols) {
          final rowTiles = tiles.sublist(i, (i + cols).clamp(0, tiles.length));
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: IntesharSpacing.md),
              // IntrinsicHeight + stretch makes every tile in the row adopt the
              // tallest tile's height. Labels (maxLines: 2) and captions wrap to
              // different line counts per tile — especially in Arabic — which
              // otherwise leaves the cards visibly uneven.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < rowTiles.length; j++) ...[
                      if (j > 0) const SizedBox(width: IntesharSpacing.md),
                      Expanded(child: rowTiles[j]),
                    ],
                    // Fill remaining cols with invisible spacers so row is uniform
                    for (var k = rowTiles.length; k < cols; k++) ...[
                      const SizedBox(width: IntesharSpacing.md),
                      const Expanded(child: SizedBox()),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color tint;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 18),
      child: Stack(
        children: [
          // Icon chip top-end
          PositionedDirectional(
            end: 0,
            top: 0,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                // Reserve the floating icon-chip's corner (34px + gap) so long
                // labels — especially the Arabic ones — never run under it.
                padding: const EdgeInsetsDirectional.only(end: 42),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(
                    12,
                    color: cs.onSurfaceVariant,
                    w: IntesharWeight.semibold,
                  ),
                ),
              ),
              const SizedBox(height: IntesharSpacing.sm2),
              // UX-127: 30 is on no scale. Snapping to the 32 step is only safe
              // because the numeral now scales down inside its own tile — a
              // four-column desktop tile is ~190dp wide and a month's granted
              // credit is a long number, so it could already clip at 30.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: IntesharText.displayLg(color: cs.onSurface)),
              ),
              const SizedBox(height: IntesharSpacing.xs),
              Text(
                caption,
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Body row (transactions + low stock) ─────────────────────────────────────

class _BodyRow extends StatelessWidget {
  final Entity entity;
  final List<GrantRow> transfers;
  final Map<String, ({String name, int count})> lowSkus;
  final int lowStockThreshold;
  final List<_ChildCredit>? childCredit;
  final AppLocalizations l;

  const _BodyRow({
    required this.entity,
    required this.transfers,
    required this.lowSkus,
    required this.lowStockThreshold,
    required this.childCredit,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final wide = c.maxWidth >= 900;
        // Only agents have the full transfers page (B-056); HQ/stores see the
        // card without a deep link.
        final transfersRoute = entity.type.transfersRoute;
        final txnCard = _RecentTransfersCard(
          transfers: transfers,
          selfId: entity.id,
          onViewAll: transfersRoute != null ? () => ctx.go(transfersRoute) : null,
          l: l,
        );

        // UX-25: "which of my accounts has run out of credit" is the first
        // question of an agent's morning and had no answer anywhere. Shown for
        // both agent tiers — the Sub Agent dashboard was otherwise a balance
        // card and one tile.
        final credit = childCredit;
        final creditCard = (transfersRoute != null && credit != null && credit.isNotEmpty)
            ? _ChildCreditCard(
                rows: credit,
                onTopUp: () => ctx.go(transfersRoute),
              )
            : null;

        // Low-stock is an inventory concern — only for inventory-backed tiers.
        // Sub Agents & Stores draw-on-print and hold no cards (B-042).
        final lowCard = entity.type.inventoryBacked
            ? _LowStockCard(
                lowSkus: lowSkus,
                threshold: lowStockThreshold,
                // UX-28: stock only arrives when the tier above uploads a batch.
                // HQ is that tier, so it has no one to ask.
                canRequest: entity.type != EntityType.INTESHAR,
                l: l,
              )
            : null;

        final side = <Widget>[?creditCard, ?lowCard];
        if (side.isEmpty) return txnCard;

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: txnCard),
              const SizedBox(width: IntesharSpacing.lg),
              SizedBox(
                width: 360,
                child: Column(children: [
                  for (var i = 0; i < side.length; i++) ...[
                    if (i > 0) const SizedBox(height: IntesharSpacing.lg),
                    side[i],
                  ],
                ]),
              ),
            ],
          );
        }
        return Column(children: [
          txnCard,
          for (final w in side) ...[const SizedBox(height: IntesharSpacing.lg), w],
        ]);
      },
    );
  }
}

// ─── Child credit card (UX-25) ───────────────────────────────────────────────

/// The accounts under this agent, poorest first — the ones that will stop
/// selling next. Zero-balance rows are called out; the rest still show a number
/// so "low" can be judged rather than guessed.
class _ChildCreditCard extends StatelessWidget {
  final List<_ChildCredit> rows;
  final VoidCallback onTopUp;
  const _ChildCreditCard({required this.rows, required this.onTopUp});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final dry = rows.where((r) => r.available <= 0).toList();
    // Poorest first; show the empty ones, then enough of the rest to give the
    // number context — never the whole roster (that is the Reports page).
    final shown = rows.take(dry.length > 5 ? dry.length.clamp(0, 8) : 5).toList();

    return InkCard(
      density: CardDensity.flush,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ar ? 'رصيد الحسابات' : 'Account credit',
                        style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dry.isEmpty
                            ? (ar ? 'كل الحسابات لديها رصيد' : 'every account has credit')
                            : (ar
                                ? '${dry.length} حساب بلا رصيد'
                                : '${dry.length} out of credit'),
                        style: IntesharType.sans(
                          12,
                          color: dry.isEmpty
                              ? context.status.success
                              : context.status.danger,
                          w: IntesharWeight.semibold,
                        ),
                      ),
                    ],
                  ),
                ),
                _ViewAllLink(label: ar ? 'شحن' : 'Top up', onTap: onTopUp),
              ],
            ),
          ),
          const Hairline(),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Hairline(),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 11, 20, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      shown[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IntesharType.sans(14, color: cs.onSurface, w: IntesharWeight.semibold),
                    ),
                  ),
                  const SizedBox(width: IntesharSpacing.sm),
                  Text(
                    Formatters.iqd(shown[i].available.round()),
                    style: IntesharType.mono(
                      12,
                      color: shown[i].available <= 0
                          ? context.status.danger
                          : cs.onSurface,
                      w: shown[i].available <= 0 ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (rows.length > shown.length)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 12),
              child: Text(
                ar
                    ? 'و${rows.length - shown.length} حساب آخر'
                    : 'and ${rows.length - shown.length} more',
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Recent transfers card (B-051) ───────────────────────────────────────────

/// Newest balance transfers touching this account, from the grant ledger
/// (`GET /api/balance/grants` — names resolved server-side). Sent transfers
/// show the destination, received ones the source.
class _RecentTransfersCard extends StatelessWidget {
  final List<GrantRow> transfers;
  final String selfId;

  /// Deep-link to the full transfers page (agents only, B-056); null hides it.
  final VoidCallback? onViewAll;
  final AppLocalizations l;

  const _RecentTransfersCard({
    required this.transfers,
    required this.selfId,
    required this.onViewAll,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';

    return InkCard(
      density: CardDensity.flush,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ar ? 'آخر التحويلات' : 'Recent transfers',
                    style: IntesharType.sans(
                      14,
                      color: cs.onSurface,
                      w: FontWeight.w700,
                    ),
                  ),
                ),
                if (onViewAll != null)
                  _ViewAllLink(label: l.dashViewAll, onTap: onViewAll!),
              ],
            ),
          ),
          const Hairline(),
          if (transfers.isEmpty)
            _InlineEmpty(message: ar ? 'لا توجد تحويلات بعد.' : 'No transfers yet.')
          else
            ...List.generate(transfers.length, (i) {
              final g = transfers[i];
              final sent = g.sourceId == selfId;
              final other = sent
                  ? (g.destName.isNotEmpty ? g.destName : g.destId)
                  : (g.sourceName.isNotEmpty ? g.sourceName : g.sourceId);
              // UX-128: sending credit down the tree is the product working, not
              // a failure — `brand`, never `danger`. Red here spends the one
              // signal a sales floor reacts to on a routine top-up.
              final tint =
                  sent ? context.status.brand : context.status.success;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(IntesharRadii.xs),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            sent ? Icons.north_east : Icons.south_west,
                            size: 16,
                            color: tint,
                          ),
                        ),
                        const SizedBox(width: IntesharSpacing.sm2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sent
                                    ? (ar ? 'إلى $other' : 'To $other')
                                    : (ar ? 'من $other' : 'From $other'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: IntesharType.sans(
                                  14,
                                  color: cs.onSurface,
                                  w: IntesharWeight.semibold,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '${g.date} ${g.time}',
                                style: IntesharType.mono(
                                  11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${sent ? '−' : '+'}${Formatters.iqd(g.amount.round())}',
                          style: IntesharType.mono(
                            14,
                            color: tint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i != transfers.length - 1) const Hairline(),
                ],
              );
            }),
        ],
      ),
    );
  }
}

/// Tappable "View all →" link with proper hover/focus/pressed feedback.
class _ViewAllLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ViewAllLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IntesharRadii.sm),
      // UX-119: "View all" / "Top up" / "Request cards" are the only outbound
      // links on the dashboard cards, and 12px text with 6px of padding made
      // them ~28dp tall.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: IntesharType.sans(
                12,
                color: context.tones.brandInk,
                w: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: context.tones.brandInk,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Compact inline empty state for a card section — mirrors the low-stock card's
/// "all healthy" row rather than the full-screen hero EmptyState.
class _InlineEmpty extends StatelessWidget {
  final String message;
  const _InlineEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: IntesharSpacing.md),
          Expanded(
            child: Text(
              message,
              style: IntesharType.sans(
                14,
                color: cs.onSurfaceVariant,
                w: IntesharWeight.regular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacked two-line transaction row for narrow widths (phones, side panel).
// ─── Virtual balance card ─────────────────────────────────────────────────────

class _BalanceCard extends ConsumerWidget {
  final Entity entity;
  final AgentBalance balance;
  final List<EntitySummaryRow> children;
  final bool canTransfer;
  final VoidCallback onGranted;
  const _BalanceCard({
    required this.entity,
    required this.balance,
    required this.children,
    required this.canTransfer,
    required this.onGranted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    // Inventory-backed tiers (HQ / Main Agent) grant balance down, so it reads as
    // transferable credit. Wallet tiers (Sub Agent / Store) only spend it on
    // withdrawals/prints from the Main Agent's stock, so it reads as a spending cap.
    // One canonical term for the virtual balance across the app (POS / dashboard / stores):
    // "Balance" / "الرصيد".
    final label = ar ? 'الرصيد' : 'Balance';
    // B-111: the dashboard used to open its OWN transfer sheet — a plain dropdown
    // fed by a single unpaged children(size:200) call. The server sorts children
    // type-ASC, so an agent's POS points sorted last and fell off: the exact B-092
    // bug, on the MORE prominent of the two entry points. It also never received
    // B-105 (single dialog + Agents/POS segment) or B-109 (distinct POS rows).
    // One transfer flow now, not two — this is a shortcut to the real page.
    final transfersRoute = entity.type.transfersRoute;
    final showTransfer =
        canTransfer && children.isNotEmpty && transfersRoute != null;
    final cs = Theme.of(context).colorScheme;
    // UX-20: `available` is `base − grantsOut`, and the card rendered only the
    // result — while the pricing screen shows `قيمة المخزون` (stock × price) on a
    // completely different basis. Neither stated what it was, so two money
    // numbers sat in the app with no stated relationship. `AgentBalance` already
    // carries `base` and `grantsOut` and the client already parses them, so the
    // card now shows the three lines the owner thinks in:
    //   credited to me → given to my accounts → left with me.
    final showBreakdown = balance.base != 0 || balance.grantsOut != 0;
    // UX-28: balance only enters the system when the tier above grants it after
    // an off-system payment — so for everyone but HQ, "I need more" is a
    // sentence someone has to type. This is the shortcut to typing it.
    final canAsk = entity.type != EntityType.INTESHAR;
    // B-094: a WHITE card with a brand accent rule, not a solid gold slab. The
    // number is the hero — big ink numerals on paper read as money, and gold is
    // reserved for the thin accent + the label, so it stays meaningful.
    // UX-126: the card is an `InkCard` like every other card on the screen —
    // this used to be a hand-rolled `cs.surface` (the PAGE colour) + hairline
    // recipe sitting inches from real InkCards on the same viewport.
    return InkCard(
      bordered: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The one flash of brand colour on the card.
              BrandRule(width: 3, height: 40),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            IntesharType.overline(color: cs.onSurfaceVariant)),
                    const SizedBox(height: IntesharSpacing.xs),
                    Text(
                      Formatters.iqd(balance.available.round()),
                      style: IntesharType.codec(
                        size: 32,
                        w: FontWeight.w900,
                        color: cs.onSurface,
                        letterSpacing: -0.8,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              if (showTransfer)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.onSurface,
                    foregroundColor: cs.surface,
                  ),
                  onPressed: () => context.go(transfersRoute),
                  icon: const Icon(Icons.north_east, size: 16),
                  label: Text(ar ? 'تحويل رصيد' : 'Transfer'),
                ),
            ],
          ),
          if (showBreakdown) ...[
            const SizedBox(height: 14),
            const Hairline(),
            const SizedBox(height: IntesharSpacing.sm2),
            _BalanceLine(
              label: ar ? 'مُضاف لي' : 'Credited to me',
              amount: balance.base,
            ),
            const SizedBox(height: IntesharSpacing.xs),
            _BalanceLine(
              label: ar ? 'مُحوَّل إلى حساباتي' : 'Given to my accounts',
              amount: balance.grantsOut,
              negative: true,
            ),
            const SizedBox(height: IntesharSpacing.xs),
            _BalanceLine(
              label: ar ? 'المتبقي لديّ' : 'Left with me',
              amount: balance.available,
              strong: true,
            ),
            const SizedBox(height: IntesharSpacing.sm),
            // What "credited" is measured in — the other half of UX-20. An
            // inventory-backed tier's credit is the value of the stock HQ
            // uploaded to it; a wallet tier's is credit its parent granted.
            Text(
              balance.inventoryBacked
                  ? (ar
                      ? 'المُضاف = قيمة الكروت المرفوعة لك'
                      : 'Credited = the value of the cards uploaded to you')
                  : (ar
                      ? 'المُضاف = الرصيد الممنوح لك'
                      : 'Credited = the balance granted to you'),
              style: IntesharType.sans(12, color: cs.onSurfaceVariant),
            ),
          ],
          if (canAsk) ...[
            const SizedBox(height: IntesharSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => showSupplyRequest(
                  context,
                  ref,
                  kind: SupplyRequestKind.balance,
                  current: balance.available,
                ),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: Text(ar ? 'طلب رصيد' : 'Request balance'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the balance breakdown (UX-20): a label and its figure, in the
/// order the account owner reasons about them.
class _BalanceLine extends StatelessWidget {
  final String label;
  final num amount;
  final bool negative;
  final bool strong;
  const _BalanceLine({
    required this.label,
    required this.amount,
    this.negative = false,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IntesharType.sans(
              12,
              color: strong ? cs.onSurface : cs.onSurfaceVariant,
              w: strong ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: IntesharSpacing.sm2),
        Text(
          '${negative && amount != 0 ? '−' : ''}${Formatters.iqd(amount.round())}',
          style: IntesharType.mono(
            12,
            color: strong ? cs.onSurface : cs.onSurfaceVariant,
            w: strong ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _LowStockCard extends ConsumerWidget {
  final Map<String, ({String name, int count})> lowSkus;

  /// UX-47: the line that decided these SKUs are "low". Without it "12 left"
  /// cannot be told apart from "nearly out" — the reader has no idea whether
  /// the bar was set at 20 or at 500.
  final int threshold;

  /// UX-28: whether this account has anyone above it to ask for cards.
  final bool canRequest;
  final AppLocalizations l;

  const _LowStockCard({
    required this.lowSkus,
    required this.threshold,
    required this.canRequest,
    required this.l,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    // The ask is prefilled with exactly what is running out — the reader of the
    // message should not have to ask "which cards?".
    final lowNames = lowSkus.values.map((e) => e.name).join(ar ? '، ' : ', ');

    return InkCard(
      density: CardDensity.flush,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.dashLowStock,
                        style: IntesharType.sans(
                          14,
                          color: cs.onSurface,
                          w: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ar
                            ? 'أقل من $threshold بطاقة'
                            : 'below $threshold cards',
                        style: IntesharType.sans(12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (canRequest)
                  _ViewAllLink(
                    label: ar ? 'طلب كروت' : 'Request cards',
                    onTap: () => showSupplyRequest(
                      context,
                      ref,
                      kind: SupplyRequestKind.stock,
                      category: lowNames,
                      // One SKU: the count is unambiguous and worth quoting.
                      // Several: it would read as a total that means nothing.
                      current: lowSkus.length == 1
                          ? lowSkus.values.first.count
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const Hairline(),
          if (lowSkus.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: context.status.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: context.status.success,
                    ),
                  ),
                  const SizedBox(width: IntesharSpacing.md),
                  Expanded(
                    child: Text(
                      l.dashAllHealthy,
                      style: IntesharType.sans(
                        14,
                        color: context.status.success,
                        w: IntesharWeight.semibold,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...lowSkus.entries.toList().asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      20,
                      12,
                      20,
                      12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.value.name,
                            style: IntesharType.sans(
                              14,
                              color: cs.onSurface,
                              w: IntesharWeight.semibold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: IntesharSpacing.sm),
                        Text(
                          '${e.value.count} ${l.dashUnitsLeft}',
                          style: IntesharType.sans(
                            12,
                            // Low, not broken — same tone as the KPI tile above.
                            color: context.status.warn,
                            w: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < lowSkus.length - 1) const Hairline(),
                ],
              );
            }),
        ],
      ),
    );
  }
}
