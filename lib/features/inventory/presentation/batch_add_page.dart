import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

class BatchAddPage extends ConsumerStatefulWidget {
  const BatchAddPage({super.key});

  @override
  ConsumerState<BatchAddPage> createState() => _BatchAddPageState();
}

class _BatchAddPageState extends ConsumerState<BatchAddPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.edit), text: 'Manual'),
            Tab(icon: Icon(Icons.table_chart), text: 'Excel'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              _ManualTab(),
              _ExcelTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Manual Tab ────────────────────────────────────────────────────────────────

class _ManualTab extends ConsumerStatefulWidget {
  const _ManualTab();

  @override
  ConsumerState<_ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends ConsumerState<_ManualTab> {
  List<ProductDefinition> _defs = [];
  Object? _loadError;
  bool _loading = true;

  ProductDefinition? _selectedDef;
  int _quantity = 10;
  bool _autoGenerate = true;
  final _startSerialCtrl = TextEditingController();
  final _startPinCtrl = TextEditingController();
  final _prefixCtrl = TextEditingController(text: 'SN');

  double _progress = 0;
  bool _importing = false;
  String? _importError;
  int _imported = 0;

  @override
  void initState() {
    super.initState();
    _loadDefs();
  }

  @override
  void dispose() {
    _startSerialCtrl.dispose();
    _startPinCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDefs() async {
    try {
      final api = ref.read(apiClientProvider);
      final repo = DefinitionRepository(api);
      final defs = await repo.readAll();
      if (mounted) {
        setState(() {
          _defs = defs;
          _loading = false;
          if (defs.isNotEmpty) _selectedDef = defs.first;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  String _entityId() {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is AuthAuthenticated) return auth.entity.id;
    return '';
  }

  Future<void> _import() async {
    if (_selectedDef == null) return;
    final def = _selectedDef!;
    final entityId = _entityId();
    if (entityId.isEmpty) return;

    setState(() {
      _importing = true;
      _progress = 0;
      _imported = 0;
      _importError = null;
    });

    final api = ref.read(apiClientProvider);
    final repo = ProductRepository(api);
    final rng = Random();

    for (var i = 0; i < _quantity; i++) {
      try {
        final String serial;
        final String pin;
        if (_autoGenerate) {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final rand = rng.nextInt(99999).toString().padLeft(5, '0');
          serial = '${_prefixCtrl.text.trim()}-$ts-$rand';
          pin = rng.nextInt(999999).toString().padLeft(6, '0');
        } else {
          serial = '${_startSerialCtrl.text.trim()}-${(i + 1).toString().padLeft(4, '0')}';
          pin = '${_startPinCtrl.text.trim()}-${(i + 1).toString().padLeft(4, '0')}';
        }

        await repo.create(Product(
          id: 'prod-${DateTime.now().millisecondsSinceEpoch}-$i',
          productDefinition: def,
          status: ProductStatus.AVAILABLE,
          serialNumber: serial,
          pin: pin,
          owners: [entityId],
          currentOwner: entityId,
        ));

        if (mounted) {
          setState(() {
            _imported = i + 1;
            _progress = (i + 1) / _quantity;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _importError = 'Failed at item ${i + 1}: $e';
            _importing = false;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $_imported products!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return ErrorState(error: _loadError!, onRetry: _loadDefs);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Product Definition',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<ProductDefinition>(
            initialValue: _selectedDef,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: _defs
                .map((d) => DropdownMenuItem(
                      value: d,
                      child: Text('${d.name} (${d.sku})'),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedDef = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Quantity: $_quantity',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              Slider(
                value: _quantity.toDouble(),
                min: 1,
                max: 500,
                divisions: 499,
                label: '$_quantity',
                onChanged: (v) =>
                    setState(() => _quantity = v.round()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-generate serial & PIN'),
            value: _autoGenerate,
            onChanged: (v) => setState(() => _autoGenerate = v),
          ),
          if (_autoGenerate) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _prefixCtrl,
              decoration: const InputDecoration(
                labelText: 'Serial prefix',
                hintText: 'SN',
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            TextField(
              controller: _startSerialCtrl,
              decoration: const InputDecoration(
                labelText: 'Serial number prefix',
                hintText: 'SN2024',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _startPinCtrl,
              decoration: const InputDecoration(
                labelText: 'PIN prefix',
                hintText: 'PIN2024',
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (_importing) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text('$_imported / $_quantity imported…'),
            const SizedBox(height: 16),
          ],
          if (_importError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _importError!,
                style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_importing || _selectedDef == null)
                  ? null
                  : _import,
              icon: const Icon(Icons.upload),
              label: Text('Import $_quantity Products'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Excel Tab ─────────────────────────────────────────────────────────────────

class _ExcelTab extends ConsumerStatefulWidget {
  const _ExcelTab();

  @override
  ConsumerState<_ExcelTab> createState() => _ExcelTabState();
}

class _ExcelTabState extends ConsumerState<_ExcelTab> {
  List<_ExcelRow>? _preview;
  List<ProductDefinition> _defs = [];
  ProductDefinition? _selectedDef;
  bool _loadingDefs = true;
  bool _importing = false;
  double _progress = 0;
  int _imported = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDefs();
  }

  Future<void> _loadDefs() async {
    try {
      final api = ref.read(apiClientProvider);
      final repo = DefinitionRepository(api);
      final defs = await repo.readAll();
      if (mounted) {
        setState(() {
          _defs = defs;
          _loadingDefs = false;
          if (defs.isNotEmpty) _selectedDef = defs.first;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingDefs = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read file bytes.');
      return;
    }

    // Parse CSV only for now (xlsx requires the excel package)
    if (file.extension?.toLowerCase() == 'csv') {
      _parseCsv(String.fromCharCodes(bytes));
    } else {
      setState(() =>
          _error = 'XLSX parsing requires the excel package. Use CSV for now.\n'
              'Format: serialNumber,pin (one per row, no header)');
    }
  }

  void _parseCsv(String content) {
    final rows = <_ExcelRow>[];
    final lines =
        content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    // Skip header if it looks like a header
    int start = 0;
    if (lines.isNotEmpty &&
        lines[0].toLowerCase().contains('serial')) {
      start = 1;
    }
    for (var i = start; i < lines.length; i++) {
      final parts = lines[i].split(',');
      if (parts.length >= 2) {
        rows.add(_ExcelRow(
          serial: parts[0].trim(),
          pin: parts[1].trim(),
        ));
      }
    }
    setState(() {
      _preview = rows;
      _error = null;
    });
  }

  String _entityId() {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is AuthAuthenticated) return auth.entity.id;
    return '';
  }

  Future<void> _import() async {
    if (_preview == null || _preview!.isEmpty || _selectedDef == null) return;
    final def = _selectedDef!;
    final entityId = _entityId();
    if (entityId.isEmpty) return;

    setState(() {
      _importing = true;
      _progress = 0;
      _imported = 0;
      _error = null;
    });

    final api = ref.read(apiClientProvider);
    final repo = ProductRepository(api);
    final rows = _preview!;

    for (var i = 0; i < rows.length; i++) {
      try {
        await repo.create(Product(
          id: 'prod-${DateTime.now().millisecondsSinceEpoch}-$i',
          productDefinition: def,
          status: ProductStatus.AVAILABLE,
          serialNumber: rows[i].serial,
          pin: rows[i].pin,
          owners: [entityId],
          currentOwner: entityId,
        ));
        if (mounted) {
          setState(() {
            _imported = i + 1;
            _progress = (i + 1) / rows.length;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Failed at row ${i + 1}: $e';
            _importing = false;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _importing = false;
        _preview = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $_imported products!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CSV Format',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const Text(
                    'serialNumber,pin\nSN0001,1234\nSN0002,5678',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_loadingDefs)
            const CircularProgressIndicator()
          else
            DropdownButtonFormField<ProductDefinition>(
              initialValue: _selectedDef,
              decoration: const InputDecoration(
                labelText: 'Product Definition',
                border: OutlineInputBorder(),
              ),
              items: _defs
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text('${d.name} (${d.sku})'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDef = v),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Pick CSV / XLSX File'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ],
          if (_preview != null && _preview!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Preview (${_preview!.length} rows)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: const Row(
                      children: [
                        Expanded(
                            child: Text('Serial',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold))),
                        Expanded(
                            child: Text('PIN',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  ...(_preview!.take(10).map(
                        (r) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(r.serial)),
                              Expanded(child: Text(r.pin)),
                            ],
                          ),
                        ),
                      )),
                  if (_preview!.length > 10)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '… and ${_preview!.length - 10} more rows',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_importing) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('$_imported / ${_preview!.length} imported…'),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_importing || _selectedDef == null)
                    ? null
                    : _import,
                icon: const Icon(Icons.upload),
                label: Text('Import ${_preview!.length} rows'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExcelRow {
  final String serial;
  final String pin;
  const _ExcelRow({required this.serial, required this.pin});
}
