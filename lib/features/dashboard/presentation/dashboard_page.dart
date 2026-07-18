import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

// ─── Data container ─────────────────────────────────────────────────────────

class _DashData {
  final List<Product> products;
  final List<AppTransaction> allTxns;
  final Map<String, String> entityNames; // id → meta.name
  final int childCount; // direct children, counted via parent links
  final List<Entity>
  children; // direct children (for the balance transfer picker)
  final AgentBalance balance;

  const _DashData({
    required this.products,
    required this.allTxns,
    required this.entityNames,
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
      final results = await Future.wait([
        ProductRepository(api).readByEntity(entity.id),
        TransactionRepository(api).readAll(),
        EntityRepository(api).readAll(),
      ]);
      final products = results[0] as List<Product>;
      final allTxns = results[1] as List<AppTransaction>;
      final allEntities = results[2] as List<Entity>;
      final entityNames = <String, String>{
        for (final e in allEntities) e.id: e.meta.name,
      };
      final children = allEntities.where((e) => e.parent == entity.id).toList();
      // Balance is best-effort: a failure here must not blank the dashboard.
      AgentBalance balance = const AgentBalance();
      try {
        balance = await PricingRepository(api).balance();
      } catch (_) {}
      setState(() {
        _data = _DashData(
          products: products,
          allTxns: allTxns,
          entityNames: entityNames,
          childCount: children.length,
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

    // Compute KPI values
    final availableProducts = data.products
        .where((p) => p.status == ProductStatus.AVAILABLE)
        .toList();
    final availableSkus = <String>{
      for (final p in availableProducts) p.productDefinition.sku,
    };

    // Group available count by SKU
    final availableCountBySku = <String, int>{};
    for (final p in availableProducts) {
      availableCountBySku[p.productDefinition.sku] =
          (availableCountBySku[p.productDefinition.sku] ?? 0) + 1;
    }

    // Low stock: SKUs below this account's configured threshold (falls back to
    // EntityMeta.defaultLowStockThreshold when the entity hasn't set one).
    final lowStockThreshold = entity.meta.effectiveLowStockThreshold;
    final lowSkus = <String, ({String name, int count})>{};
    for (final sku in availableCountBySku.keys) {
      if (availableCountBySku[sku]! < lowStockThreshold) {
        final name = data.products
            .firstWhere((p) => p.productDefinition.sku == sku)
            .productDefinition
            .name;
        lowSkus[sku] = (name: name, count: availableCountBySku[sku]!);
      }
    }

    // Transactions involving this entity
    final myTxns = data.allTxns
        .where((t) => t.sourceId == entity.id || t.destinationId == entity.id)
        .toList();
    // Sort descending by date then time
    myTxns.sort((a, b) {
      final dc = b.date.compareTo(a.date);
      return dc != 0 ? dc : b.time.compareTo(a.time);
    });
    final recentTxns = myTxns.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
      children: [
        // ── Slim header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 28, 24, 0),
          child: _SlimHeader(entity: entity),
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
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 0),
          child: _KpiRow(
            childCount: data.childCount,
            availableCount: availableProducts.length,
            availableSkuCount: availableSkus.length,
            txnCount: myTxns.length,
            lowStockCount: lowSkus.length,
          ),
        ),

        // ── Two-column body ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
          child: _BodyRow(
            entity: entity,
            recentTxns: recentTxns,
            entityNames: data.entityNames,
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

// ─── KPI tile row ─────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final int childCount;
  final int availableCount;
  final int availableSkuCount;
  final int txnCount;
  final int lowStockCount;

  const _KpiRow({
    required this.childCount,
    required this.availableCount,
    required this.availableSkuCount,
    required this.txnCount,
    required this.lowStockCount,
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
        tint: IntesharColors.saffron,
      ),
      _KpiTile(
        label: l.dashKpiStock,
        value: Formatters.money(availableCount),
        caption: l.dashKpiSkusCount(availableSkuCount),
        icon: Icons.inventory_2_outlined,
        tint: const Color(0xFF2563EB),
      ),
      _KpiTile(
        label: l.dashKpiTransactions,
        value: Formatters.money(txnCount),
        caption: l.dashKpiThisAccount,
        icon: Icons.swap_horiz,
        tint: IntesharColors.sage,
      ),
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
  final List<AppTransaction> recentTxns;
  final Map<String, String> entityNames;
  final Map<String, ({String name, int count})> lowSkus;
  final AppLocalizations l;

  const _BodyRow({
    required this.entity,
    required this.recentTxns,
    required this.entityNames,
    required this.lowSkus,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final wide = c.maxWidth >= 900;
        final txnCard = _RecentTransactionsCard(
          txns: recentTxns,
          entityNames: entityNames,
          onViewAll: entity.type == EntityType.STORE
              ? null
              : () => ctx.go('${_rolePrefix(entity.type)}/transactions'),
          l: l,
        );
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

// ─── Recent transactions card ─────────────────────────────────────────────────

class _RecentTransactionsCard extends StatelessWidget {
  final List<AppTransaction> txns;
  final Map<String, String> entityNames;

  /// Deep-link to the full transactions page; null hides the link (stores
  /// have no transactions route — they hold no cards since draw-on-print).
  final VoidCallback? onViewAll;
  final AppLocalizations l;

  const _RecentTransactionsCard({
    required this.txns,
    required this.entityNames,
    required this.onViewAll,
    required this.l,
  });

  String _resolveName(String id) => entityNames[id] ?? id;

  Color _statusColor(TransactionStatus s) {
    return switch (s) {
      TransactionStatus.COMPLETED => IntesharColors.sage,
      TransactionStatus.FAILED => IntesharColors.oxblood,
      _ => IntesharColors.saffronDeep,
    };
  }

  String _statusLabel(TransactionStatus s, AppLocalizations l) {
    return switch (s) {
      TransactionStatus.COMPLETED => l.txnStatusComplete,
      TransactionStatus.PENDING => l.txnStatusPending,
      TransactionStatus.PROCESSING => l.txnStatusProcessing,
      TransactionStatus.FAILED => l.txnStatusFailed,
    };
  }

  ({
    String route,
    String meta,
    String skuLabel,
    int qty,
    int amount,
    TransactionStatus status,
  })
  _rowData(int i) {
    final tx = txns[i];
    final shortId = tx.id.length > 8 ? tx.id.substring(0, 8) : tx.id;
    final skuLabel = tx.lines.isEmpty
        ? '—'
        : tx.lines.length == 1
        ? tx.lines.first.sku
        : '${tx.lines.length} SKUs';
    return (
      route: '${_resolveName(tx.sourceId)} → ${_resolveName(tx.destinationId)}',
      meta: '#$shortId · ${tx.date} ${tx.time}',
      skuLabel: skuLabel,
      qty: tx.lines.fold(0, (s, ln) => s + (int.tryParse(ln.amount) ?? 0)),
      amount: tx.lines.fold(
        0,
        (s, ln) => s + (int.tryParse(ln.lineTotal) ?? 0),
      ),
      status: tx.status,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, c) {
          // The columnar table needs room for the fixed SKU/qty/status/amount
          // columns; narrower than this it would overflow, so stack each row.
          final compact = c.maxWidth < 500;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.dashRecentTransactions,
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

              if (txns.isEmpty)
                _InlineEmpty(message: l.dashNoTransactions)
              else if (compact)
                ...List.generate(
                  txns.length,
                  (i) => _CompactTxnRow(
                    data: _rowData(i),
                    last: i == txns.length - 1,
                    statusLabel: _statusLabel,
                    statusColor: _statusColor,
                    l: l,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
                  child: _TxnHeaderRow(l: l),
                ),
                const Hairline(),
                ...List.generate(
                  txns.length,
                  (i) => _ColumnarTxnRow(
                    data: _rowData(i),
                    last: i == txns.length - 1,
                    statusLabel: _statusLabel,
                    statusColor: _statusColor,
                    l: l,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

typedef _TxnRowData = ({
  String route,
  String meta,
  String skuLabel,
  int qty,
  int amount,
  TransactionStatus status,
});

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
                color: IntesharColors.saffronDeep,
                w: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: IntesharColors.saffronDeep,
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
class _CompactTxnRow extends StatelessWidget {
  final _TxnRowData data;
  final bool last;
  final String Function(TransactionStatus, AppLocalizations) statusLabel;
  final Color Function(TransactionStatus) statusColor;
  final AppLocalizations l;
  const _CompactTxnRow({
    required this.data,
    required this.last,
    required this.statusLabel,
    required this.statusColor,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.route,
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
                  StampPill(
                    label: statusLabel(data.status, l),
                    color: statusColor(data.status),
                    fontSize: 10,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      data.meta,
                      style: IntesharType.mono(
                        10,
                        color: IntesharColors.inkSoft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Formatters.iqd(data.amount),
                    style: IntesharType.mono(
                      12,
                      color: cs.onSurface,
                      w: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!last) const Hairline(),
      ],
    );
  }
}

/// Columnar transaction row for wide widths (desktop, tablet).
class _ColumnarTxnRow extends StatelessWidget {
  final _TxnRowData data;
  final bool last;
  final String Function(TransactionStatus, AppLocalizations) statusLabel;
  final Color Function(TransactionStatus) statusColor;
  final AppLocalizations l;
  const _ColumnarTxnRow({
    required this.data,
    required this.last,
    required this.statusLabel,
    required this.statusColor,
    required this.l,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.route,
                      style: IntesharType.sans(
                        13,
                        color: cs.onSurface,
                        w: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data.meta,
                      style: IntesharType.mono(
                        10,
                        color: IntesharColors.inkSoft,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  data.skuLabel,
                  style: IntesharType.sans(12, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  Formatters.money(data.qty),
                  textAlign: TextAlign.end,
                  style: IntesharType.sans(12, color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StampPill(
                    label: statusLabel(data.status, l),
                    color: statusColor(data.status),
                    fontSize: 10,
                  ),
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  Formatters.iqd(data.amount),
                  textAlign: TextAlign.end,
                  style: IntesharType.mono(11, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (!last) const Hairline(),
      ],
    );
  }
}

class _TxnHeaderRow extends StatelessWidget {
  final AppLocalizations l;
  const _TxnHeaderRow({required this.l});

  @override
  Widget build(BuildContext context) {
    final style = IntesharType.sans(
      11,
      color: IntesharColors.inkSoft,
      w: FontWeight.w700,
    );
    return Row(
      children: [
        Expanded(child: Text(l.dashColRoute, style: style)),
        SizedBox(width: 80, child: Text(l.dashColSku, style: style)),
        SizedBox(
          width: 44,
          child: Text(l.dashColQty, textAlign: TextAlign.end, style: style),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 96, child: Text(l.dashColStatus, style: style)),
        SizedBox(
          width: 100,
          child: Text(l.dashColAmount, textAlign: TextAlign.end, style: style),
        ),
      ],
    );
  }
}

// ─── Virtual balance card ─────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final Entity entity;
  final AgentBalance balance;
  final List<Entity> children;
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
    final showTransfer = canTransfer && children.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: IntesharColors.saffron,
        borderRadius: BorderRadius.circular(IntesharRadii.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: IntesharType.overline(
                    color: IntesharColors.ink.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Formatters.iqd(balance.available.round()),
                  style: const TextStyle(
                    fontFamily: 'CodecPro',
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: IntesharColors.ink,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          if (showTransfer)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: IntesharColors.ink,
                foregroundColor: IntesharColors.saffron,
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _TransferSheet(
                  children: children,
                  balance: balance,
                  onGranted: onGranted,
                ),
              ),
              icon: const Icon(Icons.north_east, size: 16),
              label: Text(ar ? 'تحويل رصيد' : 'Transfer'),
            ),
        ],
      ),
    );
  }
}

class _TransferSheet extends ConsumerStatefulWidget {
  final List<Entity> children;
  final AgentBalance balance;
  final VoidCallback onGranted;
  const _TransferSheet({
    required this.children,
    required this.balance,
    required this.onGranted,
  });

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  Entity? _dest;
  final _amount = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.children.isNotEmpty) _dest = widget.children.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final dest = _dest;
    final amount = num.tryParse(_amount.text.trim());
    if (dest == null) return;
    if (amount == null || amount <= 0) {
      setState(
        () => _error = ar ? 'أدخل مبلغاً صحيحاً' : 'Enter a valid amount',
      );
      return;
    }
    if (amount > widget.balance.available) {
      setState(
        () => _error = ar
            ? 'الرصيد غير كافٍ (المتاح ${Formatters.iqd(widget.balance.available.round())})'
            : 'Insufficient balance (available ${Formatters.iqd(widget.balance.available.round())})',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'تأكيد التحويل' : 'Confirm transfer'),
        content: Text(
          ar
              ? 'سيتم تحويل ${Formatters.iqd(amount.round())} إلى "${dest.meta.name}". لا يمكن التراجع عن هذا الإجراء.'
              : 'You are about to transfer ${Formatters.iqd(amount.round())} to "${dest.meta.name}". This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ar ? 'إرسال' : 'Send')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await PricingRepository(
        ref.read(apiClientProvider),
      ).grant(destId: dest.id, amount: amount);
      if (mounted) {
        Navigator.pop(context);
        widget.onGranted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ar ? 'تم تحويل الرصيد' : 'Balance transferred'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionLabel(ar ? 'تحويل رصيد' : 'Transfer balance'),
          const SizedBox(height: 12),
          DropdownButtonFormField<Entity>(
            initialValue: _dest,
            isExpanded: true,
            decoration: InputDecoration(labelText: ar ? 'إلى' : 'To'),
            items: widget.children
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text('${e.meta.name} (${e.type.label})'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _dest = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: ar ? 'المبلغ' : 'Amount',
              suffixText: 'IQD',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: cs.error, fontSize: 12.5)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(ar ? 'تحويل' : 'Transfer'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Low stock card ──────────────────────────────────────────────────────────

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
