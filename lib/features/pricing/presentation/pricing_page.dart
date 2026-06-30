import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/pricing/data/pricing_repository.dart';
import 'package:inteshar/features/pricing/domain/pricing_models.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) => _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('Pricing', 'التسعير');
  String get title => p('Prices', 'الأسعار');
  String get subtitle => p('Set your selling price per category', 'حدّد سعر بيعك لكل فئة');
  String get balanceLabel => p('Inventory worth', 'قيمة المخزون');
  String unpriced(int n) => p('$n unpriced', '$n بدون سعر');
  String get official => p('Official', 'الرسمي');
  String get yourPrice => p('Your price', 'سعرك');
  String get available => p('Available', 'المتوفر');
  String get lineValue => p('Value', 'القيمة');
  String get save => p('Save prices', 'حفظ الأسعار');
  String get saved => p('Prices saved', 'تم حفظ الأسعار');
  String get uncategorized => p('Uncategorized', 'بدون شركة');
  String get empty => p('No categories in the catalog yet.', 'لا توجد فئات في الكتالوج بعد.');
  String get byGovernorate => p('By governorate', 'حسب المحافظة');
  String get untagged => p('No region', 'بدون محافظة');
  String get allRegions => p('All regions', 'كل المحافظات');
  String get unauthorized => p('Pricing access not granted', 'لا تملك صلاحية إدارة الأسعار');
}

class PricingPage extends ConsumerStatefulWidget {
  const PricingPage({super.key});

  @override
  ConsumerState<PricingPage> createState() => _PricingPageState();
}

class _PricingPageState extends ConsumerState<PricingPage> {
  PricingCatalog? _catalog;
  bool _loading = true;
  bool _saving = false;
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
    _authorized = auth is AuthAuthenticated && auth.can({Capability.MANAGE_PRICING});
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
        _ctrls['${row.sku}::'] = TextEditingController(text: _fmt(row.effectivePrice));
        for (final g in row.governorates) {
          _ctrls['${row.sku}::${g.governorate}'] = TextEditingController(text: _fmt(g.effectivePrice));
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
        // SKU-wide base price.
        final baseVal = num.tryParse(_ctrls['${row.sku}::']?.text.trim() ?? '');
        if (baseVal != null && (row.agentPrice == null || row.agentPrice != baseVal)) {
          await _repo.setPrice(entityId: '', sku: row.sku, price: baseVal);
        }
        // Per-governorate (subcategory) overrides.
        for (final g in row.governorates) {
          final value = num.tryParse(_ctrls['${row.sku}::${g.governorate}']?.text.trim() ?? '');
          if (value == null) continue;
          if (g.agentPrice == null || g.agentPrice != value) {
            await _repo.setPrice(entityId: '', sku: row.sku, governorate: g.governorate, price: value);
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.saved)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
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
          PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle),
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
      return Center(child: Text(s.empty, style: IntesharType.sans(14, color: cs.onSurfaceVariant)));
    }

    // Group rows by company, preserving the server's (company, name) order.
    final groups = <String, List<CategoryPriceRow>>{};
    for (final row in catalog.rows) {
      final key = row.companyName.isNotEmpty ? row.companyName : s.uncategorized;
      groups.putIfAbsent(key, () => []).add(row);
    }

    return Column(
      children: [
        _BalanceHeader(s: s, worth: catalog.inventoryWorth, unpriced: catalog.unpricedCount),
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
            children: [
              for (final entry in groups.entries) ...[
                SectionLabel(entry.key),
                ...entry.value.map((row) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _PriceRow(row: row, ctrls: _ctrls, s: s),
                    )),
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
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
  const _BalanceHeader({required this.s, required this.worth, required this.unpriced});

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
              Text(s.balanceLabel,
                  style: IntesharType.overline(color: IntesharColors.ink.withValues(alpha: 0.7))),
              const SizedBox(height: 2),
              Text(Formatters.iqd(worth.round()),
                  style: const TextStyle(
                      fontFamily: 'CodecPro', fontSize: 26, fontWeight: FontWeight.w900, color: IntesharColors.ink, height: 1)),
            ],
          ),
          const Spacer(),
          if (unpriced > 0)
            StampPill(label: s.unpriced(unpriced), color: cs.error),
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

  /// Whether to show the per-governorate subcategory fields (more than just an
  /// untagged bucket).
  bool get _hasGovBreakdown =>
      row.governorates.length > 1 ||
      (row.governorates.length == 1 && row.governorates.first.governorate.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    return InkCard(
      padding: const EdgeInsets.all(14),
      ruleColor: row.priced ? IntesharColors.sage : cs.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.name, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700)),
              ),
              Text('${s.official}: ${Formatters.iqd(row.officialPrice.round())}',
                  style: IntesharType.mono(11.5, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          // SKU-wide base price ("" governorate) — the fallback for any region without its own.
          _PriceField(
            label: _hasGovBreakdown ? s.allRegions : s.yourPrice,
            ctrl: ctrls['${row.sku}::'],
            available: row.available,
            lineValue: row.lineValue,
            s: s,
          ),
          if (_hasGovBreakdown) ...[
            const SizedBox(height: 12),
            Text(s.byGovernorate, style: IntesharType.overline(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            ...row.governorates.map((g) {
              final label = g.governorate.isEmpty ? s.untagged : governorateLabel(g.governorate, loc);
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
            style: IntesharType.mono(14, color: cs.onSurface),
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${s.available}: $available',
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text('${s.lineValue}: ${Formatters.iqd(lineValue.round())}',
                  style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}
