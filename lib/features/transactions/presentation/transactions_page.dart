import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

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

      // Filter to only transactions involving this entity
      final relevant = all.where((t) => t.sourceId == _currentEntityId || t.destinationId == _currentEntityId).toList();
      relevant.sort((a, b) {
        final da = '${a.date} ${a.time}';
        final db = '${b.date} ${b.time}';
        return db.compareTo(da); // newest first
      });

      // Pre-fetch entity names for display
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final txns = _all ?? [];

    return Scaffold(
      body: txns.isEmpty
          ? EmptyState(message: 'No transactions yet', actionLabel: 'Create Transaction', onAction: () => context.push('${_rolePath()}/transactions/new'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: txns.length,
                itemBuilder: (ctx, i) {
                  final tx = txns[i];
                  return _TxCard(tx: tx, currentEntityId: _currentEntityId ?? '', entityCache: _entityCache, onTap: () => _showDetail(tx));
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(onPressed: () => context.push('${_rolePath()}/transactions/new'), child: const Icon(Icons.add)),
    );
  }

  void _showDetail(AppTransaction tx) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => _TxDetailSheet(tx: tx, entityCache: _entityCache, scrollController: scrollCtrl),
      ),
    );
  }
}

class _TxCard extends StatelessWidget {
  final AppTransaction tx;
  final String currentEntityId;
  final Map<String, Entity> entityCache;
  final VoidCallback onTap;

  const _TxCard({required this.tx, required this.currentEntityId, required this.entityCache, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOutgoing = tx.sourceId == currentEntityId;
    final counterpartyId = isOutgoing ? tx.destinationId : tx.sourceId;
    final counterparty = entityCache[counterpartyId];
    final counterpartyName = counterparty?.meta.name ?? counterpartyId;

    final totalItems = tx.lines.fold(0, (sum, l) => sum + (int.tryParse(l.amount) ?? 0));
    final totalValue = tx.lines.fold(0, (sum, l) => sum + (int.tryParse(l.lineTotal) ?? 0));

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOutgoing ? Theme.of(context).colorScheme.tertiaryContainer : Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            isOutgoing ? Icons.arrow_upward : Icons.arrow_downward,
            color: isOutgoing ? Theme.of(context).colorScheme.onTertiaryContainer : Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(isOutgoing ? 'To: $counterpartyName' : 'From: $counterpartyName', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${tx.date} ${tx.time}  •  $totalItems items  •  ${Formatters.iqd(totalValue)}', style: Theme.of(context).textTheme.bodySmall),
        trailing: _StatusChip(status: tx.status),
        onTap: onTap,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final TransactionStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      TransactionStatus.PENDING => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      TransactionStatus.PROCESSING => (cs.secondaryContainer, cs.onSecondaryContainer),
      TransactionStatus.COMPLETED => (cs.primaryContainer, cs.onPrimaryContainer),
      TransactionStatus.FAILED => (cs.errorContainer, cs.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(
        status.name,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TxDetailSheet extends StatelessWidget {
  final AppTransaction tx;
  final Map<String, Entity> entityCache;
  final ScrollController scrollController;

  const _TxDetailSheet({required this.tx, required this.entityCache, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final srcName = entityCache[tx.sourceId]?.meta.name ?? tx.sourceId;
    final dstName = entityCache[tx.destinationId]?.meta.name ?? tx.destinationId;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Transaction', style: Theme.of(context).textTheme.titleMedium),
            _StatusChip(status: tx.status),
          ],
        ),
        const SizedBox(height: 4),
        Text('ID: ${tx.id}', style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 24),
        _Row('Date', '${tx.date} ${tx.time}'),
        _Row('From', srcName),
        _Row('To', dstName),
        if (tx.processMessage.isNotEmpty) _Row('Message', tx.processMessage),
        const Divider(height: 24),
        Text('Lines', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        ...tx.lines.map(
          (l) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('SKU: ${l.sku}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('× ${l.amount}'),
                const SizedBox(width: 16),
                Text(Formatters.iqd(l.price)),
                const SizedBox(width: 8),
                Text('= ${Formatters.iqd(l.lineTotal)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Total: ${Formatters.iqd(tx.lines.fold(0, (s, l) => s + (int.tryParse(l.lineTotal) ?? 0)))}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
