import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/files/web_download.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

String _newProductId() {
  final rand = Random.secure();
  final hex =
      List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join();
  return 'prod-${DateTime.now().millisecondsSinceEpoch}-$hex';
}

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
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: l.batchAddEyebrow,
            title: l.batchAddTitle,
            subtitle: l.batchAddSubtitle,
          ),
          // Pill tab selector
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: IntesharColors.saffron,
                  borderRadius: BorderRadius.circular(999),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: IntesharColors.ink,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: IntesharType.sans(13, w: FontWeight.w800),
                unselectedLabelStyle: IntesharType.sans(13, w: FontWeight.w700),
                tabs: [
                  Tab(text: l.batchAddTabSingle),
                  Tab(text: l.batchAddTabCsvXlsx),
                ],
              ),
            ),
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
      ),
    );
  }
}

// ── Single Voucher Tab ────────────────────────────────────────────────────────

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
  final _serialCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _serialFocus = FocusNode();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDefs();
  }

  @override
  void dispose() {
    _serialCtrl.dispose();
    _pinCtrl.dispose();
    _serialFocus.dispose();
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

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    final def = _selectedDef;
    if (def == null) return;

    final serial = _serialCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    if (serial.isEmpty) {
      setState(() => _error = l.addVoucherSerialRequired);
      return;
    }
    if (pin.isEmpty) {
      setState(() => _error = l.addVoucherPinRequired);
      return;
    }

    final entityId = _entityId();
    if (entityId.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(apiClientProvider);
    final repo = ProductRepository(api);

    try {
      final existing = await repo.readByEntity(entityId);
      final dup = existing.any(
        (p) => p.serialNumber.trim().toLowerCase() == serial.toLowerCase(),
      );
      if (dup) {
        if (mounted) {
          setState(() {
            _saving = false;
            _error = l.addVoucherDuplicateSerial(serial);
          });
        }
        return;
      }

      await repo.create(Product(
        id: _newProductId(),
        productDefinition: def,
        status: ProductStatus.AVAILABLE,
        serialNumber: serial,
        pin: pin,
        owners: [entityId],
        currentOwner: entityId,
      ));

      if (mounted) {
        setState(() {
          _saving = false;
          _serialCtrl.clear();
          _pinCtrl.clear();
        });
        _serialFocus.requestFocus();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.addVoucherSaved)));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return ErrorState(error: _loadError!, onRetry: _loadDefs);
    }

    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(l.addVoucherDenomination),
            DropdownButtonFormField<ProductDefinition>(
              initialValue: _selectedDef,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: l.batchAddProductDefinition),
              items: _defs
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text('${d.name} (${d.sku})'),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDef = v),
            ),
            const SizedBox(height: 22),
            SectionLabel(l.addVoucherSerial),
            TextField(
              controller: _serialCtrl,
              focusNode: _serialFocus,
              decoration: InputDecoration(
                labelText: l.addVoucherSerial,
                hintText: 'SN0001',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            SectionLabel(l.addVoucherPin),
            TextField(
              controller: _pinCtrl,
              decoration: InputDecoration(
                labelText: l.addVoucherPin,
                hintText: '1234',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving && _selectedDef != null) _save();
              },
            ),
            const SizedBox(height: 22),
            // Error banner
            if (_error != null) ...[
              InkCard(
                ruleColor: cs.error,
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: IntesharType.sans(13, color: cs.onSurface)),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_saving || _selectedDef == null) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_circle_outline, size: 18),
                label: Text(l.addVoucherSave),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Excel / CSV Tab ───────────────────────────────────────────────────────────

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

  Future<void> _downloadTemplate() async {
    final l = AppLocalizations.of(context)!;
    final excel = Excel.createExcel();
    final sheet = excel['Vouchers'];
    excel.setDefaultSheet('Vouchers');
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    sheet.appendRow([TextCellValue('serialNumber'), TextCellValue('pin')]);
    sheet.appendRow([TextCellValue('SN0001'), TextCellValue('1234')]);
    sheet.appendRow([TextCellValue('SN0002'), TextCellValue('5678')]);
    sheet.appendRow([TextCellValue('SN0003'), TextCellValue('9012')]);

    final encoded = excel.encode();
    if (encoded == null) return;
    final bytes = Uint8List.fromList(encoded);

    const fileName = 'vouchers_template.xlsx';
    String? path;
    try {
      if (kIsWeb) {
        downloadBytes(fileName, bytes);
        path = fileName;
      } else if (Platform.isAndroid || Platform.isIOS) {
        path = await FilePicker.platform.saveFile(
          dialogTitle: l.batchAddDownloadTemplate,
          fileName: fileName,
          bytes: bytes,
        );
      } else {
        path = await FilePicker.platform.saveFile(
          dialogTitle: l.batchAddDownloadTemplate,
          fileName: fileName,
        );
        if (path != null) {
          final finalPath =
              path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
          await File(finalPath).writeAsBytes(bytes);
          path = finalPath;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
      return;
    }

    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.batchAddTemplateSaved)),
      );
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
      setState(
          () => _error = AppLocalizations.of(context)!.batchAddErrorReadBytes);
      return;
    }

    if (file.extension?.toLowerCase() == 'csv') {
      _parseCsv(utf8.decode(bytes, allowMalformed: true));
    } else {
      _parseXlsx(bytes);
    }
  }

  void _parseCsv(String content) {
    final rows = <_ExcelRow>[];
    final lines =
        content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    int start = 0;
    if (lines.isNotEmpty && lines[0].toLowerCase().contains('serial')) {
      start = 1;
    }
    for (var i = start; i < lines.length; i++) {
      final parts = lines[i].split(',');
      if (parts.length >= 2) {
        rows.add(_ExcelRow(serial: parts[0].trim(), pin: parts[1].trim()));
      }
    }
    setState(() {
      _preview = rows;
      _error = null;
    });
  }

  void _parseXlsx(Uint8List bytes) {
    final l = AppLocalizations.of(context)!;
    try {
      final book = Excel.decodeBytes(bytes);
      final sheets =
          book.tables.values.where((t) => t.maxRows > 0).toList();
      if (sheets.isEmpty) {
        setState(() => _error = l.batchAddXlsxBadHeader);
        return;
      }
      final sheet = sheets.first;
      final allRows = sheet.rows;
      if (allRows.isEmpty) {
        setState(() => _error = l.batchAddXlsxBadHeader);
        return;
      }

      int serialCol = -1;
      int pinCol = -1;
      final header = allRows.first;
      for (var i = 0; i < header.length; i++) {
        final raw =
            header[i]?.value?.toString().trim().toLowerCase() ?? '';
        if (raw == 'serialnumber' ||
            raw == 'serial' ||
            raw == 'serial number') {
          serialCol = i;
        } else if (raw == 'pin') {
          pinCol = i;
        }
      }
      if (serialCol < 0 || pinCol < 0) {
        setState(() => _error = l.batchAddXlsxBadHeader);
        return;
      }

      final rows = <_ExcelRow>[];
      for (var r = 1; r < allRows.length; r++) {
        final row = allRows[r];
        final serial = (serialCol < row.length
                ? row[serialCol]?.value?.toString().trim()
                : '') ??
            '';
        final pin = (pinCol < row.length
                ? row[pinCol]?.value?.toString().trim()
                : '') ??
            '';
        if (serial.isEmpty && pin.isEmpty) continue;
        rows.add(_ExcelRow(serial: serial, pin: pin));
      }
      setState(() {
        _preview = rows;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _entityId() {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is AuthAuthenticated) return auth.entity.id;
    return '';
  }

  Future<void> _import() async {
    final l = AppLocalizations.of(context)!;
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

    final Set<String> existingSerials;
    try {
      final existing = await repo.readByEntity(entityId);
      existingSerials =
          existing.map((p) => p.serialNumber.trim().toLowerCase()).toSet();
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = e.toString();
        });
      }
      return;
    }

    for (var i = 0; i < rows.length; i++) {
      final key = rows[i].serial.trim().toLowerCase();
      if (existingSerials.contains(key)) {
        if (mounted) {
          setState(() {
            _error = l.batchAddDuplicateRow(i + 1, rows[i].serial);
            _importing = false;
          });
        }
        return;
      }

      try {
        await repo.create(Product(
          id: _newProductId(),
          productDefinition: def,
          status: ProductStatus.AVAILABLE,
          serialNumber: rows[i].serial,
          pin: rows[i].pin,
          owners: [entityId],
          currentOwner: entityId,
        ));
        existingSerials.add(key);
        if (mounted) {
          setState(() {
            _imported = i + 1;
            _progress = (i + 1) / rows.length;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = l.batchAddFailedAtRow(i + 1, e.toString());
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
        SnackBar(content: Text(l.batchAddImportedProducts(_imported))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Format guide card ────────────────────────────────────────
            SectionLabel(l.batchAddCsvFormat),
            InkCard(
              ruleColor: cs.onPrimaryContainer,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.batchAddRequiredColumns,
                    style: IntesharType.overline(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(IntesharRadii.sm),
                    ),
                    child: SelectableText(
                      'serialNumber,pin\nSN0001,1234\nSN0002,5678',
                      style: IntesharType.mono(12.5,
                          color: cs.onSurface, letterSpacing: 0.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(l.batchAddDownloadTemplate),
              ),
            ),

            const SizedBox(height: 24),
            // ── Denomination picker ──────────────────────────────────────
            SectionLabel(l.batchAddDenomination),
            if (_loadingDefs)
              const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator())
            else
              DropdownButtonFormField<ProductDefinition>(
                initialValue: _selectedDef,
                isExpanded: true,
                decoration:
                    InputDecoration(labelText: l.batchAddProductDefinition),
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
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(l.batchAddPickFile),
              ),
            ),

            // ── Error banner ─────────────────────────────────────────────
            if (_error != null) ...[
              const SizedBox(height: 14),
              InkCard(
                ruleColor: cs.error,
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: IntesharType.sans(13, color: cs.onSurface)),
              ),
            ],

            // ── Preview table ────────────────────────────────────────────
            if (_preview != null && _preview!.isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionLabel(
                l.batchAddPreview,
                trailing: Text(
                  l.batchAddRowCount(_preview!.length),
                  style:
                      IntesharType.overline(color: cs.onSurfaceVariant),
                ),
              ),
              InkCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          14, 10, 14, 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(
                              '#',
                              style: IntesharType.sans(11,
                                  color: IntesharColors.lichen,
                                  w: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              l.batchAddColSerial,
                              style: IntesharType.sans(11,
                                  color: IntesharColors.lichen,
                                  w: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              l.batchAddColPin,
                              style: IntesharType.sans(11,
                                  color: IntesharColors.lichen,
                                  w: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Hairline(),
                    // Data rows (max 10)
                    ..._preview!.take(10).toList().asMap().entries.map(
                          (e) => Column(
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional
                                    .fromSTEB(14, 9, 14, 9),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      child: monoText(
                                        (e.key + 1)
                                            .toString()
                                            .padLeft(2, '0'),
                                        size: 11,
                                        color: IntesharColors.lichen,
                                      ),
                                    ),
                                    Expanded(
                                      child: monoText(
                                        e.value.serial,
                                        size: 12.5,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    Expanded(
                                      child: monoText(
                                        e.value.pin,
                                        size: 12.5,
                                        color: IntesharColors.lichen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (e.key <
                                  (_preview!.length > 10
                                          ? 10
                                          : _preview!.length) -
                                      1)
                                const Hairline(),
                            ],
                          ),
                        ),
                    // "and N more" footer
                    if (_preview!.length > 10) ...[
                      const Hairline(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Text(
                          l.batchAddMoreRows(_preview!.length - 10),
                          style: IntesharType.sans(12,
                              color: IntesharColors.lichen),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Progress block
              if (_importing) ...[
                _ProgressBlock(
                  progress: _progress,
                  label: l.batchAddProgressImported(
                      _imported, _preview!.length),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      (_importing || _selectedDef == null) ? null : _import,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text(l.batchAddImportRows(_preview!.length)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Progress block ────────────────────────────────────────────────────────────

class _ProgressBlock extends StatelessWidget {
  final double progress;
  final String label;
  const _ProgressBlock({required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      ruleColor: cs.onPrimaryContainer,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.batchAddPrinting,
                style: IntesharType.overline(color: cs.onPrimaryContainer),
              ),
              const Spacer(),
              monoText(
                '${(progress * 100).round()}%',
                size: 12,
                color: cs.onSurface,
                w: FontWeight.w700,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
          const SizedBox(height: 8),
          Text(label,
              style:
                  IntesharType.sans(12, color: IntesharColors.lichen)),
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
