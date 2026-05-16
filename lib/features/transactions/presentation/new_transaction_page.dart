import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/transactions/data/transaction_repository.dart';
import 'package:inteshar/features/transactions/domain/transaction.dart';

class NewTransactionPage extends ConsumerStatefulWidget {
  const NewTransactionPage({super.key});

  @override
  ConsumerState<NewTransactionPage> createState() => _NewTransactionPageState();
}

class _NewTransactionPageState extends ConsumerState<NewTransactionPage> {
  Entity? _currentEntity;
  List<Entity> _children = [];
  List<ProductDefinition> _defs = [];

  Entity? _destination;
  final List<_LineItem> _lines = [];

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  AppTransaction? _result;

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
      if (auth is! AuthAuthenticated) throw Exception('Not authenticated');

      _currentEntity = auth.entity;
      final api = ref.read(apiClientProvider);
      final entityRepo = EntityRepository(api);
      final defRepo = DefinitionRepository(api);

      // Load children as potential destinations using parent field — immune to
      // the backend bug that clears childrenIds on every entity PUT.
      final children = await entityRepo.readDirectChildren(_currentEntity!.id);

      final defs = await defRepo.readAll();

      if (mounted) {
        setState(() {
          _children = children;
          _defs = defs;
          if (children.isNotEmpty) _destination = children.first;
          if (defs.isNotEmpty && _lines.isEmpty) {
            _lines.add(_LineItem(def: defs.first, amount: 1));
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_destination == null || _lines.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final txRepo = TransactionRepository(api);
      final now = DateTime.now();

      final lines = _lines
          .where((l) => l.amount > 0)
          .map(
            (l) => TransactionLine(
              id: 'line_${DateTime.now().millisecondsSinceEpoch}',
              sku: l.def.sku,
              amount: l.amount.toString(),
              price: l.price ?? l.def.defaultPrice,
              lineTotal: _lineTotal(l),
            ),
          )
          .toList();

      if (lines.isEmpty) throw Exception('Add at least one line item');

      final tx = AppTransaction(date: Formatters.date(now), time: Formatters.time(now), sourceId: _currentEntity!.id, destinationId: _destination!.id, lines: lines);

      AppTransaction created = await txRepo.create(tx);

      // Poll until COMPLETED or FAILED (max 15 seconds)
      int polls = 0;
      while (polls < 15 && created.status != TransactionStatus.COMPLETED && created.status != TransactionStatus.FAILED) {
        await Future.delayed(const Duration(seconds: 1));
        created = await txRepo.read(created.id);
        polls++;
      }

      if (mounted) {
        setState(() {
          _result = created;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  String _lineTotal(_LineItem l) {
    final price = int.tryParse(l.price ?? l.def.defaultPrice) ?? 0;
    return (price * l.amount).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Transaction'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _result != null
          ? _ResultView(result: _result!)
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Source (read-only)
          _SectionHeader('Source'),
          Card(
            child: ListTile(leading: const Icon(Icons.store), title: Text(_currentEntity?.meta.name ?? '—'), subtitle: Text(_currentEntity?.type.label ?? '')),
          ),
          const SizedBox(height: 16),

          // Destination
          _SectionHeader('Destination'),
          if (_children.isEmpty)
            const Text('No child entities. Add children first via the hierarchy.', style: TextStyle(color: Colors.red))
          else
            DropdownButtonFormField<Entity>(
              initialValue: _destination,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: _children.map((e) => DropdownMenuItem(value: e, child: Text('${e.meta.name} (${e.type.label})'))).toList(),
              onChanged: (v) => setState(() => _destination = v),
            ),
          const SizedBox(height: 16),

          // Lines
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader('Lines'),
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: _defs.isEmpty ? null : () => setState(() => _lines.add(_LineItem(def: _defs.first, amount: 1))),
              ),
            ],
          ),
          ..._lines.asMap().entries.map((entry) {
            final i = entry.key;
            final line = entry.value;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<ProductDefinition>(
                            initialValue: line.def,
                            decoration: const InputDecoration(labelText: 'Product', isDense: true),
                            items: _defs.map((d) => DropdownMenuItem(value: d, child: Text('${d.name} (${d.sku})'))).toList(),
                            onChanged: (d) {
                              if (d != null) {
                                setState(() => _lines[i] = _lines[i].copyWith(def: d));
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () => setState(() => _lines.removeAt(i)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: line.amount.toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                            onChanged: (v) => setState(() {
                              _lines[i] = _lines[i].copyWith(amount: int.tryParse(v) ?? 1);
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: line.price ?? line.def.defaultPrice,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Price (IQD)', isDense: true),
                            onChanged: (v) => setState(() {
                              _lines[i] = _lines[i].copyWith(price: v);
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Total:\n${Formatters.iqd(_lineTotal(line))}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 8),
          // Grand total
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Grand Total: ${Formatters.iqd(_lines.fold(0, (s, l) => s + (int.tryParse(_lineTotal(l)) ?? 0)))}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_submitting || _destination == null || _lines.isEmpty) ? null : _submit,
              icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              label: Text(_submitting ? 'Submitting…' : 'Submit Transaction'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final AppTransaction result;
  const _ResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    final success = result.status == TransactionStatus.COMPLETED;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(success ? Icons.check_circle : Icons.error, size: 80, color: success ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(success ? 'Transaction Completed!' : 'Transaction Failed', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            if (result.processMessage.isNotEmpty) ...[const SizedBox(height: 8), Text(result.processMessage, textAlign: TextAlign.center)],
            const SizedBox(height: 8),
            Text('ID: ${result.id}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.pop(), child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}

class _LineItem {
  final ProductDefinition def;
  final int amount;
  final String? price;

  const _LineItem({required this.def, required this.amount, this.price});

  _LineItem copyWith({ProductDefinition? def, int? amount, String? price}) => _LineItem(def: def ?? this.def, amount: amount ?? this.amount, price: price ?? this.price);
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
