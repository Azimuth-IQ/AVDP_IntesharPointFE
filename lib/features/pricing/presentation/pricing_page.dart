import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/core/files/report_export.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/price_filter.dart';
import 'package:inteshar/features/pricing/domain/price_sheet.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) =>
      _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('Pricing', 'التسعير');
  String get title => p('Prices', 'الأسعار');
  String get subtitle =>
      p('Set your selling price per category', 'حدّد سعر بيعك لكل فئة');
  String get balanceLabel => p('Inventory worth', 'قيمة المخزون');
  // UX-20: two large IQD figures live one tap apart — this one and the
  // dashboard's الرصيد (base − grantsOut). They never agree, so each has to
  // state what it is made of instead of leaving the operator to guess.
  String get worthBasis =>
      p('available × official price', 'المتوفر × السعر الرسمي');
  String unpriced(int n) => p('$n unpriced', '$n بدون سعر');
  String get official => p('Official', 'الرسمي');
  // UX-21: "الرسمي" alone never said which side of the trade it is. For an agent
  // pricing its own account the platform default IS what it pays — its cost.
  String get officialCost => p('Official (your cost)', 'الرسمي (كلفتك)');
  String get yourPrice => p('Your price', 'سعرك');
  // UX-23: with a sub-agent selected, "سعرك" is a lie on every field and, worse,
  // on the exported sheet's column header — two agents, two sheets, one column
  // name is exactly how the wrong prices get uploaded to the wrong agent.
  String priceOf(String agent) => p('$agent’s price', 'سعر $agent');
  // UX-21: the one number the business runs on, computed instead of subtracted
  // 40 times by hand. "Margin" only when it IS the caller's margin.
  String get margin => p('Your margin', 'هامشك');
  String get vsOfficial => p('vs official', 'الفرق عن الرسمي');
  String get belowCost => p('below cost', 'دون الكلفة');
  // Pricing someone else's account, the official price is not THEIR cost (their
  // cost is my price), so the warning stays factual about what it compared.
  String get belowOfficial => p('below official', 'دون السعر الرسمي');
  String get available => p('Available', 'المتوفر');
  String get lineValue => p('Value', 'القيمة');
  // UX-22: the value readout is deliberately independent of the price typed
  // (B-082 — stock is valued at the platform price). Say so, or lowering a price
  // and watching it not move reads as "it didn't save".
  String get atOfficialPrice => p('at official price', 'بالسعر الرسمي');
  String get save => p('Save prices', 'حفظ الأسعار');
  String get saved => p('Prices saved', 'تم حفظ الأسعار');
  String get uncategorized => p('Uncategorized', 'بدون شركة');
  String get empty =>
      p('No categories in the catalog yet.', 'لا توجد فئات في الكتالوج بعد.');
  String get byGovernorate => p('By governorate', 'حسب المحافظة');
  String get untagged => p('No region', 'بدون محافظة');
  String get allRegions => p('All regions', 'كل المحافظات');
  String get unauthorized =>
      p('Pricing access not granted', 'لا تملك صلاحية إدارة الأسعار');
  String get exportXlsx => p('Export', 'تصدير');
  String get uploadXlsx => p('Upload', 'رفع');
  String get applyToSelf => p('Apply to me', 'تطبيق على حسابي');
  String get alsoAgents => p('Also apply to agents…', 'تطبيق على وكلاء أيضاً…');
  // B-125: apply one sheet to every sub-agent in one action.
  String allSubAgents(int n) =>
      p('All my sub-agents ($n)', 'كل وكلائي الفرعيين ($n)');
  String get clearTargets => p('Clear', 'مسح');
  String get colSku => p('SKU', 'الرمز');
  String get colName => p('Name', 'الاسم');
  String get colGov => p('Governorate', 'المحافظة');
  String get searchHint => p('Search category, SKU or company…', 'ابحث بالفئة أو الرمز أو الشركة…');
  String get company => p('Company', 'الشركة');
  String get allCompanies => p('All companies', 'كل الشركات');
  String get allGovernorates => p('All governorates', 'كل المحافظات');
  String get clearFilters => p('Clear filters', 'مسح عوامل التصفية');
  String get colOfficial => p('Official price', 'السعر الرسمي');
  String get colYour => p('Your price', 'سعرك');
  String parsed(int n) => p('$n prices parsed', 'تم قراءة $n سعر');
  String applied(int agents) => p('Applied to $agents account(s)', 'تم التطبيق على $agents حساب');
  String get nothingParsed => p('No prices found in the file', 'لا توجد أسعار في الملف');
  // B-117: export/upload follow the filters on screen.
  String get nothingToExport =>
      p('Nothing to export in the current filter', 'لا توجد بيانات ضمن التصفية الحالية');
  String scopedTo(String scope) =>
      p('Export & upload follow: $scope', 'التصدير والرفع يتبعان: $scope');
  // B-121/B-126: whose prices are being edited.
  String get pricingFor => p('Pricing for', 'التسعير لـ');
  String get myOwnPrices => p('My own prices', 'أسعار حسابي');
  // UX-21: name the direction. This screen sets what the caller's CHILDREN pay
  // it; the official price is what the caller itself pays.
  String get pricingForMeHint => p(
      'Your selling prices — what your agents and shops pay you.',
      'أسعار بيعك — ما يدفعه وكلاؤك ومتاجرك لك.');
  // UX-23: this is the price the sub-agent SELLS at — what its own shops pay it —
  // not what it pays me. The old wording left that open, and the whole screen
  // hinges on it (`buildDebitChain` prices a shop at its parent's rate).
  String get pricingForAgentHint => p(
      'This sub-agent’s selling price — what its shops pay it. Export and upload follow this choice.',
      'سعر بيع هذا الوكيل الفرعي — ما تدفعه متاجره له. التصدير والرفع يتبعان هذا الاختيار.');
  String get cancel => p('Cancel', 'إلغاء');
  String get apply => p('Apply', 'تطبيق');
  // UX-69: a bare number in a box labelled "بغداد" reads as a price, a stock
  // count or a value with equal plausibility. Name the currency, name the field,
  // and keep the governorate as a heading rather than as the field's own label.
  String get currency => p('IQD', 'د.ع');
  String get edited => p('Edited', 'معدّل');
  String saveN(int n) => p('Save prices ($n)', 'حفظ الأسعار ($n)');
  // UX-68: switching the pricing target reloads the catalog, which disposes every
  // controller — a screenful of typed prices used to vanish with no prompt.
  String get unsavedTitle => p('Unsaved prices', 'أسعار غير محفوظة');
  String unsavedBody(int n) => p(
      '$n price(s) you typed have not been saved. Leaving now discards them.',
      'لديك $n سعر لم يتم حفظه. المغادرة الآن ستتجاهلها.');
  String get keepEditing => p('Keep editing', 'متابعة التعديل');
  String get discard => p('Discard', 'تجاهل');
}

/// One decimal below 10%, whole numbers above — and never a trailing `.0`, so a
/// 25% margin reads "25%" rather than "25.0%" (UX-21).
String _pct(num v) {
  if (v >= 10) return v.round().toString();
  final one = v.toStringAsFixed(1);
  return one.endsWith('.0') ? one.substring(0, one.length - 2) : one;
}

/// A SKU is "regional" when its stock is broken down by governorate (a real
/// governorate bucket, or more than one bucket). Regional SKUs are priced ONLY
/// per governorate — they get no standalone global/"all regions" price (B-041).
bool _regionalRow(CategoryPriceRow row) =>
    row.governorates.length > 1 ||
    (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);

class PricingPage extends ConsumerStatefulWidget {
  const PricingPage({super.key});

  @override
  ConsumerState<PricingPage> createState() => _PricingPageState();
}

class _PricingPageState extends ConsumerState<PricingPage> {
  PricingCatalog? _catalog;
  bool _loading = true;
  bool _saving = false;
  bool _unpricedOnly = false; // B-080: filter the list to categories still on defaults
  // B-114: the unpriced pill was the ONLY filter — no way to find one category in
  // a multi-company catalog, or to see just the SKUs priced for one governorate.
  String _query = '';
  // B-121: WHICH account these prices belong to. Null = my own. A Main Agent
  // picks a sub-agent and the whole screen — list, export, upload — follows it.
  String? _targetId;
  String _targetName = '';
  List<EntitySummaryRow> _subAgents = const [];
  String _company = ''; // '' = every company
  String _gov = ''; // '' = every governorate
  Object? _error;

  /// B-117: one description of "in scope", shared by the list, the Excel export
  /// and the upload. Derived rather than stored so it cannot fall out of step
  /// with the controls that set these fields.
  PriceFilter get _filter => PriceFilter(
        query: _query,
        company: _company,
        governorate: _gov,
        unpricedOnly: _unpricedOnly,
      );
  bool _authorized = true;

  /// UX-68: set for the single frame in which an answered discard prompt lets the
  /// route pop; otherwise [PopScope] would veto its own retry forever.
  bool _allowPop = false;

  /// Rebuilds the target dropdown from scratch after a REJECTED change, so it
  /// snaps back to the account still being edited — `DropdownButtonFormField`
  /// takes `initialValue` only on first build, so its internal state would
  /// otherwise keep showing the account we refused to switch to (UX-68).
  int _pickerEpoch = 0;

  final Map<String, TextEditingController> _ctrls = {};

  /// UX-69: the value each field was LOADED with, so an edited row can be marked
  /// before the single bottom Save writes it. Same key space as [_ctrls].
  final Map<String, String> _original = {};

  /// How many fields currently differ from what was loaded — the Save button says
  /// it, so "which of my 60 rows will be written" is answerable without counting.
  final ValueNotifier<int> _dirtyCount = ValueNotifier<int>(0);

  bool _fieldDirty(String key) =>
      parseAmount(_ctrls[key]?.text) != parseAmount(_original[key]);

  /// UX-68: anything typed and not yet written by the bottom Save. Both exits
  /// that throw it away — switching the pricing target (which reloads and
  /// disposes every controller) and leaving the route — go through
  /// [_confirmDiscard] first.
  ///
  /// Mirrors the guard already in `voucher_templates_page.dart` (`_dirty` + a
  /// discard/keep dialog) rather than inventing a second idiom for it.
  Future<bool> _confirmDiscard(_S s) async {
    final n = _dirtyCount.value;
    if (n == 0) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.unsavedTitle),
        content: Text(s.unsavedBody(n)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.discard),
          ),
        ],
      ),
    );
    return discard == true;
  }

  void _recountDirty() {
    final n = _ctrls.keys.where(_fieldDirty).length;
    if (_dirtyCount.value != n) _dirtyCount.value = n;
  }

  PricingRepository get _repo => PricingRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    // Guard: only agents with MANAGE_PRICING may load the catalog. An AGENT1
    // user that reaches this route without the capability sees an empty state
    // and the catalog fetch is skipped entirely (no needless server call).
    final auth = ref.read(authStateProvider).valueOrNull;
    _authorized =
        auth is AuthAuthenticated && auth.can({Capability.MANAGE_PRICING});
    if (_authorized) {
      _load();
      _loadSubAgents();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _dirtyCount.dispose();
    super.dispose();
  }

  /// B-121: the accounts this one may price for. Best-effort — the picker simply
  /// does not appear when there are none (a sub-agent pricing itself, or an agent
  /// with no children), which is the correct behaviour rather than an empty
  /// dropdown.
  ///
  /// UX-30 asked for STORE children to be added here so a Main Agent could price
  /// for a directly-attached shop. Deliberately NOT done — a price row written
  /// against a STORE is never read by anything:
  ///
  ///   * `InventoryController.buildDebitChain` (BE:1117) starts the price cascade
  ///     at the CALLER'S PARENT — "a store sells at the sub-agent's price".
  ///   * `/product/sellable` (BE:570) uses `priceTier = target.getParent()` for
  ///     every wallet-backed target (AGENT2/STORE).
  ///   * `TransactionProcessor.computeOrderCost` prices at `sourceId`, the seller.
  ///
  /// The pricing axis is the SELLER, so `AgentPrice(entityId = someStore)` would
  /// only ever govern that store's own children — and a STORE is a leaf. Widening
  /// the picker would hand the operator a field that saves successfully, reloads
  /// with their number in it, and changes nothing anyone is ever charged.
  Future<void> _loadSubAgents() async {
    try {
      final rows = await EntityRepository(ref.read(apiClientProvider))
          .children((ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id ?? '',
              page: 0, size: 200);
      if (!mounted) return;
      setState(() => _subAgents =
          rows.items.where((e) => e.type == EntityType.AGENT2).toList());
    } catch (_) {
      // No picker; the screen still prices the caller's own account.
    }
  }

  /// UX-23: what the editable column actually is. Pricing my own account it is
  /// "my price"; with a target selected it names that account, so the field, the
  /// margin caption and the exported sheet's header all agree on whose price
  /// this is.
  /// [maxChars] is deliberately tight: this lands in a 152px field's floating
  /// label, which clips rather than wrapping. The exported sheet's header takes
  /// the full name — it has the room.
  String _priceLabel(_S s, {int maxChars = 12}) {
    if (_targetId == null || _targetName.trim().isEmpty) return s.yourPrice;
    final n = _targetName.trim();
    return s.priceOf(
        n.length > maxChars ? '${n.substring(0, maxChars - 1)}…' : n);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _repo.catalog(entityId: _targetId);
      if (!mounted) return;
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      _original.clear();
      for (final row in catalog.rows) {
        // Base (SKU-wide) field keyed "sku::"; one field per governorate keyed "sku::gov".
        _bind('${row.sku}::', row.effectivePrice);
        for (final g in row.governorates) {
          _bind('${row.sku}::${g.governorate}', g.effectivePrice);
        }
      }
      _recountDirty();
      setState(() {
        _catalog = catalog;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Creates the field for [key], remembers what it was loaded with, and keeps
  /// the dirty count live as the operator types (UX-69).
  void _bind(String key, num value) {
    final text = _fmt(value);
    _original[key] = text;
    _ctrls[key] = TextEditingController(text: text)..addListener(_recountDirty);
  }

  String _fmt(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  Future<void> _save() async {
    final s = _S.of(context);
    final catalog = _catalog;
    if (catalog == null) return;
    setState(() => _saving = true);
    try {
      for (final row in catalog.rows) {
        if (!_regionalRow(row)) {
          // Non-regional: a single SKU-wide base price.
          final baseVal = parseAmount(_ctrls['${row.sku}::']?.text);
          if (baseVal != null &&
              (row.agentPrice == null || row.agentPrice != baseVal)) {
            await _repo.setPrice(entityId: _targetId ?? '', sku: row.sku, price: baseVal);
          }
          continue;
        }
        // Regional: per-governorate prices ONLY (no standalone global price). The
        // untagged "" bucket, if any, is saved here too via its own governorate row.
        for (final g in row.governorates) {
          final value = parseAmount(_ctrls['${row.sku}::${g.governorate}']?.text);
          if (value == null) continue;
          if (g.agentPrice == null || g.agentPrice != value) {
            await _repo.setPrice(
              entityId: _targetId ?? '',
              sku: row.sku,
              governorate: g.governorate,
              price: value,
            );
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.saved)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// B-059: download the catalog to XLSX — official prices as the baseline, plus
  /// a "your price" column (current price if set, else the official default).
  /// Filename-safe agent name. Arabic is kept — the OS handles it and a
  /// transliteration would make the file harder for the operator to recognise.
  String _slugName(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'agent' : cleaned;
  }

  Future<void> _exportXlsx(_S s) async {
    final catalog = _catalog;
    if (catalog == null) return;
    // B-114: the governorate column read as "missing" because it held a raw code
    // for regional SKUs and was EMPTY for the rest — and most SKUs are untagged.
    // Write a readable name, and say "all governorates" explicitly rather than
    // leaving a blank the customer has to interpret. The upload path resolves
    // both back (governorateFromAnything), so an exported sheet still re-imports.
    //
    // B-117: the sheet is the FILTERED view. Exporting everything while the
    // screen showed one governorate is what made the export unusable — you had
    // to re-filter in Excel to find the rows you were already looking at.
    final loc = Localizations.localeOf(context).languageCode;
    final filter = _filter;
    //
    // UX-42: the two price columns go out as real numbers, so the sheet can be
    // summed and sorted in Excel instead of being 60 rows of left-aligned text.
    // The upload reads a numeric cell back as its digits, so the round trip is
    // unchanged.
    final rows = buildPriceSheetCells(
      rows: catalog.rows,
      filter: filter,
      locale: loc,
      allGovernoratesLabel: loc == 'ar' ? 'كل المحافظات' : 'All governorates',
    );
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.nothingToExport)));
      }
      return;
    }
    // B-123: the file is named for the agent it belongs to. Two sheets for two
    // sub-agents landing in Downloads as `inteshar-prices.xlsx` and
    // `inteshar-prices (1).xlsx` is how the wrong prices get uploaded back.
    final stem = _targetId == null
        ? priceSheetFileName(filter)
        : '${priceSheetFileName(filter)}-${_slugName(_targetName)}';
    // UX-23: the price column is named for the account it belongs to. The file
    // name already carried the agent (B-123) but the column inside still said
    // "سعرك", so two sheets open side by side in Excel were indistinguishable —
    // the last step before the wrong prices are uploaded to the wrong agent.
    // The upload parses by column INDEX (cells 0/2/4), so renaming the header is
    // safe for the round trip.
    await exportRowsToXlsx(
      fileName: stem,
      sheetName: 'Prices',
      headers: [
        s.colSku,
        s.colName,
        s.colGov,
        s.colOfficial,
        _targetId == null ? s.colYour : s.priceOf(_targetName.trim()),
      ],
      rows: rows,
    );
  }

  /// B-059: parse an edited price sheet and apply it — to me by default, with an
  /// optional multi-agent target. Columns: sku, name, governorate, official, your.
  Future<void> _uploadXlsx(_S s) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    final bytes = res?.files.firstOrNull?.bytes;
    if (bytes == null || !mounted) return;

    final parsed = <Map<String, dynamic>>[];
    var sheetDataRows = 0; // rows below the header we attempted to read
    try {
      final book = Excel.decodeBytes(bytes);
      for (final table in book.tables.values) {
        sheetDataRows = (table.rows.length - 1).clamp(0, 1 << 30);
        for (var i = 1; i < table.rows.length; i++) {
          final r = table.rows[i];
          String cell(int idx) =>
              (idx < r.length ? r[idx]?.value?.toString().trim() : '') ?? '';
          final sku = cell(0);
          // B-114: the sheet now carries a readable governorate, so map it back.
          // Anything unrecognised (incl. the "all governorates" marker and older
          // sheets' blanks) means SKU-wide, which is what '' encodes.
          final gov = governorateFromAnything(cell(2)) ?? '';
          final priceStr = cell(4).replaceAll(',', '');
          final price = num.tryParse(priceStr);
          if (sku.isEmpty || price == null) continue;
          parsed.add({'sku': sku, 'governorate': gov, 'price': price});
        }
        break; // first sheet only
      }
    } catch (_) {
      // Fall through to the "nothing parsed" message.
    }
    if (!mounted) return;

    // B-117: the upload obeys the same scope as the view and the export. A
    // filtered screen is a working scope, so a sheet carrying other companies or
    // regions must not quietly rewrite prices the operator cannot even see.
    // Skipped rows are COUNTED and shown — silently dropping them would be the
    // same failure as silently applying them.
    // B-124: the upload is NO LONGER narrowed by the on-screen filter. B-117 tied
    // them together; the customer asked for the opposite ("الغاء رفع ملف الأسعار
    // حسب التصفية"), and with the agent picker doing the scoping (B-121) the
    // filter is a view convenience again, not a write scope. A sheet applies in
    // full to the chosen account(s), so nothing is silently held back.

    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.nothingParsed)));
      return;
    }

    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final myId = (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id ?? '';

    // Confirm with a PREVIEW of exactly what will change + an explicit target.
    final extraAgents = <String, String>{}; // id -> name
    // Default target follows the picker: editing a sub-agent uploads to THAT
    // agent, not silently to my own account (B-121).
    var applyToSelf = _targetId == null;
    if (_targetId != null) extraAgents[_targetId!] = _targetName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final cs = Theme.of(ctx).colorScheme;
          final canApply = applyToSelf || extraAgents.isNotEmpty;
          return AlertDialog(
            title: Text(s.uploadXlsx),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Recognized N of M — warn (error tint) when the sheet had rows we couldn't read.
                Text(
                  sheetDataRows > parsed.length
                      ? (ar ? 'تم التعرف على ${parsed.length} من $sheetDataRows صفًا' : 'Recognized ${parsed.length} of $sheetDataRows rows')
                      : (ar ? 'تم التعرف على ${parsed.length} صفًا' : 'Recognized ${parsed.length} rows'),
                  style: IntesharType.sans(12.5,
                      color: sheetDataRows > parsed.length ? cs.error : cs.onSurfaceVariant, w: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                // Preview table: SKU · governorate · new price.
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: Column(children: [
                        for (final p in parsed)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            child: Row(children: [
                              Expanded(flex: 3, child: Text('${p['sku']}',
                                  style: IntesharType.mono(11.5, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
                              Expanded(flex: 2, child: Text(
                                  (p['governorate'] as String).isEmpty ? '—' : '${p['governorate']}',
                                  style: IntesharType.sans(11.5, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                              Text(Formatters.iqd((p['price'] as num).round()),
                                  style: IntesharType.mono(11.5, color: cs.onSurface)),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Explicit target — checked by default writes MY prices. When agents
                // are added the id list becomes non-empty, so self is only included
                // if this stays checked (the API treats a non-empty list as exact).
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: applyToSelf,
                  onChanged: (v) => setD(() => applyToSelf = v ?? false),
                  title: Text(ar ? 'تطبيق على حسابي' : 'Apply to my account',
                      style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w600)),
                ),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in extraAgents.entries)
                    InputChip(
                      label: Text(e.value, overflow: TextOverflow.ellipsis),
                      onDeleted: () => setD(() => extraAgents.remove(e.key)),
                    ),
                ]),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showEntitySearchPicker(
                        ctx,
                        repository: EntityRepository(ref.read(apiClientProvider)),
                        title: s.alsoAgents,
                        // Sellers only — see [_loadSubAgents] for why a STORE is
                        // not a meaningful pricing target (UX-30).
                        types: const [EntityType.AGENT1, EntityType.AGENT2],
                      );
                      if (picked != null) setD(() => extraAgents[picked.id] = picked.label);
                    },
                    icon: const Icon(Icons.group_add, size: 16),
                    label: Text(s.alsoAgents),
                  ),
                  // B-125: 'اريد تحديد كل الوكلاء دفعة واحدة'. Picking sub-agents
                  // one at a time was the whole complaint. The count is on the
                  // button because this writes prices to every one of them.
                  if (_subAgents.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => setD(() {
                        for (final a in _subAgents) {
                          extraAgents[a.id] = a.name;
                        }
                      }),
                      icon: const Icon(Icons.select_all, size: 16),
                      label: Text(s.allSubAgents(_subAgents.length)),
                    ),
                  if (extraAgents.isNotEmpty)
                    TextButton(
                      onPressed: () => setD(extraAgents.clear),
                      child: Text(s.clearTargets),
                    ),
                ]),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
              FilledButton(onPressed: canApply ? () => Navigator.pop(ctx, true) : null, child: Text(s.apply)),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;

    // Build the target list. Empty ⇒ caller only (server default). A NON-empty
    // list is treated as EXACTLY those entities, so self must be added explicitly
    // whenever we also target other agents.
    final targetIds = <String>[];
    if (extraAgents.isNotEmpty) {
      if (applyToSelf && myId.isNotEmpty) targetIds.add(myId);
      targetIds.addAll(extraAgents.keys);
    }

    setState(() => _saving = true);
    try {
      final result = await _repo.setBulk(
        prices: parsed,
        entityIds: targetIds, // empty = self only; non-empty = exactly these
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.applied(result.length))));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    // UX-68: leaving the route throws away every typed price exactly like
    // switching the target did. Same prompt on both exits.
    return ValueListenableBuilder<int>(
      valueListenable: _dirtyCount,
      builder: (context, dirty, child) => PopScope<Object?>(
        canPop: _allowPop || dirty == 0,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          // Resolved before the await so the prompt's async gap can't leave us
          // reaching into a defunct element for it.
          final nav = Navigator.of(context);
          if (!await _confirmDiscard(s) || !mounted) return;
          // The guard has been answered — let this one pop through rather than
          // zeroing the dirty count, which the Save button also reads.
          setState(() => _allowPop = true);
          await nav.maybePop();
          if (mounted) setState(() => _allowPop = false);
        },
        child: child!,
      ),
      child: _scaffold(s),
    );
  }

  Widget _scaffold(_S s) {
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: s.eyebrow,
            title: s.title,
            subtitle: s.subtitle,
            trailing: (_authorized && _catalog != null)
                ? Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _exportXlsx(s),
                      icon: const Icon(Icons.download, size: 16),
                      label: Text(s.exportXlsx),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _uploadXlsx(s),
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(s.uploadXlsx),
                    ),
                  ])
                : null,
          ),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }


  /// B-121: whose prices am I editing? B-126 puts each agent's governorate on the
  /// row, so the one-governorate rule is legible instead of assumed.
  Widget _agentPicker(_S s, String loc) {
    final cs = Theme.of(context).colorScheme;
    String labelFor(EntitySummaryRow r) {
      final g = r.governorates.isNotEmpty ? r.governorates.first : '';
      return g.isEmpty ? r.name : '${r.name} — ${governorateLabel(g, loc)}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DropdownButtonFormField<String?>(
        key: ValueKey('pricing-target-${_targetId ?? ''}-$_pickerEpoch'),
        initialValue: _targetId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: s.pricingFor,
          isDense: true,
          prefixIcon: const Icon(Icons.storefront_outlined, size: 18),
          helperText: _targetId == null ? s.pricingForMeHint : s.pricingForAgentHint,
          helperMaxLines: 2,
          helperStyle: IntesharType.sans(11, color: cs.onSurfaceVariant),
        ),
        items: [
          DropdownMenuItem(value: null, child: Text(s.myOwnPrices)),
          for (final a in _subAgents)
            DropdownMenuItem(
              value: a.id,
              child: Text(labelFor(a), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) async {
          if (v == _targetId) return;
          // UX-68: _load() disposes and clears every controller, so an unguarded
          // switch silently threw away a screenful of typed prices.
          if (!await _confirmDiscard(s)) {
            // Put the dropdown back on the account still being edited.
            if (mounted) setState(() => _pickerEpoch++);
            return;
          }
          if (!mounted) return;
          setState(() {
            _targetId = v;
            _targetName = v == null
                ? ''
                : _subAgents.firstWhere((a) => a.id == v).name;
          });
          // Reload: the catalog IS the target's prices, so a stale list would
          // show one agent's numbers under another agent's name.
          _load();
        },
      ),
    );
  }
  /// B-114: search + company + governorate, beside the existing unpriced pill.
  /// The pill was the only filter, so finding one category in a multi-company
  /// catalog meant scrolling.
  Widget _filterBar(_S s, String loc, List<String> companies, List<String> govs,
      int shown, int total) {
    final cs = Theme.of(context).colorScheme;
    final filtering = _query.isNotEmpty || _company.isNotEmpty || _gov.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(children: [
        TextField(
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: s.searchHint,
            // Say what the filter DID, not just that one is on.
            suffixText: filtering ? '$shown/$total' : null,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        if (companies.length > 1 || govs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            if (companies.length > 1)
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _company,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.company, isDense: true),
                  items: [
                    DropdownMenuItem(value: '', child: Text(s.allCompanies)),
                    for (final c in companies)
                      DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _company = v ?? ''),
                ),
              ),
            // B-122: the governorate dropdown is gone. A sub-agent covers exactly
            // one governorate (B-127), so choosing the AGENT already chooses the
            // region — two controls for one fact just let them disagree.
            if (filtering) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: s.clearFilters,
                icon: Icon(Icons.filter_alt_off_outlined, size: 20, color: cs.onSurfaceVariant),
                onPressed: () => setState(() {
                  _query = '';
                  _company = '';
                  _gov = '';
                }),
              ),
            ],
          ]),
        ],
        // B-117: Export/Upload sit up in the header, far from these controls, so
        // say here that they follow them — otherwise "Export" reads as "export
        // everything" and the scoped file looks like data loss.
        if (_filter.isActive) ...[
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              s.scopedTo(_scopeLabel(s, loc)),
              style: IntesharType.sans(11.5, color: cs.onSurfaceVariant, w: FontWeight.w600),
            ),
          ),
        ],
      ]),
    );
  }

  /// Human description of the active scope, for the hint and the dialogs.
  String _scopeLabel(_S s, String loc) {
    final parts = <String>[
      if (_company.isNotEmpty) _company,
      if (_gov.isNotEmpty) governorateLabel(_gov, loc),
      if (_unpricedOnly) (loc == 'ar' ? 'غير المسعّرة' : 'unpriced'),
      if (_query.trim().isNotEmpty) '"${_query.trim()}"',
    ];
    return parts.isEmpty ? s.allCompanies : parts.join(' · ');
  }

  Widget _body(_S s) {
    if (!_authorized) {
      final cs = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              s.unauthorized,
              style: IntesharType.sans(14, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final catalog = _catalog!;
    final cs = Theme.of(context).colorScheme;
    if (catalog.rows.isEmpty) {
      return Center(
        child: Text(
          s.empty,
          style: IntesharType.sans(14, color: cs.onSurfaceVariant),
        ),
      );
    }

    // Group rows by company, preserving the server's (company, name) order.
    // The "N unpriced" pill filters to categories still on default prices (B-080).
    final loc = Localizations.localeOf(context).languageCode;
    // B-117: the SAME filter object the export and the upload use, so what is
    // on screen and what lands in the sheet can never disagree.
    final visibleRows = _filter.apply(catalog.rows);
    final companies = <String>{
      for (final r in catalog.rows)
        if (r.companyName.isNotEmpty) r.companyName,
    }.toList()
      ..sort();
    final govs = <String>{
      for (final r in catalog.rows)
        for (final g in r.governorates)
          if (g.governorate.isNotEmpty) g.governorate,
    }.toList()
      ..sort();
    final groups = <String, List<CategoryPriceRow>>{};
    for (final row in visibleRows) {
      final key = row.companyName.isNotEmpty
          ? row.companyName
          : s.uncategorized;
      groups.putIfAbsent(key, () => []).add(row);
    }

    return Column(
      children: [
        _BalanceHeader(
          s: s,
          worth: catalog.inventoryWorth,
          unpriced: catalog.unpricedCount,
          unpricedOnly: _unpricedOnly,
          onToggleUnpriced: () => setState(() => _unpricedOnly = !_unpricedOnly),
        ),
        if (_subAgents.isNotEmpty) _agentPicker(s, loc),
        _filterBar(s, loc, companies, govs, visibleRows.length, catalog.rows.length),
        Expanded(
          child: visibleRows.isEmpty
              ? Center(
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'ar'
                        ? 'كل الفئات مُسعّرة.'
                        : 'All categories are priced.',
                    style: IntesharType.sans(14, color: cs.onSurfaceVariant),
                  ),
                )
              : ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
                  children: [
                    for (final entry in groups.entries) ...[
                      SectionLabel(entry.key),
                      ...entry.value.map(
                        (row) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _PriceRow(
                            row: row,
                            ctrls: _ctrls,
                            original: _original,
                            s: s,
                            // UX-23: whose price this column is.
                            priceLabel: _priceLabel(s),
                            // UX-21: "margin" is only the caller's margin when the
                            // caller is the one being priced.
                            forSelf: _targetId == null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: SizedBox(
              width: double.infinity,
              // UX-69: the one Save writes every edited field, so it says how many
              // it is about to write. "Save prices" over 60 rows told the operator
              // nothing about what they had actually changed.
              child: ValueListenableBuilder<int>(
                valueListenable: _dirtyCount,
                builder: (context, dirty, _) => FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(dirty > 0 ? s.saveN(dirty) : s.save),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  final _S s;
  final num worth;
  final int unpriced;
  final bool unpricedOnly;
  final VoidCallback onToggleUnpriced;
  const _BalanceHeader({
    required this.s,
    required this.worth,
    required this.unpriced,
    required this.unpricedOnly,
    required this.onToggleUnpriced,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: context.tones.brand,
        borderRadius: BorderRadius.circular(IntesharRadii.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.balanceLabel,
                  style: IntesharType.overline(
                    color: IntesharColors.ink.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      Formatters.iqd(worth.round()),
                      style: const TextStyle(
                        fontFamily: 'CodecPro',
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: IntesharColors.ink,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                // UX-20: this and the dashboard's الرصيد (credited − granted out)
                // are two large IQD figures one tap apart that never agree,
                // because they are not the same quantity. Neither stated its
                // basis; this one now does.
                const SizedBox(height: 4),
                Text(
                  s.worthBasis,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(11,
                      color: IntesharColors.ink.withValues(alpha: 0.75),
                      w: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (unpriced > 0)
            // Tap to filter the list to just the unpriced categories (toggle).
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onToggleUnpriced,
              child: Opacity(
                opacity: unpricedOnly ? 1 : 0.85,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  StampPill(label: s.unpriced(unpriced), color: cs.error),
                  const SizedBox(width: 4),
                  Icon(unpricedOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
                      size: 16, color: IntesharColors.ink.withValues(alpha: 0.7)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final CategoryPriceRow row;
  final Map<String, TextEditingController> ctrls;

  /// UX-69: the loaded values, so the card can flag itself as edited.
  final Map<String, String> original;
  final _S s;

  /// UX-23: what the editable column is called — "سعرك" only when these really
  /// are the caller's own prices, otherwise the target account's name.
  final String priceLabel;

  /// UX-21: true when the caller is pricing its own account, so the computed
  /// difference from the official price IS its margin.
  final bool forSelf;
  const _PriceRow({
    required this.row,
    required this.ctrls,
    required this.original,
    required this.s,
    required this.priceLabel,
    required this.forSelf,
  });

  /// The field keys this card actually RENDERS (a regional row shows only its
  /// per-governorate fields, never the SKU-wide one).
  List<String> get _keys => _regionalRow(row)
      ? [for (final g in row.governorates) '${row.sku}::${g.governorate}']
      : ['${row.sku}::'];

  bool _dirty(String k) =>
      parseAmount(ctrls[k]?.text) != parseAmount(original[k]);

  @override
  Widget build(BuildContext context) {
    final listenables = [
      for (final k in _keys)
        if (ctrls[k] != null) ctrls[k]!,
    ];
    // Rebuilds only THIS card as its own fields change — the page above does not
    // rebuild per keystroke.
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) => _card(context, _keys.any(_dirty)),
    );
  }

  Widget _card(BuildContext context, bool dirty) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    final regional = _regionalRow(row);
    return InkCard(
      padding: const EdgeInsets.all(14),
      ruleColor: row.priced ? IntesharColors.sage : cs.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.name,
                  style: IntesharType.sans(
                    15,
                    color: cs.onSurface,
                    w: FontWeight.w700,
                  ),
                ),
              ),
              // UX-69: an unsaved edit is visible on the row it belongs to, so a
              // list of 60 says which 10 the bottom Save is about to write.
              if (dirty) ...[
                StampPill(
                  label: s.edited,
                  color: context.tones.brandInk,
                  icon: Icons.edit_outlined,
                  filled: false,
                ),
                const SizedBox(width: 8),
              ],
              // UX-21: the two numbers on this card are a BUY and a SELL price
              // and nothing said which. The platform default is what this agent
              // pays, so name it that when the agent is pricing itself.
              Flexible(
                child: Text(
                  '${forSelf ? s.officialCost : s.official}: '
                  '${Formatters.iqd(row.officialPrice.round())}',
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  style: IntesharType.mono(11.5, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!regional)
            // Non-regional category: one price for all its (untagged) stock.
            _PriceField(
              ctrl: ctrls['${row.sku}::'],
              original: original['${row.sku}::'] ?? '',
              available: row.available,
              lineValue: row.lineValue,
              // The backend sets the same official price on the row and on every
              // one of its governorate lines (PricingHelper writes one `off` for
              // all of them), so one value is correct for every field here.
              officialPrice: row.officialPrice,
              priceLabel: priceLabel,
              forSelf: forSelf,
              s: s,
            )
          else ...[
            // Regional category: price ONLY per governorate — no global price (B-041).
            Text(
              s.byGovernorate,
              style: IntesharType.overline(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            ...row.governorates.map((g) {
              final label = g.governorate.isEmpty
                  ? s.untagged
                  : governorateLabel(g.governorate, loc);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _PriceField(
                  // The governorate is a HEADING over the field now, not the
                  // field's label — the box itself says "your price · IQD".
                  region: label,
                  ctrl: ctrls['${row.sku}::${g.governorate}'],
                  original: original['${row.sku}::${g.governorate}'] ?? '',
                  available: g.available,
                  lineValue: g.lineValue,
                  officialPrice: g.officialPrice,
                  priceLabel: priceLabel,
                  forSelf: forSelf,
                  s: s,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  /// The governorate this price applies to, for a regional row. Null on a
  /// SKU-wide field. UX-69: it used to BE the field's label, which made a bare
  /// number under "بغداد" ambiguous between price, stock and value.
  final String? region;
  final TextEditingController? ctrl;

  /// The value loaded from the server — anything else means unsaved.
  final String original;
  final int available;

  /// `available × officialPrice`. UX-22: deliberately NOT a function of the price
  /// typed (B-082 — stock is valued at the platform price), which is exactly why
  /// it may not sit inside the input's row pretending to be its result.
  final num lineValue;

  /// The platform default for this SKU — the agent's cost, and the baseline the
  /// margin is measured against (UX-21).
  final num officialPrice;

  /// UX-23: the editable column's name — "سعرك", or the target account's.
  final String priceLabel;

  /// UX-21: whether the computed difference is the caller's own margin.
  final bool forSelf;
  final _S s;
  const _PriceField({
    this.region,
    required this.ctrl,
    required this.original,
    required this.available,
    required this.lineValue,
    required this.officialPrice,
    required this.priceLabel,
    required this.forSelf,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    if (c == null) return _content(context, false, null);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: c,
      builder: (context, v, _) => _content(
        context,
        parseAmount(v.text) != parseAmount(original),
        parseAmount(v.text),
      ),
    );
  }

  /// UX-21: the one number the business runs on, computed instead of subtracted
  /// by hand once per category. Absolute + percent of cost, tinted (and worded,
  /// and iconed — never colour alone) when the agent would be selling at a loss.
  Widget _marginBlock(BuildContext context, num? typed) {
    final cs = Theme.of(context).colorScheme;
    // The currency rides on the caption, so the number itself stays short enough
    // to sit beside a 152px field on a POS handheld without ellipsizing.
    final label = Text(
      '${forSelf ? s.margin : s.vsOfficial} · ${s.currency}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: IntesharType.overline(color: cs.onSurfaceVariant),
    );
    if (typed == null) {
      // Empty field — no price, so no margin to state. Say nothing rather than
      // showing a margin of "−cost".
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          Text('—', style: IntesharType.mono(12.5, color: cs.onSurfaceVariant)),
        ],
      );
    }
    final m = typed - officialPrice;
    final negative = m < 0;
    final sign = m > 0 ? '+' : (negative ? '−' : '');
    // Percent of cost. Only meaningful against a non-zero official price — an
    // unpriced SKU would otherwise divide by zero and read "∞%".
    final pct = officialPrice > 0 ? ((m / officialPrice) * 100).abs() : null;
    final pctText = pct == null ? '' : ' (${_pct(pct)}%)';
    final color = negative ? cs.error : cs.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        label,
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (negative) ...[
              Icon(Icons.trending_down, size: 14, color: cs.error),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                '$sign${Formatters.money(m.abs())}$pctText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.mono(12.5, color: color, w: FontWeight.w800),
              ),
            ),
          ],
        ),
        // Not colour alone.
        if (negative)
          Text(
            forSelf ? s.belowCost : s.belowOfficial,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IntesharType.sans(11, color: cs.error, w: FontWeight.w700),
          ),
      ],
    );
  }

  Widget _content(BuildContext context, bool dirty, num? typed) {
    final cs = Theme.of(context).colorScheme;
    final brandInk = context.tones.brandInk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (region != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(Icons.place_outlined,
                  size: 13, color: dirty ? brandInk : cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  // Not colour alone: the edited line says so in words.
                  dirty ? '${region!} · ${s.edited}' : region!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(12,
                      color: dirty ? brandInk : cs.onSurfaceVariant,
                      w: dirty ? FontWeight.w800 : FontWeight.w600),
                ),
              ),
            ]),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 152,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: const [ThousandsInputFormatter()],
                style: IntesharType.mono(14, color: cs.onSurface),
                decoration: InputDecoration(
                  // Always says WHAT the number is, whose it is (UX-23), and in
                  // which currency.
                  labelText: priceLabel,
                  isDense: true,
                  suffixText: s.currency,
                  suffixStyle: IntesharType.sans(11.5, color: cs.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // UX-21: the margin sits where the value used to — beside the field,
            // because unlike the value it IS a function of what is typed.
            Expanded(child: _marginBlock(context, typed)),
          ],
        ),
        // UX-22: stock and its value are facts about the inventory, not results
        // of this input, so they live on their own line below it and say what
        // they are priced at. In the input's row at equal weight, a value that
        // did not move when the price dropped read as "it didn't save".
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(
              '${s.available}: ${Formatters.money(available)}',
              style: IntesharType.sans(12, color: cs.onSurfaceVariant),
            ),
            Text(
              '${s.lineValue}: ${Formatters.iqd(lineValue.round())} · ${s.atOfficialPrice}',
              style: IntesharType.sans(12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}
