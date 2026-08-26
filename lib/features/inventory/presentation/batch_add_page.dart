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
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/voucher_batch.dart';
import 'package:inteshar/features/inventory/domain/voucher_import.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
import 'package:inteshar/shared/widgets/confirm_dialog.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/loading_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// Inline bilingual label (the import tab adds several controls; rather than churn
/// the .arb files we resolve ar/en at build time, the same pattern the login page uses).
String _tr(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;

/// The batch(es) a just-finished import created, published so the Batches tab can
/// refresh and jump straight to them (UX-05 — the tab used not to even reload, so
/// the highest-frequency HQ task ended with three numbers and no way to see the
/// thing it had just made).
class _BatchFocus {
  final List<String> batchIds;

  /// Strictly increasing (microseconds) so a repeat upload re-triggers the
  /// Batches tab even when the ids match — and so the tab can tell an event it
  /// has already applied from a new one after the state was cleared.
  final int tick;
  const _BatchFocus(this.batchIds, this.tick);
}

final _batchFocusProvider = StateProvider<_BatchFocus?>((_) => null);

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

/// A question the operator must answer before a batch import can go out.
enum BatchImportRequirement {
  category,

  /// Which Main Agent's warehouse receives the codes.
  warehouse,
  vouchers,

  /// Region-locked formats only: whether these are for one governorate or
  /// deliberately region-free.
  saleScope,

  /// Region-locked and scoped to one governorate: which one.
  governorate,
}

/// What is still unanswered on the batch-import screen, in the order it is shown.
///
/// Extracted from widget state deliberately. Two customer-visible incidents came
/// from this gate rather than from the import itself:
///
/// - **C-08** — the sale scope defaulted to "answered", so an operator uploading
///   "for Karbala" produced stock sellable in all 18 governorates and was never
///   told. Fixed by making an unanswered scope block the import; then found again
///   in `_canImport`, which re-stated three of the four checks and dropped the
///   scope, so the button stayed pressable. The gate and the button must be the
///   same rule — hence one function with one caller.
/// - **UX-14** — the warehouse defaulted to the first agent in a truncated list,
///   which made [warehouse] unreachable and quietly sent thousands of codes to
///   whoever sorted first.
///
/// Both were a required question that did not look required. That is the class of
/// bug this function exists to make testable.
List<BatchImportRequirement> batchImportMissing({
  required bool hasCategory,
  required bool hasWarehouse,
  required bool hasVouchers,
  required bool regionLockedFormat,
  required bool? regionLockedScope,
  required bool hasGovernorate,
}) {
  final missing = <BatchImportRequirement>[];
  if (!hasCategory) missing.add(BatchImportRequirement.category);
  if (!hasWarehouse) missing.add(BatchImportRequirement.warehouse);
  if (!hasVouchers) missing.add(BatchImportRequirement.vouchers);
  if (regionLockedFormat) {
    if (regionLockedScope == null) {
      missing.add(BatchImportRequirement.saleScope);
    } else if (regionLockedScope && !hasGovernorate) {
      missing.add(BatchImportRequirement.governorate);
    }
  }
  return missing;
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

/// One tab of this page: its label in both languages and the view it shows.
typedef _TabSpec = ({String ar, String en, Widget view});

/// The tabs, in order. ONE list feeds the controller length, the `TabBar` and
/// the `TabBarView` — they used to be three hand-kept copies, and the length
/// had drifted to 3 against 2 tabs, which trips the
/// `controller.length == children.length` assert on every debug/profile build.
const List<_TabSpec> _batchTabs = [
  // B-088: the single-voucher tab is retired — bulk upload is the only
  // supported way to add stock.
  (ar: 'رفع ملف', en: 'Upload file', view: _UploadTab()),
  (ar: 'الدفعات', en: 'Batches', view: _BatchesTab()),
];

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
    _tabs = TabController(length: _batchTabs.length, vsync: this);
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
    // "Open this batch" on the import result lands on the Batches tab.
    ref.listen<_BatchFocus?>(_batchFocusProvider, (_, next) {
      if (next != null && next.batchIds.isNotEmpty) _tabs.animateTo(1);
    });
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
                // The indicator is a brand pill — the selected label rides on it.
                labelColor: context.tones.onBrand,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: IntesharType.sans(13, w: FontWeight.w800),
                unselectedLabelStyle: IntesharType.sans(13, w: FontWeight.w700),
                tabs: [
                  for (final t in _batchTabs) Tab(text: _tr(context, t.ar, t.en)),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [for (final t in _batchTabs) t.view],
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
  String? _selectedGovernorate;
  /// null = not answered yet (blocks the import), true = one governorate,
  /// false = deliberately region-free.
  bool? _regionLockedScope; // region-lock (NEW only)
  bool _loading = true;
  Object? _loadError;

  Uint8List? _pickedBytes;
  String? _pickedExt;
  String? _fileName;
  List<ParsedVoucher>? _preview;

  /// Lines the parser could not read. Never uploaded, and previously invisible —
  /// the result banner reported them only as part of a bare "invalid" count.
  List<RejectedRow> _rejected = const [];

  bool _importing = false;
  double _progress = 0;
  // Rows actually written / rows in the file — the operator's question during a
  // 20k-row upload is "how many are in?", not "what percent?".
  int _uploadedRows = 0;
  int _uploadTotalRows = 0;
  BatchImportResult? _result;
  String? _error;

  // ── What the last import attempted, kept so the result is reconcilable ──────
  // The preview is cleared on success (the file is spent), but the reconciliation
  // download and the "sent to" line have to outlive it.
  List<ParsedVoucher> _attempted = const [];
  List<RejectedRow> _attemptedRejected = const [];
  String? _resultTargetLabel;

  /// Set when a chunked upload died part-way: the rows before this index ARE on
  /// the server (UX-85). Null on a clean run.
  PartialImportException? _partial;

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
          // Deliberately NOT defaulted (UX-14) — see the picker below. The
          // category may default; the warehouse thousands of codes land in
          // may not.
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

  /// Extensions this page can actually parse.
  static const _readableExtensions = {'txt', 'csv', 'xlsx'};

  Future<void> _pickFile() async {
    // Deliberately FileType.any rather than a custom extension filter.
    // A filter greys the file out in the OS dialog, which is indistinguishable
    // from "this app will not take my file" — the customer's report was exactly
    // that ("ميستقبل الملفات"). An .xls, an uppercase .TXT or a file the OS
    // types oddly all vanish behind such a filter. Taking any file and then
    // explaining what happened is the honest version: the user can always select
    // what they have, and gets a reason when it cannot be read.
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      setState(() => _error = AppLocalizations.of(context)!.batchAddErrorReadBytes);
      return;
    }
    final ext = file.extension?.toLowerCase();
    if (ext != null && !_readableExtensions.contains(ext)) {
      if (!mounted) return;
      setState(() {
        _pickedBytes = null;
        _pickedExt = null;
        _fileName = null;
        _preview = null;
        _rejected = const [];
        _error = ext == 'xls'
            ? _tr(
                context,
                'صيغة xls القديمة غير مدعومة. افتح الملف في Excel واحفظه بصيغة '
                    'xlsx ثم أعد رفعه.',
                'The legacy .xls format is not supported. Open it in Excel, save '
                    'as .xlsx and upload again.')
            : _tr(
                context,
                'صيغة الملف (.$ext) غير مدعومة. الصيغ المقبولة: xlsx أو csv أو txt.',
                'That file type (.$ext) is not supported. Accepted formats: '
                    'xlsx, csv or txt.');
      });
      return;
    }
    setState(() {
      _pickedBytes = bytes;
      // A file with no extension is treated as text, which is what a pasted-code
      // export usually is.
      _pickedExt = ext ?? 'txt';
      _fileName = file.name;
      _result = null;
      _partial = null;
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
      final parsed = _pickedExt == 'xlsx'
          ? _parseXlsx(bytes, _format)
          : parseVoucherFileDetailed(
              utf8.decode(bytes, allowMalformed: true), _format);
      setState(() {
        _preview = parsed.rows;
        _rejected = parsed.rejected;
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
        _rejected = const [];
        _pickedBytes = null;
        _pickedExt = null;
        _fileName = null;
        _error = null;
      });
      return;
    }
    final detected = detectFormat(text);
    try {
      final parsed = parseVoucherFileDetailed(text, detected ?? _format);
      setState(() {
        if (detected != null) _format = detected;
        _pickedBytes = Uint8List.fromList(utf8.encode(text));
        _pickedExt = 'txt';
        _fileName = _tr(context, 'نص ملصوق', 'pasted text');
        _preview = parsed.rows;
        _rejected = parsed.rejected;
        _result = null;
        _partial = null;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e, context));
    }
  }

  /// Required fields not yet satisfied — drives the pre-upload guard + hint.
  ///
  /// The decision itself lives in [batchImportMissing], a pure function, for the
  /// same reason [batchRowDecide] does: this gate is the only thing standing
  /// between a mistyped screen and thousands of codes in the wrong warehouse,
  /// and a rule buried in widget state cannot be tested without driving the
  /// whole page. This method only turns the answer into words.
  List<String> _missing() => batchImportMissing(
        hasCategory: _selectedDef != null,
        hasWarehouse: _target != null,
        hasVouchers: _preview != null && _preview!.isNotEmpty,
        regionLockedFormat: _format.regionLocked,
        regionLockedScope: _regionLockedScope,
        hasGovernorate: _selectedGovernorate != null,
      ).map((r) => switch (r) {
        BatchImportRequirement.category => _tr(context, 'الفئة', 'Category'),
        BatchImportRequirement.warehouse =>
          _tr(context, 'الوكيل الرئيسي', 'Main Agent'),
        BatchImportRequirement.vouchers =>
          _tr(context, 'قسائم صالحة', 'valid vouchers'),
        BatchImportRequirement.saleScope =>
          _tr(context, 'نطاق البيع', 'sale scope'),
        BatchImportRequirement.governorate =>
          _tr(context, 'المحافظة', 'governorate'),
      }).toList();

  /// Says in words what the chosen scope will do, because the consequence lands
  /// weeks later at a POS counter rather than here.
  String _scopeSummary(BuildContext context) {
    if (_regionLockedScope == null) {
      return _tr(context, 'اختر نطاق البيع قبل الرفع.',
          'Choose where these cards can be sold before importing.');
    }
    if (_regionLockedScope == false) {
      return _tr(context, 'ستكون هذه الكروت قابلة للبيع في كل المحافظات.',
          'These cards will be sellable in every governorate.');
    }
    final gov = _selectedGovernorate;
    if (gov == null) {
      return _tr(context, 'اختر المحافظة.', 'Choose the governorate.');
    }
    final name = governorateLabel(gov, Localizations.localeOf(context).languageCode);
    return _tr(context, 'ستكون هذه الكروت قابلة للبيع في $name فقط.',
        'These cards will be sellable in $name only.');
  }

  /// The import button and the red "Required: …" line must never disagree —
  /// the gate IS the missing-field list. Before this, `_canImport` re-stated
  /// three of the four checks and dropped the sale scope, so the button stayed
  /// pressable with no scope answered and the upload went out with
  /// `governorate: null` — stock sellable in all 18 governorates (C-08).
  bool get _canImport => _missing().isEmpty;

  ParsedImport _parseXlsx(Uint8List bytes, ImportFormat format) {
    final book = Excel.decodeBytes(bytes);
    final sheets = book.tables.values.where((t) => t.maxRows > 0).toList();
    if (sheets.isEmpty) return const ParsedImport();
    final rows = sheets.first.rows;
    final out = <ParsedVoucher>[];
    final rejected = <RejectedRow>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      String cell(int i) =>
          (i < row.length ? row[i]?.value?.toString().trim() : '') ?? '';
      final serial = cell(0);
      if (r == 0 && serial.toLowerCase().contains('serial')) continue; // header
      final pin = cell(1);
      if (serial.isEmpty && pin.isEmpty) continue; // a spacer row, not a loss
      if (serial.isEmpty || pin.isEmpty) {
        // Named, not silently dropped: a spreadsheet row with a serial and no
        // PIN is a supplier mistake the operator has to go and fix.
        rejected.add(RejectedRow(
          line: r + 1,
          text: serial.isEmpty ? pin : serial,
          reason: serial.isEmpty ? 'serial' : 'pin',
        ));
        continue;
      }
      final expiry = normalizeExpiry(cell(2));
      final label = format == ImportFormat.other
          ? (cell(3).isEmpty ? null : cell(3))
          : null;
      out.add(ParsedVoucher(
          serial: serial, pin: pin, expiry: expiry, label: label));
    }
    return ParsedImport(rows: out, rejected: rejected);
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
        // B-106: name the type for SAF, or the picker can write a document
        // whose MIME does not match its .xlsx name → "unknown format".
        path = await FilePicker.platform.saveFile(
            dialogTitle: l.batchAddDownloadTemplate,
            fileName: fileName,
            bytes: bytes,
            type: FileType.custom,
            allowedExtensions: const ['xlsx']);
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
      showOk(context, l.batchAddTemplateSaved);
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
      _rejected = const [];
      _result = null;
      _partial = null;
      _attempted = const [];
      _attemptedRejected = const [];
      _error = null;
      _progress = 0;
    });
  }

  /// Uploads the parsed rows, starting at [from] — a partial failure retry sends
  /// only the tail that never reached the server.
  Future<void> _import({int from = 0}) async {
    final def = _selectedDef;
    final target = _target;
    if (_preview == null || _preview!.isEmpty || def == null || target == null) {
      return;
    }
    // Second gate, deliberately duplicated: an unanswered sale scope must not be
    // able to reach the wire as `governorate: null` (C-08), whatever state the
    // button is in.
    if (_format.regionLocked && _regionLockedScope == null) return;
    final rows = _preview!;
    final rejected = _rejected;
    final targetLabel = target.label;
    // Carry the earlier chunks' counts through a retry so the banner keeps
    // reporting the WHOLE upload, not just the tail.
    final carried = from > 0 ? _result : null;
    setState(() {
      _importing = true;
      _progress = from == 0 ? 0 : from / rows.length;
      _uploadedRows = from;
      _uploadTotalRows = rows.length;
      _result = null;
      _partial = null;
      _error = null;
    });
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final gov = _format.regionLocked ? _selectedGovernorate : null;
      var res = await repo.batchImport(
        definitionId: def.id,
        ownerId: target.id,
        governorate: gov,
        type: _format.wire,
        vouchers: rows,
        from: from,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _progress = total == 0 ? 1 : done / total;
              _uploadedRows = done;
              _uploadTotalRows = total;
            });
          }
        },
      );
      if (carried != null) res = carried.merge(res);
      if (!mounted) return;
      setState(() {
        _importing = false;
        _result = res;
        _resultTargetLabel = targetLabel;
        _attempted = rows;
        _attemptedRejected = rejected;
        _preview = null;
        _rejected = const [];
        _pickedBytes = null;
        _fileName = null;
      });
      // UX-05: the Batches tab used not to refresh at all, so the batch just
      // created was invisible until the operator navigated away and back.
      if (res.batchIds.isNotEmpty) {
        ref.read(_batchFocusProvider.notifier).state =
            _BatchFocus(res.batchIds, DateTime.now().microsecondsSinceEpoch);
      }
    } on PartialImportException catch (e) {
      // UX-85: everything before `sentRows` IS on the server, owned and
      // sellable. Reporting a bare error made the operator re-upload and then
      // distrust the "duplicates" count the retry produced.
      if (!mounted) return;
      setState(() {
        _importing = false;
        _result =
            carried == null ? e.partial : carried.merge(e.partial);
        _resultTargetLabel = targetLabel;
        _attempted = rows;
        _attemptedRejected = rejected;
        _partial = e;
        // The preview stays: the remaining rows are the retry.
        _uploadedRows = e.sentRows;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        if (carried == null) {
          _error = friendlyError(e, context);
          return;
        }
        // A retry whose FIRST chunk failed: nothing new landed, but the earlier
        // attempt's vouchers are still on the server. Reverting to a bare error
        // here would re-tell exactly the lie UX-85 is about.
        _result = carried;
        _resultTargetLabel = targetLabel;
        _attempted = rows;
        _attemptedRejected = rejected;
        _partial = PartialImportException(
          partial: carried,
          cause: e,
          sentRows: from,
          totalRows: rows.length,
        );
        _uploadedRows = from;
      });
    }
  }

  /// UX-05: a per-serial reconciliation of the import, so a 20k-row file can be
  /// diffed against the supplier's list instead of eyeballed from three numbers
  /// and the first 20 duplicate serials.
  Future<void> _downloadReconciliation() async {
    final res = _result;
    if (res == null) return;
    final saveTitle = _tr(context, 'حفظ الملف', 'Save file');
    final csv = buildReconciliationCsv(
      attempted: _attempted,
      duplicateSerials: res.skippedSerials.toSet(),
      rejected: _attemptedRejected,
      sentRows: _partial?.sentRows,
      label: (k) => switch (k) {
        'imported' => _tr(context, 'تم الاستيراد', 'imported'),
        'duplicate' => _tr(context, 'مكرر — موجود مسبقاً', 'duplicate — already on file'),
        'notsent' => _tr(context, 'لم يُرسل — أعد المحاولة', 'not sent — retry'),
        'columns' => _tr(context, 'أعمدة ناقصة', 'not enough columns'),
        'serial' => _tr(context, 'رقم تسلسلي فارغ', 'blank serial'),
        'pin' => _tr(context, 'رمز فارغ', 'blank PIN'),
        _ => k,
      },
    );
    // A BOM so Excel opens the Arabic reason column as UTF-8 rather than mojibake.
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    final fileName = 'import_reconciliation.csv';
    try {
      if (kIsWeb) {
        downloadBytes(fileName, bytes);
      } else if (Platform.isAndroid || Platform.isIOS) {
        await FilePicker.platform.saveFile(
          dialogTitle: saveTitle,
          fileName: fileName,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: const ['csv'],
        );
      } else {
        final path = await FilePicker.platform
            .saveFile(dialogTitle: saveTitle, fileName: fileName);
        if (path != null) {
          final finalPath =
              path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
          await File(finalPath).writeAsBytes(bytes);
        }
      }
      if (mounted) {
        showOk(context, _tr(context, 'تم تحميل الملف', 'File downloaded'));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// What the upload actually did.
  ///
  /// C-18 ("المطلوب إظهار اسم الوكيل الذي رُفعت إليه البضاعة"): the headline names
  /// the receiving agent, so the target is confirmable AFTER committing and not
  /// only from the dropdown before it.
  ///
  /// UX-85: when the upload stopped part-way this stays a result, not an error —
  /// the rows already sent are live stock. It says what landed, what did not, and
  /// that retrying is safe because the server dedups on serial.
  Widget _resultBanner(ColorScheme cs) {
    final res = _result!;
    final partial = _partial;
    final to = _resultTargetLabel;
    final ids = res.batchIds;
    return InkCard(
      ruleColor: partial != null ? cs.error : context.tones.brandInk,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              partial != null ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              size: 18,
              color: partial != null ? cs.error : context.status.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                to == null
                    ? _tr(context, 'تم استيراد ${Formatters.money(res.imported)} قسيمة',
                        '${Formatters.money(res.imported)} vouchers imported')
                    : _tr(
                        context,
                        'تم استيراد ${Formatters.money(res.imported)} قسيمة إلى $to',
                        '${Formatters.money(res.imported)} imported to $to',
                      ),
                style: IntesharType.sans(14.5,
                    color: cs.onSurface, w: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            _tr(
              context,
              'مكرر: ${res.skipped} • غير صالح: ${res.invalid}',
              'Duplicate: ${res.skipped} • invalid: ${res.invalid}',
            ),
            style: IntesharType.sans(13, color: cs.onSurfaceVariant, w: FontWeight.w600),
          ),
          // ── Partial upload (UX-85) ───────────────────────────────────
          if (partial != null) ...[
            const SizedBox(height: 10),
            Text(
              _tr(
                context,
                'توقف الرفع بعد ${Formatters.money(partial.sentRows)} من '
                    '${Formatters.money(partial.totalRows)} صف. القسائم أعلاه '
                    'موجودة فعلاً على الخادم وقابلة للبيع — لم تُفقد.',
                'The upload stopped after ${Formatters.money(partial.sentRows)} of '
                    '${Formatters.money(partial.totalRows)} rows. The vouchers above '
                    'ARE already on the server and sellable — nothing was lost.',
              ),
              style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              friendlyError(partial.cause, context),
              style: IntesharType.sans(12.5, color: context.status.danger, w: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _tr(
                context,
                'إعادة الرفع آمنة: الخادم يتجاهل أي رقم تسلسلي موجود مسبقاً، '
                    'فلن تتكرر أي قسيمة.',
                'Retrying is safe: the server ignores any serial it already has, '
                    'so no voucher can be duplicated.',
              ),
              style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
            ),
          ],
          // ── Actions ──────────────────────────────────────────────────
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (partial != null && partial.remainingRows > 0)
                FilledButton.icon(
                  onPressed: _importing
                      ? null
                      : () => _import(from: partial.sentRows),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_tr(
                    context,
                    'إكمال المتبقي (${Formatters.money(partial.remainingRows)})',
                    'Upload the remaining ${Formatters.money(partial.remainingRows)}',
                  )),
                ),
              if (ids.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => ref.read(_batchFocusProvider.notifier).state =
                      _BatchFocus(ids, DateTime.now().microsecondsSinceEpoch),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(ids.length == 1
                      ? _tr(context, 'فتح الدفعة', 'Open this batch')
                      : _tr(context, 'فتح الدفعات (${ids.length})',
                          'Open the ${ids.length} batches')),
                ),
              OutlinedButton.icon(
                onPressed: _downloadReconciliation,
                icon: const Icon(Icons.table_view_outlined, size: 18),
                label: Text(_tr(context, 'تقرير المطابقة', 'Reconciliation CSV')),
              ),
              // B-089: start the next upload without leaving the page.
              if (partial == null)
                FilledButton.icon(
                  onPressed: _resetForAnother,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: Text(_tr(context, 'رفع ملف آخر', 'Upload another file')),
                ),
            ],
          ),
          // Which serials were skipped as duplicates (first 20) — the full list is
          // in the reconciliation CSV above.
          if (res.skippedSerials.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _tr(
                context,
                'أرقام مكررة: ${res.skippedSerials.take(20).join('، ')}${res.skippedSerials.length > 20 ? ' …' : ''}',
                'Duplicate serials: ${res.skippedSerials.take(20).join(', ')}${res.skippedSerials.length > 20 ? ' …' : ''}',
              ),
              style: IntesharType.mono(11.5,
                  color: cs.onSurfaceVariant, w: FontWeight.w600),
            ),
          ],
          // Rows the parser threw away BEFORE the upload. The server never saw
          // them, so its `invalid` count cannot mention them.
          if (_attemptedRejected.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _tr(
                context,
                'صفوف غير مقروءة لم تُرسل: ${_attemptedRejected.length} '
                    '(الأسطر ${_attemptedRejected.take(10).map((r) => r.line).join('، ')}'
                    '${_attemptedRejected.length > 10 ? ' …' : ''})',
                'Unreadable rows never sent: ${_attemptedRejected.length} '
                    '(lines ${_attemptedRejected.take(10).map((r) => r.line).join(', ')}'
                    '${_attemptedRejected.length > 10 ? ' …' : ''})',
              ),
              style: IntesharType.sans(12, color: context.status.danger, w: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return LoadingState(
          message: _tr(context, 'جارٍ تحميل الفئات والوكلاء…',
              'Loading categories and agents…'));
    }
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
              // UX-14: was a flat dropdown over a `listAll(size: 200)` snapshot —
              // the weakest picker in the app on the screen where picking wrong is
              // most expensive. Now the shared server-searched picker, which does
              // not truncate and can be typed into.
              //
              // And it starts EMPTY. It used to default to `agent1s.first`, which
              // made the `_target == null` guard below unreachable: an operator who
              // never touched this field handed thousands of vouchers to whichever
              // agent happened to sort first. Same failure C-08 fixed for the sale
              // scope — an unanswered question has to look unanswered.
              InkWell(
                onTap: () async {
                  final picked = await showEntitySearchPicker(
                    context,
                    repository: EntityRepository(ref.read(apiClientProvider)),
                    title: _tr(context, 'اختر الوكيل الرئيسي', 'Pick the Main Agent'),
                    types: const [EntityType.AGENT1],
                  );
                  if (picked != null && mounted) setState(() => _target = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText:
                        _tr(context, 'تُرفع إلى الوكيل الرئيسي', 'Hand to Main Agent'),
                    suffixIcon: const Icon(Icons.manage_search),
                    errorText: _target == null
                        ? _tr(context, 'اختر الوكيل المستلم', 'Choose the receiving agent')
                        : null,
                  ),
                  child: Text(
                    _target?.label ??
                        _tr(context, 'لم يُختر بعد', 'Not chosen yet'),
                    style: IntesharType.sans(
                      14,
                      color: _target == null ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 22),

            // ── City / governorate (NEW only) ────────────────────────────
            //
            // C-08: this used to be one optional dropdown that defaulted to
            // "not geo-locked", and nothing asked about it before importing. So
            // an operator uploading "for Karbala" produced stock sellable
            // EVERYWHERE and was never told — which is exactly what the customer
            // reported, and what every voucher on the server looks like.
            //
            // The scope is now a decision with two named outcomes. Region-free
            // is still available; it just has to be chosen.
            if (isNew) ...[
              SectionLabel(_tr(context, 'نطاق البيع', 'Where these can be sold')),
              // An unanswered scope must LOOK unanswered: `{_regionLockedScope ??
              // true}` painted "One governorate" as already chosen while the
              // value was still null, so nothing on the page looked missing.
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: true,
                      label: Text(_tr(context, 'محافظة محددة', 'One governorate'))),
                  ButtonSegment(
                      value: false,
                      label: Text(_tr(context, 'كل المحافظات', 'All governorates'))),
                ],
                selected: _regionLockedScope == null
                    ? const <bool>{}
                    : {_regionLockedScope!},
                emptySelectionAllowed: true,
                onSelectionChanged: (v) => setState(() {
                  // An empty selection here would be the operator un-choosing;
                  // keep the last answer rather than silently reopening the hole.
                  if (v.isEmpty) return;
                  _regionLockedScope = v.first;
                  if (!v.first) _selectedGovernorate = null;
                }),
              ),
              if (_regionLockedScope == true) ...[
                const SizedBox(height: 12),
                GovernorateDropdown(
                  value: _selectedGovernorate,
                  // Inside the "one governorate" branch the null option is an
                  // unanswered question, not a second way to say "everywhere" —
                  // that choice is the segment above, and leaving this on null
                  // now blocks the import rather than shipping sell-anywhere stock.
                  noneLabel: _tr(context, '— اختر المحافظة —', '— Choose a governorate —'),
                  labelText: l.batchAddGovernorate,
                  onChanged: (v) => setState(() => _selectedGovernorate = v),
                ),
              ],
              const SizedBox(height: 8),
              Builder(builder: (context) {
                // While the scope is still open the summary is not a note, it is
                // the outstanding question — so it carries the error colour.
                final unanswered = _regionLockedScope == null ||
                    (_regionLockedScope == true && _selectedGovernorate == null);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (unanswered) ...[
                      Icon(Icons.error_outline, size: 15, color: context.status.danger),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        _scopeSummary(context),
                        style: IntesharType.sans(
                          12.5,
                          color: unanswered ? context.status.danger : cs.onSurfaceVariant,
                          w: unanswered ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                );
              }),
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
              _resultBanner(cs),
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
              // Rows the parser could not read are named BEFORE the upload —
              // afterwards the server can only report them as a bare "invalid"
              // count, because a row it rejects has no serial to name.
              if (_rejected.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _tr(
                    context,
                    '${_rejected.length} صفاً غير مقروء سيُتجاهل '
                        '(الأسطر ${_rejected.take(10).map((r) => r.line).join('، ')}'
                        '${_rejected.length > 10 ? ' …' : ''})',
                    '${_rejected.length} unreadable rows will be skipped '
                        '(lines ${_rejected.take(10).map((r) => r.line).join(', ')}'
                        '${_rejected.length > 10 ? ' …' : ''})',
                  ),
                  style: IntesharType.sans(12, color: context.status.danger, w: FontWeight.w600),
                ),
              ],
              // B-090: the primary action sits ABOVE the preview — it used to be the
              // very last thing on a long page, so the operator had to scroll past
              // everything to start the import they had already decided on.
              const SizedBox(height: 12),
              if (_missing().isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${_tr(context, 'مطلوب: ', 'Required: ')}${_missing().join(_tr(context, '، ', ', '))}',
                    style: IntesharType.sans(12, color: context.status.danger, w: FontWeight.w600),
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
                  // Rows, not a second copy of the percentage already on the right.
                  label:
                      '${Formatters.money(_uploadedRows)} / ${Formatters.money(_uploadTotalRows)}',
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

  /// Overline. Defaults to the voucher-upload wording; the bulk batch actions
  /// pass their own, because "جارٍ الرفع" over a pause/withdraw is the same
  /// class of lie UX-86 fixed here.
  final String? title;
  const _ProgressBlock(
      {required this.progress, required this.label, this.title});

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
                // UX-86: this bar has never printed anything — it is the
                // voucher UPLOAD, and it said "جارٍ الطباعة" on the highest-stakes
                // admin task.
                title ?? l.batchAddUploading,
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

/// How the batch list is ordered. Newest-first is the import log; the others exist
/// because a supplier recall is a hunt, not a scroll.
enum _BatchSort { newest, oldest, availableDesc, name }

class _BatchesTabState extends ConsumerState<_BatchesTab> {
  List<VoucherBatch>? _batches;
  bool _loading = true;
  Object? _error;
  // Batch IDs currently awaiting a server response (pause/delete/export).
  final Set<String> _busy = {};

  // ── UX-06: an unbounded flat list of near-identical cards ──────────────────
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  /// null = every status, true = paused only, false = active only.
  bool? _pausedFilter;

  /// ownerId, or null for every agent. C-18 makes this a usable axis: before the
  /// owner was rendered, "which agent" was not a thing you could see, let alone
  /// filter by.
  String? _ownerFilter;
  _BatchSort _sort = _BatchSort.newest;

  /// Batches a just-finished import created — pinned alone until dismissed.
  Set<String> _focusIds = const {};

  /// The last `_BatchFocus.tick` this tab acted on, so one import pins once.
  int _appliedFocusTick = 0;

  // ── Multi-select: Pause/Withdraw are the recall levers, and a recall is
  // never one batch.
  bool _selecting = false;
  final Set<String> _selected = {};

  /// Non-null while a bulk action runs — the whole list is inert until it ends.
  String? _bulkLabel;
  int _bulkDone = 0;
  int _bulkTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final batches = await repo.listBatches();
      if (mounted) {
        setState(() {
          _batches = batches;
          _loading = false;
          // Drop selections for rows that no longer exist.
          _selected.removeWhere((id) => !batches.any((b) => b.id == id));
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  /// The rows actually shown: focus pin → search → status → owner → sort.
  List<VoucherBatch> _visible(List<VoucherBatch> all) {
    var out = all;
    if (_focusIds.isNotEmpty) {
      out = out.where((b) => _focusIds.contains(b.id)).toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((b) {
        return b.productName.toLowerCase().contains(q) ||
            b.sku.toLowerCase().contains(q) ||
            (b.ownerName ?? '').toLowerCase().contains(q) ||
            (b.governorate ?? '').toLowerCase().contains(q) ||
            b.type.toLowerCase().contains(q) ||
            b.id.toLowerCase().contains(q);
      }).toList();
    }
    if (_pausedFilter != null) {
      out = out.where((b) => b.paused == _pausedFilter).toList();
    }
    if (_ownerFilter != null) {
      out = out.where((b) => b.ownerId == _ownerFilter).toList();
    }
    out = [...out];
    switch (_sort) {
      case _BatchSort.newest:
        out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _BatchSort.oldest:
        out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _BatchSort.availableDesc:
        out.sort((a, b) => b.availableCount.compareTo(a.availableCount));
      case _BatchSort.name:
        out.sort((a, b) => (a.productName.isEmpty ? a.sku : a.productName)
            .compareTo(b.productName.isEmpty ? b.sku : b.productName));
    }
    return out;
  }

  bool get _filtered =>
      _query.trim().isNotEmpty ||
      _pausedFilter != null ||
      _ownerFilter != null ||
      _focusIds.isNotEmpty;

  void _clearFilters() => setState(() {
        _searchCtrl.clear();
        _query = '';
        _pausedFilter = null;
        _ownerFilter = null;
        _focusIds = const {};
      });

  Future<void> _togglePause(VoucherBatch batch) async {
    if (_busy.contains(batch.id)) return;
    setState(() => _busy.add(batch.id));
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      await repo.pauseBatch(batch.id, pause: !batch.paused);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(batch.id));
    }
  }

  Future<void> _confirmDelete(VoucherBatch batch) async {
    if (_busy.contains(batch.id)) return;
    final confirmed = await showConfirm(
      context,
      title: _tr(context, 'حذف الدفعة', 'Delete batch'),
      body: _tr(
        context,
        'سيتم حذف جميع القسائم في هذه الدفعة نهائياً. لا يمكن التراجع.',
        'All vouchers in this batch will be permanently deleted. This cannot be undone.',
      ),
      confirmLabel: _tr(context, 'حذف', 'Delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(batch.id));
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      await repo.deleteBatch(batch.id);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
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
          type: FileType.custom,
          allowedExtensions: const ['txt'],
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
      if (mounted) showOk(context, fileDownloadedMsg);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(batch.id));
    }
  }

  Future<void> _withdraw(VoucherBatch batch) async {
    if (_busy.contains(batch.id)) return;
    final confirmed = await showConfirm(
      context,
      title: _tr(context, 'سحب الدفعة', 'Withdraw batch'),
      body: _tr(
        context,
        'سيتم سحب جميع القسائم غير المستخدمة في هذه الدفعة إلى المقر. القسائم المستخدمة لا يمكن استرجاعها.',
        'All UNUSED vouchers in this batch will be reclaimed to HQ. Used vouchers cannot be recovered.',
      ),
      confirmLabel: _tr(context, 'سحب', 'Withdraw'),
      icon: Icons.undo_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(batch.id));
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final result = await repo.withdrawBatch(batch.id);
      if (mounted) {
        showOk(
          context,
          _tr(context, 'تم سحب ${result.reclaimed} • مُستخدَم ${result.used}',
              'Reclaimed ${result.reclaimed} • Used ${result.used}'),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(batch.id));
    }
  }

  // ── Bulk actions (UX-06) ───────────────────────────────────────────────────

  /// Runs [action] over the selected batches one at a time, reporting progress
  /// and a per-batch failure count rather than dying on the first refusal — a
  /// recall that stops half-way is worse than one that reports what it missed.
  Future<void> _runBulk({
    required String label,
    required String confirmTitle,
    required String confirmBody,
    required bool destructive,
    required Future<void> Function(ProductRepository repo, VoucherBatch b) action,
  }) async {
    final all = _batches ?? const <VoucherBatch>[];
    final targets =
        all.where((b) => _selected.contains(b.id)).toList(growable: false);
    if (targets.isEmpty || _bulkLabel != null) return;
    final ok = await showConfirm(
      context,
      title: confirmTitle,
      body: confirmBody,
      confirmLabel: label,
      destructive: destructive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _bulkLabel = label;
      _bulkDone = 0;
      _bulkTotal = targets.length;
    });
    final repo = ProductRepository(ref.read(apiClientProvider));
    var failed = 0;
    Object? lastError;
    for (final b in targets) {
      try {
        await action(repo, b);
      } catch (e) {
        failed++;
        lastError = e;
      }
      if (!mounted) return;
      setState(() => _bulkDone++);
    }
    if (!mounted) return;
    setState(() {
      _bulkLabel = null;
      _selecting = false;
      _selected.clear();
    });
    await _load();
    if (!mounted) return;
    if (failed == 0) {
      showOk(
          context,
          _tr(context, 'تم على ${targets.length} دفعة',
              'Done on ${targets.length} batches'));
    } else {
      final why = friendlyError(lastError!, context);
      showError(
        context,
        _tr(
          context,
          'فشل $failed من ${targets.length}: $why',
          '$failed of ${targets.length} failed: $why',
        ),
      );
    }
  }

  Future<void> _bulkPause(bool pause) => _runBulk(
        label: pause
            ? _tr(context, 'إيقاف مؤقت', 'Pause')
            : _tr(context, 'استئناف', 'Resume'),
        confirmTitle: pause
            ? _tr(context, 'إيقاف ${_selected.length} دفعة؟',
                'Pause ${_selected.length} batches?')
            : _tr(context, 'استئناف ${_selected.length} دفعة؟',
                'Resume ${_selected.length} batches?'),
        confirmBody: pause
            ? _tr(context, 'لن تُباع أي قسيمة من هذه الدفعات حتى الاستئناف.',
                'No voucher from these batches can be sold until they are resumed.')
            : _tr(context, 'ستعود هذه الدفعات قابلة للبيع.',
                'These batches become sellable again.'),
        destructive: pause,
        action: (repo, b) => repo.pauseBatch(b.id, pause: pause),
      );

  Future<void> _bulkWithdraw() => _runBulk(
        label: _tr(context, 'سحب', 'Withdraw'),
        confirmTitle: _tr(context, 'سحب ${_selected.length} دفعة؟',
            'Withdraw ${_selected.length} batches?'),
        confirmBody: _tr(
          context,
          'سيتم سحب جميع القسائم غير المستخدمة في هذه الدفعات إلى المقر. '
              'القسائم المستخدمة لا يمكن استرجاعها.',
          'All UNUSED vouchers in these batches will be reclaimed to HQ. '
              'Used vouchers cannot be recovered.',
        ),
        destructive: true,
        action: (repo, b) => repo.withdrawBatch(b.id),
      );

  @override
  Widget build(BuildContext context) {
    // UX-05: a finished import pins the batches it just created AND reloads —
    // this tab used not to refresh at all, so the new batch was invisible.
    //
    // Deliberately a `watch` + tick and NOT a `ref.listen`: the import happens on
    // the OTHER tab, and switching to this one is what builds this widget for the
    // first time. A listener registered during that build would never see the
    // change that caused it. The event is cleared once applied so it cannot
    // re-pin on a later visit.
    final focus = ref.watch(_batchFocusProvider);
    if (focus != null && focus.tick != _appliedFocusTick) {
      _appliedFocusTick = focus.tick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _focusIds = focus.batchIds.toSet();
          _searchCtrl.clear();
          _query = '';
          _pausedFilter = null;
          _ownerFilter = null;
          _selecting = false;
          _selected.clear();
        });
        ref.read(_batchFocusProvider.notifier).state = null;
        _load();
      });
    }

    if (_loading) {
      return LoadingState(
          message: _tr(context, 'جارٍ تحميل الدفعات…', 'Loading batches…'));
    }
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
    final visible = _visible(batches);
    final bulkRunning = _bulkLabel != null;
    return Column(
      children: [
        _controls(batches, visible),
        if (bulkRunning)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
            child: _ProgressBlock(
              progress: _bulkTotal == 0 ? 0 : _bulkDone / _bulkTotal,
              title: _bulkLabel,
              label: _tr(context, '$_bulkDone من $_bulkTotal دفعة',
                  '$_bulkDone of $_bulkTotal batches'),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  message: _tr(context, 'لا توجد دفعة تطابق البحث',
                      'No batch matches this search'),
                  actionLabel: _tr(context, 'مسح الفلاتر', 'Clear filters'),
                  onAction: _clearFilters,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final b = visible[i];
                      return _BatchCard(
                        batch: b,
                        busy: _busy.contains(b.id) || bulkRunning,
                        selecting: _selecting,
                        selected: _selected.contains(b.id),
                        onSelect: () => setState(() {
                          if (!_selected.remove(b.id)) _selected.add(b.id);
                        }),
                        onTogglePause: () => _togglePause(b),
                        onDelete: () => _confirmDelete(b),
                        onExport: () => _export(b),
                        onWithdraw: () => _withdraw(b),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  /// Search, status/owner filters, sort and the multi-select bar.
  ///
  /// UX-06: before this the tab was an unbounded flat list of cards whose only
  /// identity was a product name and a string-sliced timestamp, and Pause /
  /// Withdraw — the two levers of a supplier recall — could only be pulled one
  /// card at a time.
  Widget _controls(List<VoucherBatch> all, List<VoucherBatch> visible) {
    final cs = Theme.of(context).colorScheme;
    final owners = <String, String>{};
    for (final b in all) {
      if (b.ownerId.isEmpty) continue;
      owners[b.ownerId] = (b.ownerName ?? '').isNotEmpty ? b.ownerName! : b.ownerId;
    }
    final busy = _bulkLabel != null;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                enabled: !busy,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: _tr(context, 'ابحث بالفئة أو الوكيل أو المحافظة',
                      'Search product, agent or governorate'),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          // UX-150: a bare × beside a search box is the one
                          // control a screen reader announces as just "button".
                          tooltip: _tr(context, 'مسح البحث', 'Clear search'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _searchCtrl.clear();
                            _query = '';
                          }),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<_BatchSort>(
              enabled: !busy,
              tooltip: _tr(context, 'الترتيب', 'Sort'),
              icon: const Icon(Icons.sort, size: 20),
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: _BatchSort.newest,
                    child: Text(_tr(context, 'الأحدث أولاً', 'Newest first'))),
                PopupMenuItem(
                    value: _BatchSort.oldest,
                    child: Text(_tr(context, 'الأقدم أولاً', 'Oldest first'))),
                PopupMenuItem(
                    value: _BatchSort.availableDesc,
                    child: Text(_tr(context, 'الأكثر متاحاً', 'Most available'))),
                PopupMenuItem(
                    value: _BatchSort.name,
                    child: Text(_tr(context, 'حسب الفئة', 'By product'))),
              ],
            ),
            IconButton(
              tooltip: _tr(context, 'تحديد متعدد', 'Select several'),
              isSelected: _selecting,
              icon: const Icon(Icons.checklist, size: 20),
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _selecting = !_selecting;
                        if (!_selecting) _selected.clear();
                      }),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_focusIds.isNotEmpty)
                InputChip(
                  avatar: const Icon(Icons.new_releases_outlined, size: 16),
                  label: Text(_tr(context, 'الرفع الأخير', 'Just uploaded')),
                  onDeleted: () => setState(() => _focusIds = const {}),
                ),
              FilterChip(
                label: Text(_tr(context, 'الكل', 'All')),
                selected: _pausedFilter == null,
                onSelected: busy ? null : (_) => setState(() => _pausedFilter = null),
              ),
              FilterChip(
                label: Text(_tr(context, 'نشط', 'Active')),
                selected: _pausedFilter == false,
                onSelected: busy ? null : (_) => setState(() => _pausedFilter = false),
              ),
              FilterChip(
                label: Text(_tr(context, 'موقوف', 'Paused')),
                selected: _pausedFilter == true,
                onSelected: busy ? null : (_) => setState(() => _pausedFilter = true),
              ),
              if (owners.length > 1)
                // C-18 turns the owning agent into something you can filter by.
                PopupMenuButton<String?>(
                  enabled: !busy,
                  initialValue: _ownerFilter,
                  onSelected: (v) => setState(() => _ownerFilter = v),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: null,
                        child: Text(_tr(context, 'كل الوكلاء', 'All agents'))),
                    for (final e in owners.entries)
                      PopupMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.store_outlined, size: 16),
                    label: Text(_ownerFilter == null
                        ? _tr(context, 'كل الوكلاء', 'All agents')
                        : (owners[_ownerFilter] ?? _ownerFilter!)),
                  ),
                ),
              if (_filtered)
                TextButton.icon(
                  onPressed: busy ? null : _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                  label: Text(_tr(context, 'مسح', 'Clear')),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _tr(context, 'عرض ${visible.length} من ${all.length}',
                'Showing ${visible.length} of ${all.length}'),
            style: IntesharType.sans(11.5, color: cs.onSurfaceVariant),
          ),
          if (_selecting) ...[
            const SizedBox(height: 8),
            InkCard(
              ruleColor: context.tones.brandInk,
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _tr(context, 'محدد: ${_selected.length}',
                        '${_selected.length} selected'),
                    style: IntesharType.sans(13,
                        color: cs.onSurface, w: FontWeight.w800),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                              _selected
                                ..clear()
                                ..addAll(visible.map((b) => b.id));
                            }),
                    child: Text(_tr(context, 'تحديد المعروض', 'Select shown')),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: busy ? null : () => setState(_selected.clear),
                      child: Text(_tr(context, 'إلغاء التحديد', 'Clear')),
                    ),
                  OutlinedButton.icon(
                    onPressed:
                        (_selected.isEmpty || busy) ? null : () => _bulkPause(true),
                    icon: const Icon(Icons.pause_outlined, size: 16),
                    label: Text(_tr(context, 'إيقاف', 'Pause')),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        (_selected.isEmpty || busy) ? null : () => _bulkPause(false),
                    icon: const Icon(Icons.play_arrow_outlined, size: 16),
                    label: Text(_tr(context, 'استئناف', 'Resume')),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_selected.isEmpty || busy) ? null : _bulkWithdraw,
                    style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                    icon: const Icon(Icons.undo_outlined, size: 16),
                    label: Text(_tr(context, 'سحب', 'Withdraw')),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Batch card ────────────────────────────────────────────────────────────────

class _BatchCard extends StatelessWidget {
  final VoucherBatch batch;
  final bool busy;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTogglePause;
  final VoidCallback onDelete;
  final VoidCallback onExport;
  final VoidCallback onWithdraw;

  const _BatchCard({
    required this.batch,
    required this.busy,
    this.selecting = false,
    this.selected = false,
    required this.onSelect,
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
      ruleColor: selected
          ? context.tones.brand
          : (paused ? cs.outline : context.tones.brandInk),
      padding: const EdgeInsets.all(14),
      onTap: selecting ? onSelect : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: product name + status badge
          Row(children: [
            if (selecting) ...[
              Checkbox(
                value: selected,
                onChanged: busy ? null : (_) => onSelect(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
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
          // C-18 ("المطلوب إظهار اسم الوكيل الذي رُفعت إليه البضاعة"): the owning
          // agent is resolved server-side and was parsed and then dropped, so two
          // uploads of the same category differed only by a sliced timestamp —
          // and the one fact that tells them apart, WHO GOT THE STOCK, was the
          // one missing.
          if ((batch.ownerName ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.store_outlined, size: 14, color: context.tones.brandOnSurface),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  batch.ownerName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(13,
                      color: context.tones.brandOnSurface, w: FontWeight.w700),
                ),
              ),
            ]),
          ],
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
              // UX-128: a USED card is a card that sold — the happy path. It is
              // brand, and never `danger`. This exact field was gold on the
              // inventory screen and red here, one tap apart.
              color: batch.printedCount > 0
                  ? context.status.brand
                  : cs.onSurfaceVariant,
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
                // "والزر خلي يتغير لونة عند الضغط" — a paused batch is a state
                // somebody has to notice from across the room, so the button
                // carries the colour rather than only swapping its icon.
                paused
                    ? FilledButton.icon(
                        onPressed: onTogglePause,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError,
                        ),
                        icon: const Icon(Icons.play_arrow_outlined, size: 16),
                        label: Text(_tr(context, 'استئناف', 'Resume')),
                      )
                    : OutlinedButton.icon(
                        onPressed: onTogglePause,
                        icon: const Icon(Icons.pause_outlined, size: 16),
                        label: Text(_tr(context, 'إيقاف مؤقت', 'Pause')),
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
