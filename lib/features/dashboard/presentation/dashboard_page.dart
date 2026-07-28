import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/core/api/paged.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
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

  const _DashData({
    required this.stock,
    required this.recentTransfers,
    required this.childCount,
    required this.children,
    required this.balance,
  });
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
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
      ]);
      final stock = results[0] as List<SkuSummary>;
      final transfers = (results[1] as List<GrantRow>).toList()
        ..sort((a, b) => '${b.date} ${b.time}'.compareTo('${a.date} ${a.time}'));
      final children = (results[2] as Paged<EntitySummaryRow>).items;
      // Balance is best-effort: a failure here must not blank the dashboard.
      AgentBalance balance = const AgentBalance();
      try {
        balance = await PricingRepository(api).balance();
      } catch (_) {}
      setState(() {
        _data = _DashData(
          stock: stock,
          recentTransfers: transfers.take(5).toList(),
          childCount: entity.childrenIds.length,
          children: children,
          balance: balance,
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
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [ErrorState(error: _error!, onRetry: _load)],
              )
            : _DashContent(
                entity: entity,
                data: _data!,
                onRefresh: _load,
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
        // ── Slim header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 28, 24, 0),
          child: _SlimHeader(entity: entity),
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
              showInventory: entity.type.inventoryBacked,
            ),
          ),

        // ── Two-column body ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
          child: _BodyRow(
            entity: entity,
            transfers: data.recentTransfers,
            lowSkus: lowSkus,
            l: l,
          ),
        ),
      ],
    );
  }
}

// ─── Slim header ─────────────────────────────────────────────────────────────

class _SlimHeader extends StatelessWidget {
  final Entity entity;
  const _SlimHeader({required this.entity});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final subtitle = entity.type == EntityType.INTESHAR
        ? l.dashPlatformOverview
        : entity.meta.slogan.isNotEmpty
        ? entity.meta.slogan
        : entity.type.label;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entity.meta.name,
                style: IntesharType.display(
                  28,
                  color: cs.onSurface,
                  w: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: IntesharType.sans(13, color: IntesharColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        RoleBadge(type: entity.type),
      ],
    );
  }
}

// ─── Store-admin POS note ──────────────────────────────────────────────────────

/// Shown only on a STORE-ADMIN dashboard: this console manages the shop, but the
/// actual selling counter is a separate point-of-sale login (the USER-role
/// account on `/pos`). Prevents an owner who signed in with the admin account
/// from concluding the app can't sell.
class _StorePosNote extends StatelessWidget {
  const _StorePosNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.tones.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: context.tones.brand.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.point_of_sale_outlined, size: 20, color: context.tones.brandInk),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ar ? 'هذه شاشة إدارة المتجر' : 'This is the shop management console',
                  style: IntesharType.sans(13.5, color: cs.onSurface, w: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  ar
                      ? 'للبيع والطباعة، سجّل الدخول بحساب نقطة البيع (حساب المستخدم) على تطبيق نقطة البيع.'
                      : 'To sell and print, sign in with your point-of-sale account (the USER login) in the POS app.',
                  style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
                ),
              ],
            ),
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
  final bool showInventory;

  const _KpiRow({
    required this.childCount,
    required this.availableCount,
    required this.availableSkuCount,
    required this.lowStockCount,
    required this.showInventory,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
          tint: const Color(0xFF2563EB),
        ),
      if (showInventory)
        _KpiTile(
          label: l.dashKpiLowStock,
          value: Formatters.money(lowStockCount),
          caption: lowStockCount == 0
              ? l.dashKpiAllHealthy
              : l.dashKpiNeedsAttention,
          icon: Icons.warning_amber_rounded,
          tint: IntesharColors.oxblood,
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
                    padding: const EdgeInsets.only(bottom: 12),
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
              padding: const EdgeInsets.only(bottom: 12),
              // IntrinsicHeight + stretch makes every tile in the row adopt the
              // tallest tile's height. Labels (maxLines: 2) and captions wrap to
              // different line counts per tile — especially in Arabic — which
              // otherwise leaves the cards visibly uneven.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < rowTiles.length; j++) ...[
                      if (j > 0) const SizedBox(width: 12),
                      Expanded(child: rowTiles[j]),
                    ],
                    // Fill remaining cols with invisible spacers so row is uniform
                    for (var k = rowTiles.length; k < cols; k++) ...[
                      const SizedBox(width: 12),
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
                    color: IntesharColors.inkSoft,
                    w: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: IntesharType.display(
                  30,
                  color: cs.onSurface,
                  w: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: IntesharType.sans(12, color: IntesharColors.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Body row (transactions + low stock) ─────────────────────────────────────

/// Route prefix for the signed-in role, used to deep-link into sections.
String _rolePrefix(EntityType type) => switch (type) {
  EntityType.INTESHAR => '/hq',
  EntityType.AGENT1 => '/agent1',
  EntityType.AGENT2 => '/agent2',
  EntityType.STORE => '/store',
};

class _BodyRow extends StatelessWidget {
  final Entity entity;
  final List<GrantRow> transfers;
  final Map<String, ({String name, int count})> lowSkus;
  final AppLocalizations l;

  const _BodyRow({
    required this.entity,
    required this.transfers,
    required this.lowSkus,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final wide = c.maxWidth >= 900;
        // Only agents have the full transfers page (B-056); HQ/stores see the
        // card without a deep link.
        final hasTransfersPage = entity.type == EntityType.AGENT1 ||
            entity.type == EntityType.AGENT2;
        final txnCard = _RecentTransfersCard(
          transfers: transfers,
          selfId: entity.id,
          onViewAll: hasTransfersPage
              ? () => ctx.go('${_rolePrefix(entity.type)}/transfers')
              : null,
          l: l,
        );
        // Low-stock is an inventory concern — only for inventory-backed tiers.
        // Sub Agents & Stores draw-on-print and hold no cards (B-042).
        if (!entity.type.inventoryBacked) return txnCard;
        final lowCard = _LowStockCard(lowSkus: lowSkus, l: l);

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: txnCard),
              const SizedBox(width: 16),
              SizedBox(width: 360, child: lowCard),
            ],
          );
        }
        return Column(children: [txnCard, const SizedBox(height: 16), lowCard]);
      },
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
      padding: EdgeInsets.zero,
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
              final tint = sent ? cs.error : IntesharColors.sage;
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
                            borderRadius: BorderRadius.circular(7),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            sent ? Icons.north_east : Icons.south_west,
                            size: 16,
                            color: tint,
                          ),
                        ),
                        const SizedBox(width: 10),
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
                                  13,
                                  color: cs.onSurface,
                                  w: FontWeight.w600,
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
                            13,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: IntesharType.sans(
                13,
                color: cs.onSurfaceVariant,
                w: FontWeight.w500,
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

class _BalanceCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
    final tones = context.tones;
    // B-094: a WHITE card with a brand accent rule, not a solid gold slab. The
    // number is the hero — big ink numerals on paper read as money, and gold is
    // reserved for the thin accent + the label, so it stays meaningful.
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(IntesharRadii.lg),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: IntesharShadows.elev1,
      ),
      child: Row(
        children: [
          // The one flash of brand colour on the card.
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: tones.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: IntesharType.overline(color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(
                  Formatters.iqd(balance.available.round()),
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
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
    );
  }
}

class _LowStockCard extends StatelessWidget {
  final Map<String, ({String name, int count})> lowSkus;
  final AppLocalizations l;

  const _LowStockCard({required this.lowSkus, required this.l});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 14),
            child: Text(
              l.dashLowStock,
              style: IntesharType.sans(
                14,
                color: cs.onSurface,
                w: FontWeight.w700,
              ),
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
                      color: IntesharColors.sage.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: IntesharColors.sage,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.dashAllHealthy,
                      style: IntesharType.sans(
                        13,
                        color: IntesharColors.sage,
                        w: FontWeight.w600,
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
                              13,
                              color: cs.onSurface,
                              w: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${e.value.count} ${l.dashUnitsLeft}',
                          style: IntesharType.sans(
                            12,
                            color: IntesharColors.oxblood,
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
