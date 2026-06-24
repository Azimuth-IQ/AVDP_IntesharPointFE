import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  List<AppTransaction>? _all;
  Map<String, Entity> _entityCache = {};
  Object? _error;
  bool _loading = true;
  String? _currentEntityId;

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
      if (auth is AuthAuthenticated) {
        _currentEntityId = auth.entity.id;
      } else {
        _currentEntityId = await sessionStorage.getCurrentEntityId();
      }

      final api = ref.read(apiClientProvider);
      final txRepo = TransactionRepository(api);
      final all = await txRepo.readAll();

      final relevant = all
          .where((t) => t.sourceId == _currentEntityId || t.destinationId == _currentEntityId)
          .toList();
      relevant.sort((a, b) {
        final da = '${a.date} ${a.time}';
        final db = '${b.date} ${b.time}';
        return db.compareTo(da);
      });

      final entityRepo = EntityRepository(api);
      final ids = <String>{};
      for (final t in relevant) {
        ids.add(t.sourceId);
        ids.add(t.destinationId);
      }
      final cache = <String, Entity>{};
      for (final id in ids) {
        try {
          cache[id] = await entityRepo.read(id);
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _all = relevant;
          _entityCache = cache;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _rolePath() {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is AuthAuthenticated) {
      final role = auth.entity.type.name.toLowerCase();
      if (role == 'inteshar') return '/hq';
      return '/$role';
    }
    return '/hq';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // RBAC: only users who may create transfers see the create affordances. The
    // backend independently enforces this on POST /api/transactions/create.
    final auth = ref.watch(authStateProvider).valueOrNull;
    final canCreate = auth is! AuthAuthenticated ||
        auth.can({Capability.CREATE_TRANSACTIONS});
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final txns = _all ?? [];
    final outgoing = txns.where((t) => t.sourceId == _currentEntityId).length;
    final incoming = txns.length - outgoing;
    final completed = txns.where((t) => t.status == TransactionStatus.COMPLETED).length;

    return Scaffold(
      body: MaxWidthBox(
        child: Column(
          children: [
            PageHeader(
              eyebrow: l.navTransactions,
              title: l.navTransactions,
              subtitle: l.txnsSubtitle,
              trailing: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Tally(l.txnsTallyOut, outgoing, Theme.of(context).colorScheme.error),
                  _Tally(l.txnsTallyIn,  incoming, IntesharColors.sage),
                  _Tally(l.txnsTallyDone, completed, IntesharColors.saffronDeep),
                ],
              ),
            ),
            Expanded(
              child: txns.isEmpty
                  ? EmptyState(
                      message: l.txnsEmpty,
                      actionLabel: canCreate ? l.txnsCreateAction : null,
                      onAction: canCreate
                          ? () => context.push('${_rolePath()}/transactions/new')
                          : null,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: txns.length,
                        itemBuilder: (ctx, i) {
                          final tx = txns[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: _TxCard(
                              tx: tx,
                              currentEntityId: _currentEntityId ?? '',
                              entityCache: _entityCache,
                              onTap: () => _showDetail(tx),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.push('${_rolePath()}/transactions/new'),
              icon: const Icon(Icons.add),
              label: Text(l.newTxnTitle),
            )
          : null,
    );
  }

  void _showDetail(AppTransaction tx) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.62,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => _TxDetailSheet(
          tx: tx,
          entityCache: _entityCache,
          scrollController: scrollCtrl,
          currentEntityId: _currentEntityId ?? '',
        ),
      ),
    );
  }
}

// ── Tallies ─────────────────────────────────────────────────────────────────

class _Tally extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _Tally(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction card ────────────────────────────────────────────────────────

class _TxCard extends StatefulWidget {
  final AppTransaction tx;
  final String currentEntityId;
  final Map<String, Entity> entityCache;
  final VoidCallback onTap;
  const _TxCard({
    required this.tx,
    required this.currentEntityId,
    required this.entityCache,
    required this.onTap,
  });

  @override
  State<_TxCard> createState() => _TxCardState();
}

class _TxCardState extends State<_TxCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tx = widget.tx;
    final isOutgoing = tx.sourceId == widget.currentEntityId;
    final counterpartyId = isOutgoing ? tx.destinationId : tx.sourceId;
    final counterparty = widget.entityCache[counterpartyId];
    final counterpartyName = counterparty?.meta.name ?? counterpartyId;

    final totalItems = tx.lines.fold(0, (sum, l) => sum + (int.tryParse(l.amount) ?? 0));
    final totalValue = tx.lines.fold(0, (sum, l) => sum + (int.tryParse(l.lineTotal) ?? 0));

    final ruleColor = isOutgoing ? cs.error : IntesharColors.sage;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkCard(
        ruleColor: ruleColor,
        onTap: widget.onTap,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Direction avatar — circular yellow/sage with arrow.
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ruleColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOutgoing ? Icons.north_east : Icons.south_west,
                    color: ruleColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOutgoing ? l.txnsDirectionTo : l.txnsDirectionFrom,
                        style: TextStyle(
                          fontFamily: 'CodecPro',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ruleColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        counterpartyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'CodecPro',
                          fontSize: 17,
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${tx.date} · ${tx.time}',
                        style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.4),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.iqd(totalValue),
                      style: IntesharType.mono(16, color: cs.onSurface, w: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l.txnsUnitLineSummary(totalItems, tx.lines.length),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _TxStatusChip(status: tx.status),
                const Spacer(),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                    color: _hover ? IntesharColors.saffronDeep : cs.onSurfaceVariant,
                  ),
                  child: Row(
                    children: [
                      Text(l.txnsViewDetails),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 16, color: _hover ? IntesharColors.saffronDeep : cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status chip ─────────────────────────────────────────────────────────────

class _TxStatusChip extends StatelessWidget {
  final TransactionStatus status;
  const _TxStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (status) {
      TransactionStatus.PENDING    => (l.txnStatusPending,    cs.onSurfaceVariant,       Icons.access_time),
      TransactionStatus.PROCESSING => (l.txnStatusProcessing, IntesharColors.saffronDeep, Icons.sync),
      TransactionStatus.COMPLETED  => (l.txnStatusComplete,   IntesharColors.sage,       Icons.check),
      TransactionStatus.FAILED     => (l.txnStatusFailed,     cs.error,                  Icons.close),
    };
    return StampPill(label: label, color: color, icon: icon);
  }
}

// ── Detail sheet ────────────────────────────────────────────────────────────

class _TxDetailSheet extends StatelessWidget {
  final AppTransaction tx;
  final Map<String, Entity> entityCache;
  final ScrollController scrollController;
  final String currentEntityId;

  const _TxDetailSheet({
    required this.tx,
    required this.entityCache,
    required this.scrollController,
    required this.currentEntityId,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final srcName = entityCache[tx.sourceId]?.meta.name ?? tx.sourceId;
    final dstName = entityCache[tx.destinationId]?.meta.name ?? tx.destinationId;
    final grandTotal = tx.lines.fold(0, (s, l) => s + (int.tryParse(l.lineTotal) ?? 0));

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            IntesharStar(size: 28, color: cs.onSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.txnsDetailTitle,
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 18,
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            _TxStatusChip(status: tx.status),
          ],
        ),
        const SizedBox(height: 18),
        // Source/Destination diagram
        Row(
          children: [
            Expanded(
              child: _Endpoint(
                eyebrow: l.txnsFrom,
                name: srcName,
                id: tx.sourceId,
                accent: tx.sourceId == currentEntityId ? cs.error : cs.onSurfaceVariant,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.east, size: 22, color: cs.onSurfaceVariant),
            ),
            Expanded(
              child: _Endpoint(
                eyebrow: l.txnsTo,
                name: dstName,
                id: tx.destinationId,
                accent: tx.destinationId == currentEntityId ? IntesharColors.sage : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _MetaRow(l.txnsMetaReference, tx.id, mono: true),
        _MetaRow(l.txnsMetaIssued,    '${tx.date}  ·  ${tx.time}', mono: true),
        if (tx.processMessage.isNotEmpty)
          _MetaRow(l.txnsMetaNote, tx.processMessage),
        const SizedBox(height: 20),
        SectionLabel(l.txnsLineItems),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.outline),
            borderRadius: BorderRadius.circular(IntesharRadii.sm),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(IntesharRadii.sm)),
                  border: Border(bottom: BorderSide(color: cs.outline)),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(l.txnsColSku,   style: IntesharType.overline(color: cs.onSurfaceVariant))),
                    Expanded(child: Text(l.txnsColQty,   textAlign: TextAlign.right, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                    Expanded(flex: 2, child: Text(l.txnsColUnit,  textAlign: TextAlign.right, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                    Expanded(flex: 2, child: Text(l.txnsColTotal, textAlign: TextAlign.right, style: IntesharType.overline(color: cs.onSurfaceVariant))),
                  ],
                ),
              ),
              for (var i = 0; i < tx.lines.length; i++) ...[
                if (i != 0) Container(height: 1, color: cs.outline),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          tx.lines[i].sku,
                          style: IntesharType.mono(13, color: cs.onSurface, w: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '×${tx.lines[i].amount}',
                          textAlign: TextAlign.right,
                          style: IntesharType.mono(13, color: cs.onSurface),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          Formatters.iqd(tx.lines[i].price),
                          textAlign: TextAlign.right,
                          style: IntesharType.mono(13, color: cs.onSurface),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          Formatters.iqd(tx.lines[i].lineTotal),
                          textAlign: TextAlign.right,
                          style: IntesharType.mono(13, color: cs.onSurface, w: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            color: IntesharColors.saffron,
            borderRadius: BorderRadius.circular(IntesharRadii.md),
          ),
          child: Row(
            children: [
              Text(
                l.newTxnGrandTotal,
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: IntesharColors.ink.withValues(alpha: 0.78),
                ),
              ),
              const Spacer(),
              Text(
                Formatters.iqd(grandTotal),
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: IntesharColors.ink,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Endpoint extends StatelessWidget {
  final String eyebrow;
  final String name;
  final String id;
  final Color accent;
  const _Endpoint({required this.eyebrow, required this.name, required this.id, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 14, height: 1, color: accent),
              const SizedBox(width: 6),
              Text(eyebrow, style: IntesharType.overline(color: accent)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          SelectableText(
            id,
            style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _MetaRow(this.label, this.value, {this.mono = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label.toUpperCase(), style: IntesharType.overline(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono
                  ? IntesharType.mono(12.5, color: cs.onSurface, letterSpacing: 0.4)
                  : IntesharType.sans(13, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
