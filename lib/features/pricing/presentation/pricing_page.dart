import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/utils/formatters.dart';
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
  final Map<String, TextEditingController> _ctrls = {};

  PricingRepository get _repo => PricingRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _load();
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
        _ctrls[row.sku] = TextEditingController(text: _fmt(row.effectivePrice));
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
        final raw = _ctrls[row.sku]?.text.trim() ?? '';
        final value = num.tryParse(raw);
        if (value == null) continue;
        final current = row.agentPrice;
        if (current == null || current != value) {
          await _repo.setPrice(entityId: '', sku: row.sku, price: value);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.saved)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
                      child: _PriceRow(row: row, ctrl: _ctrls[row.sku]!, s: s),
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
  final TextEditingController ctrl;
  final _S s;
  const _PriceRow({required this.row, required this.ctrl, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  style: IntesharType.mono(14, color: cs.onSurface),
                  decoration: InputDecoration(labelText: s.yourPrice, isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${s.available}: ${row.available}',
                        style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text('${s.lineValue}: ${Formatters.iqd(row.lineValue.round())}',
                        style: IntesharType.mono(12.5, color: cs.onSurface, w: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
