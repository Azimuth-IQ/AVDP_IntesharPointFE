import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ─── Sample voucher data used in the live preview ────────────────────────────
const _sampleSerial = 'SN-2024-0001-8842';
const _samplePin = '7041 8823 1907';
const _sampleCompany = 'Inteshar';

// ─── Main page ───────────────────────────────────────────────────────────────

class VoucherTemplatesPage extends ConsumerStatefulWidget {
  const VoucherTemplatesPage({super.key});

  @override
  ConsumerState<VoucherTemplatesPage> createState() =>
      _VoucherTemplatesPageState();
}

class _VoucherTemplatesPageState extends ConsumerState<VoucherTemplatesPage> {
  List<ProductDefinition>? _defs;
  Object? _error;
  bool _loading = true;

  ProductDefinition? _selected;
  VoucherTemplate _edited = const VoucherTemplate();
  bool _saving = false;

  // Text controllers for the editor fields
  late final TextEditingController _headerCtrl;
  late final TextEditingController _footerCtrl;
  late final TextEditingController _redeemCtrl;
  late final TextEditingController _prefixCtrl;
  late final TextEditingController _suffixCtrl;

  @override
  void initState() {
    super.initState();
    _headerCtrl = TextEditingController();
    _footerCtrl = TextEditingController();
    _redeemCtrl = TextEditingController();
    _prefixCtrl = TextEditingController();
    _suffixCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    _redeemCtrl.dispose();
    _prefixCtrl.dispose();
    _suffixCtrl.dispose();
    super.dispose();
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
      if (mounted) {
        setState(() {
          _defs = defs;
          if (_selected != null) {
            // Keep selection updated after refresh
            final refreshed = defs.where((d) => d.id == _selected!.id);
            if (refreshed.isNotEmpty) {
              _selectDef(refreshed.first);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectDef(ProductDefinition def) {
    setState(() {
      _selected = def;
      _edited = def.template;
      _headerCtrl.text = def.template.headerText;
      _footerCtrl.text = def.template.footerText;
      _redeemCtrl.text = def.template.redeemInstructions;
      _prefixCtrl.text = def.template.qrPrefix;
      _suffixCtrl.text = def.template.qrSuffix;
    });
  }

  void _onHeaderChanged(String v) =>
      setState(() => _edited = _edited.copyWith(headerText: v));

  void _onFooterChanged(String v) =>
      setState(() => _edited = _edited.copyWith(footerText: v));

  void _onRedeemChanged(String v) =>
      setState(() => _edited = _edited.copyWith(redeemInstructions: v));

  void _onPrefixChanged(String v) =>
      setState(() => _edited = _edited.copyWith(qrPrefix: v));

  void _onSuffixChanged(String v) =>
      setState(() => _edited = _edited.copyWith(qrSuffix: v));

  Future<void> _save() async {
    final def = _selected;
    if (def == null) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final repo = DefinitionRepository(api);
      final updated = await repo.update(def.copyWith(template: _edited));
      if (mounted) {
        setState(() {
          final idx = _defs!.indexWhere((d) => d.id == updated.id);
          if (idx >= 0) _defs![idx] = updated;
          _selected = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.vtSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.vtSaveFailed),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final defs = _defs ?? [];

    if (defs.isEmpty) {
      return Scaffold(
        body: MaxWidthBox(
          child: Column(
            children: [
              PageHeader(
                eyebrow: l.navTemplates,
                title: l.vtTitle,
                subtitle: l.vtSubtitle,
              ),
              Expanded(child: EmptyState(message: l.vtEmpty)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: MaxWidthBox(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  eyebrow: l.navTemplates,
                  title: l.vtTitle,
                  subtitle: l.vtSubtitle,
                ),
                Expanded(
                  child: isWide
                      ? _WideLayout(
                          defs: defs,
                          selected: _selected,
                          edited: _edited,
                          saving: _saving,
                          headerCtrl: _headerCtrl,
                          footerCtrl: _footerCtrl,
                          redeemCtrl: _redeemCtrl,
                          prefixCtrl: _prefixCtrl,
                          suffixCtrl: _suffixCtrl,
                          onSelect: _selectDef,
                          onHeaderChanged: _onHeaderChanged,
                          onFooterChanged: _onFooterChanged,
                          onRedeemChanged: _onRedeemChanged,
                          onPrefixChanged: _onPrefixChanged,
                          onSuffixChanged: _onSuffixChanged,
                          onToggle: (t) => setState(() => _edited = t),
                          onSave: _save,
                        )
                      : _NarrowLayout(
                          defs: defs,
                          selected: _selected,
                          edited: _edited,
                          saving: _saving,
                          headerCtrl: _headerCtrl,
                          footerCtrl: _footerCtrl,
                          redeemCtrl: _redeemCtrl,
                          prefixCtrl: _prefixCtrl,
                          suffixCtrl: _suffixCtrl,
                          onSelect: _selectDef,
                          onHeaderChanged: _onHeaderChanged,
                          onFooterChanged: _onFooterChanged,
                          onRedeemChanged: _onRedeemChanged,
                          onPrefixChanged: _onPrefixChanged,
                          onSuffixChanged: _onSuffixChanged,
                          onToggle: (t) => setState(() => _edited = t),
                          onSave: _save,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Shared props bundle ──────────────────────────────────────────────────────

typedef _TemplateToggleCb = void Function(VoucherTemplate);

// ─── Wide layout (≥900px) ────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final List<ProductDefinition> defs;
  final ProductDefinition? selected;
  final VoucherTemplate edited;
  final bool saving;
  final TextEditingController headerCtrl;
  final TextEditingController footerCtrl;
  final TextEditingController redeemCtrl;
  final TextEditingController prefixCtrl;
  final TextEditingController suffixCtrl;
  final ValueChanged<ProductDefinition> onSelect;
  final ValueChanged<String> onHeaderChanged;
  final ValueChanged<String> onFooterChanged;
  final ValueChanged<String> onRedeemChanged;
  final ValueChanged<String> onPrefixChanged;
  final ValueChanged<String> onSuffixChanged;
  final _TemplateToggleCb onToggle;
  final VoidCallback onSave;

  const _WideLayout({
    required this.defs,
    required this.selected,
    required this.edited,
    required this.saving,
    required this.headerCtrl,
    required this.footerCtrl,
    required this.redeemCtrl,
    required this.prefixCtrl,
    required this.suffixCtrl,
    required this.onSelect,
    required this.onHeaderChanged,
    required this.onFooterChanged,
    required this.onRedeemChanged,
    required this.onPrefixChanged,
    required this.onSuffixChanged,
    required this.onToggle,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SKU list column
        SizedBox(
          width: 260,
          child: _SkuList(
            defs: defs,
            selected: selected,
            onSelect: onSelect,
          ),
        ),
        const VerticalDivider(width: 1),
        // Editor + preview column
        Expanded(
          child: selected == null
              ? _SelectPrompt()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Editor
                    Expanded(
                      flex: 5,
                      child: _TemplateEditor(
                        def: selected!,
                        edited: edited,
                        saving: saving,
                        headerCtrl: headerCtrl,
                        footerCtrl: footerCtrl,
                        redeemCtrl: redeemCtrl,
                        prefixCtrl: prefixCtrl,
                        suffixCtrl: suffixCtrl,
                        onHeaderChanged: onHeaderChanged,
                        onFooterChanged: onFooterChanged,
                        onRedeemChanged: onRedeemChanged,
                        onPrefixChanged: onPrefixChanged,
                        onSuffixChanged: onSuffixChanged,
                        onToggle: onToggle,
                        onSave: onSave,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    // Preview
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            24, 24, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionLabel(
                                AppLocalizations.of(context)!.vtPreview),
                            const SizedBox(height: 16),
                            Center(
                              child: _ReceiptPreview(
                                def: selected!,
                                template: edited,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

// ─── Narrow layout (<900px) ──────────────────────────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final List<ProductDefinition> defs;
  final ProductDefinition? selected;
  final VoucherTemplate edited;
  final bool saving;
  final TextEditingController headerCtrl;
  final TextEditingController footerCtrl;
  final TextEditingController redeemCtrl;
  final TextEditingController prefixCtrl;
  final TextEditingController suffixCtrl;
  final ValueChanged<ProductDefinition> onSelect;
  final ValueChanged<String> onHeaderChanged;
  final ValueChanged<String> onFooterChanged;
  final ValueChanged<String> onRedeemChanged;
  final ValueChanged<String> onPrefixChanged;
  final ValueChanged<String> onSuffixChanged;
  final _TemplateToggleCb onToggle;
  final VoidCallback onSave;

  const _NarrowLayout({
    required this.defs,
    required this.selected,
    required this.edited,
    required this.saving,
    required this.headerCtrl,
    required this.footerCtrl,
    required this.redeemCtrl,
    required this.prefixCtrl,
    required this.suffixCtrl,
    required this.onSelect,
    required this.onHeaderChanged,
    required this.onFooterChanged,
    required this.onRedeemChanged,
    required this.onPrefixChanged,
    required this.onSuffixChanged,
    required this.onToggle,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
      children: [
        // Product picker dropdown
        _SkuDropdown(defs: defs, selected: selected, onSelect: onSelect),
        const SizedBox(height: 16),
        if (selected != null) ...[
          _TemplateEditor(
            def: selected!,
            edited: edited,
            saving: saving,
            headerCtrl: headerCtrl,
            footerCtrl: footerCtrl,
            redeemCtrl: redeemCtrl,
            prefixCtrl: prefixCtrl,
            suffixCtrl: suffixCtrl,
            onHeaderChanged: onHeaderChanged,
            onFooterChanged: onFooterChanged,
            onRedeemChanged: onRedeemChanged,
            onPrefixChanged: onPrefixChanged,
            onSuffixChanged: onSuffixChanged,
            onToggle: onToggle,
            onSave: onSave,
            inScrollable: true,
          ),
          const SizedBox(height: 24),
          SectionLabel(l.vtPreview),
          const SizedBox(height: 16),
          Center(
            child: _ReceiptPreview(def: selected!, template: edited),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: _SelectPrompt(),
          ),
      ],
    );
  }
}

// ─── SKU list (wide sidebar) ─────────────────────────────────────────────────

class _SkuList extends StatelessWidget {
  final List<ProductDefinition> defs;
  final ProductDefinition? selected;
  final ValueChanged<ProductDefinition> onSelect;

  const _SkuList({
    required this.defs,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 24),
      itemCount: defs.length,
      itemBuilder: (context, i) {
        final def = defs[i];
        final isSelected = selected?.id == def.id;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Material(
            color: isSelected
                ? IntesharColors.saffron.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(IntesharRadii.md),
            child: InkWell(
              onTap: () => onSelect(def),
              borderRadius: BorderRadius.circular(IntesharRadii.md),
              splashColor: IntesharColors.saffron.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? IntesharColors.saffron
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(IntesharRadii.sm),
                      ),
                      child: Center(
                        child: Text(
                          def.sku,
                          style: IntesharType.mono(10, color: IntesharColors.ink, w: FontWeight.w900, letterSpacing: 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            def.name,
                            style: TextStyle(
                              fontFamily: 'CodecPro',
                              fontSize: 13.5,
                              color: cs.onSurface,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              height: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Formatters.iqd(def.defaultPrice),
                            style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.2),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.edit_outlined,
                          size: 14, color: IntesharColors.saffronDeep),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── SKU dropdown (narrow) ───────────────────────────────────────────────────

class _SkuDropdown extends StatelessWidget {
  final List<ProductDefinition> defs;
  final ProductDefinition? selected;
  final ValueChanged<ProductDefinition> onSelect;

  const _SkuDropdown({
    required this.defs,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return InkCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ProductDefinition>(
          value: selected,
          hint: Text(l.vtSelectPrompt,
              style: Theme.of(context).textTheme.bodyMedium),
          isExpanded: true,
          items: defs
              .map(
                (d) => DropdownMenuItem(
                  value: d,
                  child: Row(
                    children: [
                      Text(
                        d.sku,
                        style: IntesharType.mono(12, color: IntesharColors.saffronDeep, w: FontWeight.w700),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(d.name,
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (d) {
            if (d != null) onSelect(d);
          },
        ),
      ),
    );
  }
}

// ─── Select prompt placeholder ────────────────────────────────────────────────

class _SelectPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 52, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            l.vtSelectPrompt,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Template editor ─────────────────────────────────────────────────────────

class _TemplateEditor extends StatelessWidget {
  final ProductDefinition def;
  final VoucherTemplate edited;
  final bool saving;
  final TextEditingController headerCtrl;
  final TextEditingController footerCtrl;
  final TextEditingController redeemCtrl;
  final TextEditingController prefixCtrl;
  final TextEditingController suffixCtrl;
  final ValueChanged<String> onHeaderChanged;
  final ValueChanged<String> onFooterChanged;
  final ValueChanged<String> onRedeemChanged;
  final ValueChanged<String> onPrefixChanged;
  final ValueChanged<String> onSuffixChanged;
  final _TemplateToggleCb onToggle;
  final VoidCallback onSave;
  final bool inScrollable;

  const _TemplateEditor({
    required this.def,
    required this.edited,
    required this.saving,
    required this.headerCtrl,
    required this.footerCtrl,
    required this.redeemCtrl,
    required this.prefixCtrl,
    required this.suffixCtrl,
    required this.onHeaderChanged,
    required this.onFooterChanged,
    required this.onRedeemChanged,
    required this.onPrefixChanged,
    required this.onSuffixChanged,
    required this.onToggle,
    required this.onSave,
    this.inScrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // SKU badge
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: IntesharColors.saffron,
                  borderRadius: BorderRadius.circular(IntesharRadii.xs),
                ),
                child: Text(
                  def.sku,
                  style: IntesharType.mono(12, color: IntesharColors.ink, w: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  def.name,
                  style: IntesharType.sans(16,
                      color: cs.onSurface, w: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // ── Header text ──────────────────────────────────────────────────
        SectionLabel(l.vtHeaderText),
        TextField(
          controller: headerCtrl,
          maxLines: 2,
          onChanged: onHeaderChanged,
          decoration: InputDecoration(
            hintText: _sampleCompany,
            labelText: l.vtHeaderText,
          ),
        ),
        const SizedBox(height: 20),

        // ── Fields section ───────────────────────────────────────────────
        SectionLabel(l.vtFields),
        InkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _BrandSwitch(
                label: l.vtShowProductName,
                value: edited.showProductName,
                onChanged: (v) =>
                    onToggle(edited.copyWith(showProductName: v)),
              ),
              Divider(height: 1, color: cs.outline),
              _BrandSwitch(
                label: l.vtShowSerial,
                value: edited.showSerial,
                onChanged: (v) => onToggle(edited.copyWith(showSerial: v)),
              ),
              Divider(height: 1, color: cs.outline),
              _BrandSwitch(
                label: l.vtShowPin,
                value: edited.showPin,
                onChanged: (v) => onToggle(edited.copyWith(showPin: v)),
              ),
              Divider(height: 1, color: cs.outline),
              _BrandSwitch(
                label: l.vtShowPrice,
                value: edited.showPrice,
                onChanged: (v) => onToggle(edited.copyWith(showPrice: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── QR section ───────────────────────────────────────────────────
        SectionLabel(l.vtQrSection),
        InkCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BrandSwitch(
                label: l.vtQrEnabled,
                value: edited.qrEnabled,
                onChanged: (v) => onToggle(edited.copyWith(qrEnabled: v)),
              ),
              if (edited.qrEnabled) ...[
                Divider(height: 1, color: cs.outline),
                // QR source segmented button
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.vtQrSource,
                        style: TextStyle(
                          fontFamily: 'CodecPro',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: WidgetStatePropertyAll(
                            Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        segments: [
                          ButtonSegment(
                              value: 'PIN', label: Text(l.vtQrSourcePin)),
                          ButtonSegment(
                              value: 'SERIAL',
                              label: Text(l.vtQrSourceSerial)),
                        ],
                        selected: {edited.qrSource},
                        onSelectionChanged: (sel) =>
                            onToggle(edited.copyWith(qrSource: sel.first)),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outline),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: prefixCtrl,
                          onChanged: onPrefixChanged,
                          decoration: InputDecoration(
                            labelText: l.vtQrPrefix,
                            hintText: '*133*',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: suffixCtrl,
                          onChanged: onSuffixChanged,
                          decoration: InputDecoration(
                            labelText: l.vtQrSuffix,
                            hintText: '#',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outline),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${l.vtQrExample}: ',
                        style: TextStyle(
                          fontFamily: 'CodecPro',
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          edited.qrPayload(
                              pin: _samplePin, serial: _sampleSerial),
                          style: IntesharType.mono(12, color: IntesharColors.saffronDeep, w: FontWeight.w600, letterSpacing: 0.4),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Redeem instructions ──────────────────────────────────────────
        SectionLabel(l.vtRedeemInstructions),
        TextField(
          controller: redeemCtrl,
          maxLines: 2,
          onChanged: onRedeemChanged,
          decoration: InputDecoration(
            labelText: l.vtRedeemInstructions,
            hintText: 'Dial *133*PIN# to recharge',
          ),
        ),
        const SizedBox(height: 20),

        // ── Footer text ──────────────────────────────────────────────────
        SectionLabel(l.vtFooterText),
        TextField(
          controller: footerCtrl,
          maxLines: 2,
          onChanged: onFooterChanged,
          decoration: InputDecoration(
            labelText: l.vtFooterText,
            hintText: 'Inteshar Platform · www.inteshar.iq',
          ),
        ),
        const SizedBox(height: 24),

        // ── Save button ──────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: IntesharColors.ink,
                    ),
                  )
                : Text(l.vtSave),
          ),
        ),
      ],
    );

    if (inScrollable) return content;

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 32),
      child: content,
    );
  }
}

// ─── Gold-accented switch row ─────────────────────────────────────────────────

class _BrandSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BrandSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
      title: Text(
        label,
        style: TextStyle(
          fontFamily: 'CodecPro',
          fontSize: 14,
          color: cs.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      value: value,
      activeThumbColor: IntesharColors.saffron,
      onChanged: onChanged,
    );
  }
}

// ─── 58mm thermal receipt preview ────────────────────────────────────────────

class _ReceiptPreview extends StatelessWidget {
  final ProductDefinition def;
  final VoucherTemplate template;

  const _ReceiptPreview({required this.def, required this.template});

  @override
  Widget build(BuildContext context) {
    final now = DateFormat('yyyy-MM-dd  HH:mm').format(DateTime.now());
    final qrPayload =
        template.qrPayload(pin: _samplePin, serial: _sampleSerial);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        boxShadow: IntesharShadows.elev2,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Header ──────────────────────────────────────────────────
            if (template.headerText.isNotEmpty) ...[
              Text(
                template.headerText,
                textAlign: TextAlign.center,
                style: IntesharType.mono(13, color: Colors.black, w: FontWeight.w700, letterSpacing: 0.4),
              ),
              const SizedBox(height: 8),
            ] else ...[
              Text(
                _sampleCompany,
                textAlign: TextAlign.center,
                style: IntesharType.mono(13, color: Colors.black54, w: FontWeight.w700, letterSpacing: 0.4),
              ),
              const SizedBox(height: 8),
            ],

            // ── Product name ─────────────────────────────────────────────
            if (template.showProductName) ...[
              Text(
                def.name,
                textAlign: TextAlign.center,
                style: IntesharType.mono(12, color: Colors.black87),
              ),
              const SizedBox(height: 4),
            ],

            // ── Price ────────────────────────────────────────────────────
            if (template.showPrice) ...[
              Text(
                Formatters.iqd(def.defaultPrice),
                textAlign: TextAlign.center,
                style: IntesharType.mono(12, color: Colors.black87, w: FontWeight.w600),
              ),
              const SizedBox(height: 4),
            ],

            _DashedDivider(),
            const SizedBox(height: 8),

            // ── Serial ───────────────────────────────────────────────────
            if (template.showSerial) ...[
              _ReceiptRow(label: 'SN', value: _sampleSerial),
              const SizedBox(height: 6),
            ],

            // ── PIN (larger, bold) ───────────────────────────────────────
            if (template.showPin) ...[
              const SizedBox(height: 4),
              Text(
                _samplePin,
                textAlign: TextAlign.center,
                style: IntesharType.mono(20, color: Colors.black, w: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 8),
            ],

            // ── QR code ──────────────────────────────────────────────────
            if (template.qrEnabled && qrPayload.isNotEmpty) ...[
              _DashedDivider(),
              const SizedBox(height: 10),
              QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 120,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 6),
              Text(
                qrPayload,
                textAlign: TextAlign.center,
                style: IntesharType.mono(10, color: Colors.black54, letterSpacing: 0.3),
              ),
              const SizedBox(height: 8),
            ],

            // ── Redeem instructions ──────────────────────────────────────
            if (template.redeemInstructions.isNotEmpty) ...[
              _DashedDivider(),
              const SizedBox(height: 8),
              Text(
                template.redeemInstructions,
                textAlign: TextAlign.center,
                style: IntesharType.mono(10, color: Colors.black87).copyWith(height: 1.5),
              ),
              const SizedBox(height: 8),
            ],

            // ── Footer ───────────────────────────────────────────────────
            if (template.footerText.isNotEmpty) ...[
              _DashedDivider(),
              const SizedBox(height: 8),
              Text(
                template.footerText,
                textAlign: TextAlign.center,
                style: IntesharType.mono(9, color: Colors.black54).copyWith(height: 1.5),
              ),
              const SizedBox(height: 4),
            ],

            // ── Timestamp ────────────────────────────────────────────────
            _DashedDivider(),
            const SizedBox(height: 6),
            Text(
              now,
              textAlign: TextAlign.center,
              style: IntesharType.mono(9, color: Colors.black38, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CustomPaint(
        painter: _DashedLinePainter(),
        size: const Size(double.infinity, 1),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 4.0;
    const dashSpace = 3.0;
    final paint = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + dashWidth, 0),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => false;
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: IntesharType.mono(10, color: Colors.black54, w: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            value,
            style: IntesharType.mono(10, color: Colors.black87, letterSpacing: 0.3),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
