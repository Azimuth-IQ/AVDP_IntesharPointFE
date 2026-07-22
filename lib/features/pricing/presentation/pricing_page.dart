import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
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
  String unpriced(int n) => p('$n unpriced', '$n بدون سعر');
  String get official => p('Official', 'الرسمي');
  String get yourPrice => p('Your price', 'سعرك');
  String get available => p('Available', 'المتوفر');
  String get lineValue => p('Value', 'القيمة');
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
  String get colSku => p('SKU', 'الرمز');
  String get colName => p('Name', 'الاسم');
  String get colGov => p('Governorate', 'المحافظة');
  String get colOfficial => p('Official price', 'السعر الرسمي');
  String get colYour => p('Your price', 'سعرك');
  String parsed(int n) => p('$n prices parsed', 'تم قراءة $n سعر');
  String applied(int agents) => p('Applied to $agents account(s)', 'تم التطبيق على $agents حساب');
  String get nothingParsed => p('No prices found in the file', 'لا توجد أسعار في الملف');
  String get cancel => p('Cancel', 'إلغاء');
  String get apply => p('Apply', 'تطبيق');
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
  Object? _error;
  bool _authorized = true;
  final Map<String, TextEditingController> _ctrls = {};

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
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await _repo.catalog();
      if (!mounted) return;
      for (final c in _ctrls.values) {
        c.dispose();
      }
      _ctrls.clear();
      for (final row in catalog.rows) {
        // Base (SKU-wide) field keyed "sku::"; one field per governorate keyed "sku::gov".
        _ctrls['${row.sku}::'] = TextEditingController(
          text: _fmt(row.effectivePrice),
        );
        for (final g in row.governorates) {
          _ctrls['${row.sku}::${g.governorate}'] = TextEditingController(
            text: _fmt(g.effectivePrice),
          );
        }
      }
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
          final baseVal = num.tryParse(_ctrls['${row.sku}::']?.text.trim() ?? '');
          if (baseVal != null &&
              (row.agentPrice == null || row.agentPrice != baseVal)) {
            await _repo.setPrice(entityId: '', sku: row.sku, price: baseVal);
          }
          continue;
        }
        // Regional: per-governorate prices ONLY (no standalone global price). The
        // untagged "" bucket, if any, is saved here too via its own governorate row.
        for (final g in row.governorates) {
          final value = num.tryParse(
            _ctrls['${row.sku}::${g.governorate}']?.text.trim() ?? '',
          );
          if (value == null) continue;
          if (g.agentPrice == null || g.agentPrice != value) {
            await _repo.setPrice(
              entityId: '',
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
  Future<void> _exportXlsx(_S s) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final rows = <List<String>>[];
    for (final row in catalog.rows) {
      if (_regionalRow(row)) {
        for (final g in row.governorates) {
          rows.add([
            row.sku,
            row.name,
            g.governorate,
            _fmt(g.officialPrice),
            _fmt(g.agentPrice ?? g.officialPrice),
          ]);
        }
      } else {
        rows.add([
          row.sku,
          row.name,
          '',
          _fmt(row.officialPrice),
          _fmt(row.agentPrice ?? row.officialPrice),
        ]);
      }
    }
    await exportRowsToXlsx(
      fileName: 'inteshar-prices',
      sheetName: 'Prices',
      headers: [s.colSku, s.colName, s.colGov, s.colOfficial, s.colYour],
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
          final gov = cell(2);
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
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.nothingParsed)));
      return;
    }

    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final myId = (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id ?? '';

    // Confirm with a PREVIEW of exactly what will change + an explicit target.
    final extraAgents = <String, String>{}; // id -> name
    var applyToSelf = true; // default: write MY own prices
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
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showEntitySearchPicker(
                      ctx,
                      repository: EntityRepository(ref.read(apiClientProvider)),
                      title: s.alsoAgents,
                      types: const [EntityType.AGENT1, EntityType.AGENT2],
                    );
                    if (picked != null) setD(() => extraAgents[picked.id] = picked.label);
                  },
                  icon: const Icon(Icons.group_add, size: 16),
                  label: Text(s.alsoAgents),
                ),
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
    final visibleRows =
        _unpricedOnly ? catalog.rows.where((r) => !r.priced).toList() : catalog.rows;
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
                          child: _PriceRow(row: row, ctrls: _ctrls, s: s),
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
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(s.save),
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
        color: IntesharColors.saffron,
        borderRadius: BorderRadius.circular(IntesharRadii.lg),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.balanceLabel,
                style: IntesharType.overline(
                  color: IntesharColors.ink.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Formatters.iqd(worth.round()),
                style: const TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: IntesharColors.ink,
                  height: 1,
                ),
              ),
            ],
          ),
          const Spacer(),
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
  final _S s;
  const _PriceRow({required this.row, required this.ctrls, required this.s});

  @override
  Widget build(BuildContext context) {
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
              Text(
                '${s.official}: ${Formatters.iqd(row.officialPrice.round())}',
                style: IntesharType.mono(11.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!regional)
            // Non-regional category: one price for all its (untagged) stock.
            _PriceField(
              label: s.yourPrice,
              ctrl: ctrls['${row.sku}::'],
              available: row.available,
              lineValue: row.lineValue,
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
                  label: label,
                  ctrl: ctrls['${row.sku}::${g.governorate}'],
                  available: g.available,
                  lineValue: g.lineValue,
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
  final String label;
  final TextEditingController? ctrl;
  final int available;
  final num lineValue;
  final _S s;
  const _PriceField({
    required this.label,
    required this.ctrl,
    required this.available,
    required this.lineValue,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 130,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: IntesharType.mono(14, color: cs.onSurface),
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${s.available}: ${Formatters.money(available)}',
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                '${s.lineValue}: ${Formatters.iqd(lineValue.round())}',
                style: IntesharType.mono(
                  12.5,
                  color: cs.onSurface,
                  w: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
