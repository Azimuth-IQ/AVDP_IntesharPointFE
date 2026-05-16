import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

class DefinitionsPage extends ConsumerStatefulWidget {
  const DefinitionsPage({super.key});

  @override
  ConsumerState<DefinitionsPage> createState() => _DefinitionsPageState();
}

class _DefinitionsPageState extends ConsumerState<DefinitionsPage> {
  List<ProductDefinition>? _defs;
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
      final api = ref.read(apiClientProvider);
      final repo = DefinitionRepository(api);
      final defs = await repo.readAll();
      if (mounted) setState(() => _defs = defs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForm({ProductDefinition? existing}) async {
    final idCtrl = TextEditingController(
        text: existing?.id ??
            'def-${DateTime.now().millisecondsSinceEpoch}');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    final priceCtrl =
        TextEditingController(text: existing?.defaultPrice ?? '');
    final descCtrl =
        TextEditingController(text: existing?.description ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DefinitionFormSheet(
        title: existing == null ? 'New Definition' : 'Edit Definition',
        idCtrl: idCtrl,
        nameCtrl: nameCtrl,
        skuCtrl: skuCtrl,
        priceCtrl: priceCtrl,
        descCtrl: descCtrl,
        isNew: existing == null,
        onSave: () async {
          final api = ref.read(apiClientProvider);
          final repo = DefinitionRepository(api);
          final def = ProductDefinition(
            id: idCtrl.text.trim(),
            name: nameCtrl.text.trim(),
            sku: skuCtrl.text.trim().toUpperCase(),
            defaultPrice: priceCtrl.text.trim(),
            description: descCtrl.text.trim(),
          );
          if (existing == null) {
            await repo.create(def);
          } else {
            await repo.update(def);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  Future<void> _delete(ProductDefinition def) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Definition'),
        content: Text('Delete "${def.name}"? This may break existing products.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final api = ref.read(apiClientProvider);
      final repo = DefinitionRepository(api);
      await repo.delete(def.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final defs = _defs ?? [];

    return Scaffold(
      body: defs.isEmpty
          ? EmptyState(
              message: 'No product definitions yet',
              actionLabel: 'Add First',
              onAction: () => _showForm(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: defs.length,
                itemBuilder: (context, i) {
                  final def = defs[i];
                  return Dismissible(
                    key: ValueKey(def.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Icon(
                        Icons.delete,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                    confirmDismiss: (_) async {
                      await _delete(def);
                      return false; // We reload instead of removing from list
                    },
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            def.sku.isNotEmpty
                                ? def.sku.substring(0, 2)
                                : '?',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(def.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          'SKU: ${def.sku}  •  ${Formatters.iqd(def.defaultPrice)}',
                        ),
                        onTap: () => _showForm(existing: def),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _showForm(existing: def),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DefinitionFormSheet extends StatefulWidget {
  final String title;
  final TextEditingController idCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController skuCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController descCtrl;
  final bool isNew;
  final Future<void> Function() onSave;

  const _DefinitionFormSheet({
    required this.title,
    required this.idCtrl,
    required this.nameCtrl,
    required this.skuCtrl,
    required this.priceCtrl,
    required this.descCtrl,
    required this.isNew,
    required this.onSave,
  });

  @override
  State<_DefinitionFormSheet> createState() => _DefinitionFormSheetState();
}

class _DefinitionFormSheetState extends State<_DefinitionFormSheet> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: widget.nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.skuCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration:
                  const InputDecoration(labelText: 'SKU * (e.g. AC5)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Default Price (IQD) *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            if (widget.isNew) ...[
              const SizedBox(height: 12),
              TextField(
                controller: widget.idCtrl,
                decoration:
                    const InputDecoration(labelText: 'ID (auto-generated)'),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
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
                              SnackBar(content: Text('Error: $e')),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
