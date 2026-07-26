import 'dart:convert';
import 'package:inteshar/core/api/error_mapper.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/files/web_download.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/core/geo/governorate_picker.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/voucher_batch.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// Inline bilingual label (the import tab adds several controls; rather than churn
/// the .arb files we resolve ar/en at build time, the same pattern the login page uses).
String _tr(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;

// ── Batch-import row decision (pure, testable) ─────────────────────────────

/// The outcome of evaluating a single row in a batch import.
enum BatchRowAction {
  /// The row is new — proceed to create the product.
  add,

  /// The serial already exists in this entity's inventory — skip silently.
  skip,

  /// The row has an empty serial or PIN — skip silently.
  invalid,
}

/// Decide what to do with a single batch-import row.
///
/// [serial] and [pin] are the raw values from the file (trimming is applied
/// internally). [existingSerials] must contain already-lower-cased keys so the
/// look-up is case-insensitive and O(1).
BatchRowAction batchRowDecide({
  required String serial,
  required String pin,
  required Set<String> existingSerials,
}) {
  if (serial.trim().isEmpty || pin.trim().isEmpty) return BatchRowAction.invalid;
  if (existingSerials.contains(serial.trim().toLowerCase())) {
    return BatchRowAction.skip;
  }
  return BatchRowAction.add;
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
    _tabs = TabController(length: 3, vsync: this);
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
                  color: context.tones.brand,
                  borderRadius: BorderRadius.circular(999),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: IntesharColors.ink,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: IntesharType.sans(13, w: FontWeight.w800),
                unselectedLabelStyle: IntesharType.sans(13, w: FontWeight.w700),
                tabs: [
                  // B-088: the single-voucher tab is retired — bulk upload is the
                  // only supported way to add stock.
                  Tab(text: _tr(context, 'رفع ملف', 'Upload file')),
                  Tab(text: _tr(context, 'الدفعات', 'Batches')),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _UploadTab(),
                _BatchesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Upload file Tab (two supplier formats: NEW / OTHER) ─────────────────────────

class _UploadTab extends ConsumerStatefulWidget {
  const _UploadTab();

  @override
  ConsumerState<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends ConsumerState<_UploadTab> {
  ImportFormat _format = ImportFormat.newSew;

  List<ProductDefinition> _defs = [];
  ProductDefinition? _selectedDef;
  List<EntitySummaryRow> _entities = [];
  EntitySummaryRow? _target; // who receives the vouchers (the agent/warehouse)
  String? _selectedGovernorate; // region-lock (NEW only)
  bool _loading = true;
  Object? _loadError;

  Uint8List? _pickedBytes;
  String? _pickedExt;
  String? _fileName;
  List<ParsedVoucher>? _preview;

  bool _importing = false;
  double _progress = 0;
  BatchImportResult? _result;
  String? _error;
  final TextEditingController _pasteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final defs = await DefinitionRepository(api).readAll();
      // Batch target must be a Main Agent — fetch AGENT1 rows only (bounded: one
      // per governorate) instead of downloading every entity (B-023).
      final agent1s =
          (await EntityRepository(api).search(types: const [EntityType.AGENT1]))
              .items;
      if (mounted) {
        setState(() {
          _defs = defs;
          _entities = agent1s;
          if (defs.isNotEmpty) _selectedDef = defs.first;
          _target = agent1s.isNotEmpty ? agent1s.first : null;
          _loading = false;
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context)!.batchAddErrorReadBytes);
      return;
    }
    setState(() {
      _pickedBytes = bytes;
      _pickedExt = file.extension?.toLowerCase();
      _fileName = file.name;
      _result = null;
      _error = null;
    });
    _reparse();
  }

  /// Re-derive the preview from the picked file + the current format (so toggling
  /// NEW/OTHER re-reads the same file without re-picking).
  void _reparse() {
    final bytes = _pickedBytes;
    if (bytes == null) return;
    try {
      final List<ParsedVoucher> rows;
      if (_pickedExt == 'xlsx') {
        rows = _parseXlsx(bytes, _format);
      } else {
        rows = parseVoucherFile(utf8.decode(bytes, allowMalformed: true), _format);
      }
      setState(() {
        _preview = rows;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e, context));
    }
  }

  /// Paste path: parse the textarea content directly and AUTO-SELECT the format
  /// from the columns (3 → NEW, 4+ → OTHER). Keeps the encoded bytes so a later
  /// NEW/OTHER toggle re-derives the preview from the same pasted text.
  void _onPasteChanged(String text) {
    if (text.trim().isEmpty) {
      setState(() {
        _preview = null;
        _pickedBytes = null;
        _pickedExt = null;
        _fileName = null;
        _error = null;
      });
      return;
    }
    final detected = detectFormat(text);
    try {
      final rows = parseVoucherFile(text, detected ?? _format);
      setState(() {
        if (detected != null) _format = detected;
        _pickedBytes = Uint8List.fromList(utf8.encode(text));
        _pickedExt = 'txt';
        _fileName = _tr(context, 'نص ملصوق', 'pasted text');
        _preview = rows;
        _result = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e, context));
    }
  }

  /// Required fields not yet satisfied — drives the pre-upload guard + hint.
  List<String> _missing() {
    final m = <String>[];
    if (_selectedDef == null) m.add(_tr(context, 'الفئة', 'Category'));
    if (_target == null) m.add(_tr(context, 'الوكيل الرئيسي', 'Main Agent'));
    if (_preview == null || _preview!.isEmpty) {
      m.add(_tr(context, 'قسائم صالحة', 'valid vouchers'));
    }
    return m;
  }

  bool get _canImport =>
      _selectedDef != null &&
      _target != null &&
      _preview != null &&
      _preview!.isNotEmpty;

  List<ParsedVoucher> _parseXlsx(Uint8List bytes, ImportFormat format) {
    final book = Excel.decodeBytes(bytes);
    final sheets = book.tables.values.where((t) => t.maxRows > 0).toList();
    if (sheets.isEmpty) return [];
    final rows = sheets.first.rows;
    final out = <ParsedVoucher>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      String cell(int i) =>
          (i < row.length ? row[i]?.value?.toString().trim() : '') ?? '';
      final serial = cell(0);
      if (r == 0 && serial.toLowerCase().contains('serial')) continue; // header
      final pin = cell(1);
      if (serial.isEmpty || pin.isEmpty) continue;
      final expiry = normalizeExpiry(cell(2));
      final label = format == ImportFormat.other
          ? (cell(3).isEmpty ? null : cell(3))
          : null;
      out.add(ParsedVoucher(
          serial: serial, pin: pin, expiry: expiry, label: label));
    }
    return out;
  }

  Future<void> _downloadTemplate() async {
    final l = AppLocalizations.of(context)!;
    final excel = Excel.createExcel();
    final sheet = excel['Vouchers'];
    excel.setDefaultSheet('Vouchers');
    if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
    if (_format == ImportFormat.newSew) {
      sheet.appendRow([
        TextCellValue('serialNumber'),
        TextCellValue('pin'),
        TextCellValue('expiry')
      ]);
      sheet.appendRow([
        TextCellValue('80385983791'),
        TextCellValue('020339743268988'),
        TextCellValue('28/02/2028')
      ]);
    } else {
      sheet.appendRow([
        TextCellValue('serialNumber'),
        TextCellValue('pin'),
        TextCellValue('expiry'),
        TextCellValue('label')
      ]);
      sheet.appendRow([
        TextCellValue('260303MIN0001031'),
        TextCellValue('X97645X48D7LHF4J'),
        TextCellValue('03/03/2027'),
        TextCellValue('Apple 2')
      ]);
    }
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
            bytes: bytes);
      } else {
        path = await FilePicker.platform
            .saveFile(dialogTitle: l.batchAddDownloadTemplate, fileName: fileName);
        if (path != null) {
          final finalPath =
              path.toLowerCase().endsWith('.xlsx') ? path : '$path.xlsx';
          await File(finalPath).writeAsBytes(bytes);
          path = finalPath;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context));
      return;
    }
    if (path != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.batchAddTemplateSaved)));
    }
  }

  /// B-089: clear a finished upload so the operator can immediately do another,
  /// instead of navigating away and back. Deliberately KEEPS the target, definition,
  /// format and governorate — the common case is several files for the same agent.
  void _resetForAnother() {
    setState(() {
      _pickedBytes = null;
      _fileName = null;
      _preview = null;
      _result = null;
      _error = null;
      _progress = 0;
    });
  }

  Future<void> _import() async {
    final def = _selectedDef;
    final target = _target;
    if (_preview == null || _preview!.isEmpty || def == null || target == null) {
      return;
    }
    setState(() {
      _importing = true;
      _progress = 0;
      _result = null;
      _error = null;
    });
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final gov = _format.regionLocked ? _selectedGovernorate : null;
      final res = await repo.batchImport(
        definitionId: def.id,
        ownerId: target.id,
        governorate: gov,
        type: _format.wire,
        vouchers: _preview!,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _progress = total == 0 ? 1 : done / total);
          }
        },
      );
      if (mounted) {
        setState(() {
          _importing = false;
          _result = res;
          _preview = null;
          _pickedBytes = null;
          _fileName = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = friendlyError(e, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return ErrorState(error: _loadError!, onRetry: _load);
    }
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isNew = _format == ImportFormat.newSew;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Format selector ──────────────────────────────────────────
            SectionLabel(_tr(context, 'صيغة الملف', 'File format')),
            SegmentedButton<ImportFormat>(
              segments: [
                ButtonSegment(
                  value: ImportFormat.newSew,
                  label: Text(_tr(context, 'NEW (آسيا/زين)', 'NEW (Asia/Zain)')),
                  icon: const Icon(Icons.location_on_outlined, size: 16),
                ),
                ButtonSegment(
                  value: ImportFormat.other,
                  label: Text(_tr(context, 'OTHER', 'OTHER')),
                  icon: const Icon(Icons.public_outlined, size: 16),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (s) {
                setState(() => _format = s.first);
                _reparse();
              },
            ),
            const SizedBox(height: 6),
            Text(
              isNew
                  ? _tr(context, 'serial,pin,expiry — مقيّد بالمحافظة',
                      'serial,pin,expiry — region-locked')
                  : _tr(context, 'serial,pin,expiry,label — غير مقيّد',
                      'serial,pin,expiry,label — region-free'),
              style: IntesharType.mono(12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 22),

            // ── Category (definition) ────────────────────────────────────
            SectionLabel(_tr(context, 'الفئة', 'Category')),
            DropdownButtonFormField<ProductDefinition>(
              initialValue: _selectedDef,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.batchAddProductDefinition),
              items: _defs
                  .map((d) => DropdownMenuItem(
                      value: d, child: Text('${d.name} (${d.sku})')))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDef = v),
            ),
            const SizedBox(height: 22),

            // ── Target Main Agent ────────────────────────────────────────
            SectionLabel(_tr(context, 'الوكيل الرئيسي', 'Main Agent')),
            if (_entities.isEmpty)
              InkCard(
                ruleColor: cs.error,
                padding: const EdgeInsets.all(12),
                child: Text(
                  _tr(context, 'أنشئ وكيلاً رئيسياً أولاً', 'Create a Main Agent first'),
                  style: IntesharType.sans(13, color: cs.onSurface),
                ),
              )
            else
              DropdownButtonFormField<EntitySummaryRow>(
                initialValue: _target,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: _tr(context, 'تُرفع إلى الوكيل الرئيسي', 'Hand to Main Agent')),
                items: _entities
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                    .toList(),
                onChanged: (v) => setState(() => _target = v),
              ),
            const SizedBox(height: 22),

            // ── City / governorate (NEW only) ────────────────────────────
            if (isNew) ...[
              SectionLabel(_tr(context, 'المحافظة', 'City / governorate')),
              GovernorateDropdown(
                value: _selectedGovernorate,
                noneLabel: l.batchAddNotGeoLocked,
                labelText: l.batchAddGovernorate,
                onChanged: (v) => setState(() => _selectedGovernorate = v),
              ),
              const SizedBox(height: 22),
            ],

            // ── File pick + template ─────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: Text(l.batchAddPickFile),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: Text(_tr(context, 'قالب', 'Template')),
                ),
              ],
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Text('📄 $_fileName',
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
            ],

            // ── Or paste rows (auto-detects NEW vs OTHER from the columns) ──
            const SizedBox(height: 16),
            SectionLabel(_tr(context, 'أو الصق الصفوف', 'Or paste rows')),
            TextField(
              controller: _pasteCtrl,
              minLines: 3,
              maxLines: 8,
              style: IntesharType.mono(12),
              decoration: InputDecoration(
                hintText: isNew
                    ? 'serial,pin,expiry'
                    : 'serial,pin,expiry,label',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onPasteChanged,
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

            // ── Result banner ────────────────────────────────────────────
            if (_result != null) ...[
              const SizedBox(height: 14),
              InkCard(
                ruleColor: context.tones.brandInk,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(
                        context,
                        'تم الاستيراد: ${_result!.imported} • مكرر: ${_result!.skipped} • غير صالح: ${_result!.invalid}',
                        'Imported: ${_result!.imported} • duplicate: ${_result!.skipped} • invalid: ${_result!.invalid}',
                      ),
                      style: IntesharType.sans(13.5,
                          color: cs.onSurface, w: FontWeight.w700),
                    ),
                    // B-089: start the next upload without leaving the page.
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.icon(
                        onPressed: _resetForAnother,
                        icon: const Icon(Icons.upload_file_outlined, size: 18),
                        label: Text(_tr(context, 'رفع ملف آخر', 'Upload another file')),
                      ),
                    ),
                    // Which serials were skipped as duplicates (first 20) — so the operator can
                    // reconcile instead of guessing which rows didn't import.
                    if (_result!.skippedSerials.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _tr(
                          context,
                          'أرقام مكررة: ${_result!.skippedSerials.take(20).join('، ')}${_result!.skippedSerials.length > 20 ? ' …' : ''}',
                          'Duplicate serials: ${_result!.skippedSerials.take(20).join(', ')}${_result!.skippedSerials.length > 20 ? ' …' : ''}',
                        ),
                        style: IntesharType.mono(11.5,
                            color: cs.onSurfaceVariant, w: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // ── No valid rows (content provided but parsed to nothing) ───
            if (_preview != null && _preview!.isEmpty && _result == null) ...[
              const SizedBox(height: 14),
              InkCard(
                ruleColor: cs.error,
                padding: const EdgeInsets.all(12),
                child: Text(
                  _tr(context, 'لا توجد صفوف صالحة — تحقّق من الصيغة',
                      'No valid rows found — check the format'),
                  style: IntesharType.sans(13, color: cs.onSurface),
                ),
              ),
            ],

            // ── Preview ──────────────────────────────────────────────────
            if (_preview != null && _preview!.isNotEmpty) ...[
              const SizedBox(height: 24),
              SectionLabel(
                l.batchAddPreview,
                trailing: Text(l.batchAddRowCount(_preview!.length),
                    style: IntesharType.overline(color: cs.onSurfaceVariant)),
              ),
              // B-090: the primary action sits ABOVE the preview — it used to be the
              // very last thing on a long page, so the operator had to scroll past
              // everything to start the import they had already decided on.
              const SizedBox(height: 12),
              if (_missing().isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_tr(context, 'مطلوب: ', 'Required: ')}${_missing().join(_tr(context, '، ', ', '))}',
                    style: IntesharType.sans(12, color: cs.error, w: FontWeight.w600),
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_importing || !_canImport) ? null : _import,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text(l.batchAddImportRows(_preview!.length)),
                ),
              ),
              if (_importing) ...[
                const SizedBox(height: 12),
                _ProgressBlock(
                  progress: _progress,
                  label: _tr(context, '${(_progress * 100).round()}%',
                      '${(_progress * 100).round()}%'),
                ),
              ],
              const SizedBox(height: 16),
              _PreviewTable(rows: _preview!, showLabel: !isNew),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Preview table ─────────────────────────────────────────────────────────────

class _PreviewTable extends StatelessWidget {
  final List<ParsedVoucher> rows;
  final bool showLabel;
  const _PreviewTable({required this.rows, required this.showLabel});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final shown = rows.take(10).toList();
    Widget head(String t, {int flex = 1, double width = 0}) {
      final w = Text(t,
          style: IntesharType.sans(11,
              color: IntesharColors.lichen, w: FontWeight.w700));
      return width > 0 ? SizedBox(width: width, child: w) : Expanded(flex: flex, child: w);
    }

    return InkCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            child: Row(children: [
              head('#', width: 30),
              head(l.batchAddColSerial, flex: 2),
              head(l.batchAddColPin, flex: 2),
              head(_tr(context, 'انتهاء', 'Expiry'), flex: 2),
              if (showLabel) head(_tr(context, 'الوصف', 'Label'), flex: 2),
            ]),
          ),
          const Hairline(),
          ...shown.asMap().entries.map((e) {
            final v = e.value;
            return Column(children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 14, 9),
                child: Row(children: [
                  SizedBox(
                      width: 30,
                      child: monoText((e.key + 1).toString().padLeft(2, '0'),
                          size: 11, color: IntesharColors.lichen)),
                  Expanded(
                      flex: 2,
                      child: monoText(v.serial, size: 12, color: cs.onSurface)),
                  Expanded(
                      flex: 2,
                      child:
                          monoText(v.pin, size: 12, color: IntesharColors.lichen)),
                  Expanded(
                      flex: 2,
                      child: monoText(v.expiry ?? '—',
                          size: 12, color: cs.onSurfaceVariant)),
                  if (showLabel)
                    Expanded(
                        flex: 2,
                        child: Text(v.label ?? '—',
                            style: IntesharType.sans(12,
                                color: cs.onSurfaceVariant))),
                ]),
              ),
              if (e.key < shown.length - 1) const Hairline(),
            ]);
          }),
          if (rows.length > 10) ...[
            const Hairline(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(l.batchAddMoreRows(rows.length - 10),
                  style: IntesharType.sans(12, color: IntesharColors.lichen)),
            ),
          ],
        ],
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
              style: IntesharType.sans(12, color: IntesharColors.lichen)),
        ],
      ),
    );
  }
}

// ── Batches Tab ───────────────────────────────────────────────────────────────

class _BatchesTab extends ConsumerStatefulWidget {
  const _BatchesTab();

  @override
  ConsumerState<_BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends ConsumerState<_BatchesTab> {
  List<VoucherBatch>? _batches;
  bool _loading = true;
  Object? _error;
  // Batch IDs currently awaiting a server response (pause/delete/export).
  final Set<String> _busy = {};

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
      final repo = ProductRepository(ref.read(apiClientProvider));
      final batches = await repo.listBatches();
      if (mounted) setState(() { _batches = batches; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _togglePause(VoucherBatch batch) async {
    if (_busy.contains(batch.id)) return;
    setState(() => _busy.add(batch.id));
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      await repo.pauseBatch(batch.id, pause: !batch.paused);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(batch.id));
    }
  }

  Future<void> _confirmDelete(VoucherBatch batch) async {
    if (_busy.contains(batch.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr(context, 'حذف الدفعة', 'Delete batch')),
        content: Text(_tr(
          context,
          'سيتم حذف جميع القسائم في هذه الدفعة نهائياً. لا يمكن التراجع.',
          'All vouchers in this batch will be permanently deleted. This cannot be undone.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr(context, 'إلغاء', 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr(context, 'حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy.add(batch.id));
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      await repo.deleteBatch(batch.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(batch.id));
    }
  }

  Future<void> _export(VoucherBatch batch) async {
    if (_busy.contains(batch.id)) return;
    setState(() => _busy.add(batch.id));
    // Capture context-derived strings before any async gap to avoid
    // use_build_context_synchronously warnings.
    final saveFileTitle = _tr(context, 'حفظ الملف', 'Save file');
    final fileDownloadedMsg = _tr(context, 'تم تحميل الملف', 'File downloaded');
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final bytes = await repo.exportBatchTxt(batch.id);
      final fileName = 'batch_${batch.id}.txt';
      if (kIsWeb) {
        downloadBytes(fileName, bytes);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await FilePicker.platform.saveFile(
          dialogTitle: saveFileTitle,
          fileName: fileName,
          bytes: bytes,
        );
      } else {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: saveFileTitle,
          fileName: fileName,
        );
        if (path != null) {
          final finalPath =
              path.toLowerCase().endsWith('.txt') ? path : '$path.txt';
          await File(finalPath).writeAsBytes(bytes);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(fileDownloadedMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(batch.id));
    }
  }

  Future<void> _withdraw(VoucherBatch batch) async {
    if (_busy.contains(batch.id)) return;
    // Capture bilingual strings before the async gap (showDialog returns a Future).
    final confirmTitle = _tr(context, 'سحب الدفعة', 'Withdraw batch');
    final confirmBody = _tr(
      context,
      'سيتم سحب جميع القسائم غير المستخدمة في هذه الدفعة إلى المقر. القسائم المستخدمة لا يمكن استرجاعها.',
      'All UNUSED vouchers in this batch will be reclaimed to HQ. Used vouchers cannot be recovered.',
    );
    final cancelLabel = _tr(context, 'إلغاء', 'Cancel');
    final withdrawLabel = _tr(context, 'سحب', 'Withdraw');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(confirmTitle),
        content: Text(confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(withdrawLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy.add(batch.id));
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final result = await repo.withdrawBatch(batch.id);
      if (mounted) {
        final isAr = Localizations.localeOf(context).languageCode == 'ar';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            isAr
                ? 'تم سحب ${result.reclaimed} • مُستخدَم ${result.used}'
                : 'Reclaimed ${result.reclaimed} • Used ${result.used}',
          ),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(batch.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final batches = _batches ?? [];
    if (batches.isEmpty) {
      return EmptyState(
        message: _tr(
          context,
          'لا توجد دفعات — ارفع ملفاً لإنشاء دفعة جديدة',
          'No batches yet — upload a file to create one',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        itemCount: batches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _BatchCard(
          batch: batches[i],
          busy: _busy.contains(batches[i].id),
          onTogglePause: () => _togglePause(batches[i]),
          onDelete: () => _confirmDelete(batches[i]),
          onExport: () => _export(batches[i]),
          onWithdraw: () => _withdraw(batches[i]),
        ),
      ),
    );
  }
}

// ── Batch card ────────────────────────────────────────────────────────────────

class _BatchCard extends StatelessWidget {
  final VoucherBatch batch;
  final bool busy;
  final VoidCallback onTogglePause;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onWithdraw;

  const _BatchCard({
    required this.batch,
    required this.busy,
    required this.onTogglePause,
    required this.onDelete,
    required this.onExport,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paused = batch.paused;

    return InkCard(
      ruleColor: paused ? cs.outline : context.tones.brandInk,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: product name + status badge
          Row(children: [
            Expanded(
              child: Text(
                batch.productName.isNotEmpty
                    ? batch.productName
                    : batch.sku,
                style: IntesharType.sans(15,
                    color: cs.onSurface, w: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            _BatchStatusChip(paused: paused),
          ]),
          const SizedBox(height: 6),
          // SKU · type · governorate tags
          Row(children: [
            monoText(batch.sku, size: 12, color: IntesharColors.lichen),
            const SizedBox(width: 8),
            _BatchTag(batch.type),
            if ((batch.governorate ?? '').isNotEmpty) ...[  
              const SizedBox(width: 6),
              _BatchTag(batch.governorate!),
            ],
          ]),
          const SizedBox(height: 12),
          // Count stats: total / available / used
          Row(children: [
            _CountStat(
              label: _tr(context, 'الإجمالي', 'Total'),
              value: batch.totalCount,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 24),
            _CountStat(
              label: _tr(context, 'متاح', 'Available'),
              value: batch.availableCount,
              color: cs.onSurface,
            ),
            const SizedBox(width: 24),
            _CountStat(
              label: _tr(context, 'مُستخدَم', 'Used'),
              value: batch.printedCount,
              color: batch.printedCount > 0 ? cs.error : cs.onSurfaceVariant,
            ),
          ]),
          if (batch.createdAt.isNotEmpty) ...[  
            const SizedBox(height: 8),
            Text(
              batch.createdAt.replaceFirst('T', ' ').split('.').first,
              style: IntesharType.sans(11, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          // Action row
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.file_download_outlined, size: 16),
                  label: Text(_tr(context, 'تصدير TXT', 'Export TXT')),
                ),
                // Withdraw: always enabled — reclaims AVAILABLE vouchers to HQ even if
                // some are already PRINTED (used). Result snackbar reports both counts.
                OutlinedButton.icon(
                  onPressed: onWithdraw,
                  icon: const Icon(Icons.undo_outlined, size: 16),
                  label: Text(_tr(context, 'سحب', 'Withdraw')),
                ),
                OutlinedButton.icon(
                  onPressed: onTogglePause,
                  icon: Icon(
                      paused
                          ? Icons.play_arrow_outlined
                          : Icons.pause_outlined,
                      size: 16),
                  label: Text(paused
                      ? _tr(context, 'استئناف', 'Resume')
                      : _tr(context, 'إيقاف مؤقت', 'Pause')),
                ),
                OutlinedButton.icon(
                  onPressed: batch.canDelete ? onDelete : null,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(_tr(context, 'حذف', 'Delete')),
                  style: batch.canDelete
                      ? OutlinedButton.styleFrom(foregroundColor: cs.error)
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BatchTag extends StatelessWidget {
  final String text;
  const _BatchTag(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: monoText(text, size: 11, color: cs.onSurfaceVariant),
    );
  }
}

class _BatchStatusChip extends StatelessWidget {
  final bool paused;
  const _BatchStatusChip({required this.paused});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: paused ? cs.errorContainer : cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        paused
            ? (isAr ? 'موقوف' : 'Paused')
            : (isAr ? 'نشط' : 'Active'),
        style: IntesharType.sans(11,
            color:
                paused ? cs.onErrorContainer : cs.onPrimaryContainer,
            w: FontWeight.w700),
      ),
    );
  }
}

class _CountStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _CountStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Formatters.money(value),
          style: IntesharType.sans(17, color: color, w: FontWeight.w800),
        ),
        Text(label,
            style: IntesharType.sans(10, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
