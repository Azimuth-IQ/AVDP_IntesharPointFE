import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/companies/data/company_repository.dart';
import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/template_inheritance.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
import 'package:inteshar/shared/widgets/confirm_dialog.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/loading_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ─── Sample voucher data used in the live preview ────────────────────────────
const _sampleSerial = 'SN-2024-0001-8842';
const _samplePin = '7041 8823 1907';
const _sampleCompany = 'Inteshar';
// Sample telecom company name used to preview the COMPANY NAME receipt line.
const _sampleCompanyName = 'Asiacell';

// ─── Main page ───────────────────────────────────────────────────────────────

class VoucherTemplatesPage extends ConsumerStatefulWidget {
  const VoucherTemplatesPage({super.key});

  @override
  ConsumerState<VoucherTemplatesPage> createState() =>
      _VoucherTemplatesPageState();
}

class _VoucherTemplatesPageState extends ConsumerState<VoucherTemplatesPage> {
  List<ProductDefinition>? _defs;
  // PROD-023: companies carry the template their categories follow.
  List<Company> _companies = const [];
  Object? _error;
  bool _loading = true;

  ProductDefinition? _selected;

  /// PROD-023: set while a COMPANY's template is being edited (then [_selected] is null).
  Company? _selectedCompany;
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
      // Companies are best-effort: without them the page still edits every
      // category on its own, as it did before PROD-023.
      final companiesF = CompanyRepository(api).readAll().catchError((_) => <Company>[]);
      final defs = await DefinitionRepository(api).readAll();
      final companies = await companiesF;
      if (mounted) {
        // Keep the selection updated after a refresh — but NOT while the operator
        // has unsaved edits, or a background refresh would silently discard them (B-072).
        final keep = !_dirty;
        setState(() {
          _defs = defs;
          _companies = companies;
          if (keep && _selectedCompany != null) {
            final c = companies.where((c) => c.id == _selectedCompany!.id);
            if (c.isNotEmpty) _applyCompany(c.first);
          } else if (keep && _selected != null) {
            final refreshed = defs.where((d) => d.id == _selected!.id);
            if (refreshed.isNotEmpty) _applyDef(refreshed.first);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The saved template the editor compares against; null when nothing on screen is
  /// editable (a category that follows its company shows the company's, read-only).
  VoucherTemplate? get _savedTemplate {
    final c = _selectedCompany;
    if (c != null) return c.voucherTemplate ?? const VoucherTemplate();
    final d = _selected;
    if (d == null || followsCompany(d, companyOf(d, _companies))) return null;
    return d.template;
  }

  /// Unsaved edits: the in-progress template differs from the saved one.
  bool get _dirty {
    final saved = _savedTemplate;
    return saved != null && !mapEquals(_edited.toJson(), saved.toJson());
  }

  /// UX-78: set for the single frame in which an answered discard prompt lets
  /// the route pop, so [PopScope] does not veto its own retry forever. Same
  /// idiom as the pricing grid's dirty guard.
  bool _allowPop = false;

  /// UX-78: the ONE unsaved-edits prompt, shared by every exit that throws the
  /// edits away — switching SKU or company (which reloads every controller) and
  /// leaving the route.
  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final l = AppLocalizations.of(context)!;
    // Destructive: "Discard" throws away edits with no undo. The shared
    // confirm carries that signal; the plain gold FilledButton did not.
    return showConfirm(
      context,
      title: l.vtUnsavedTitle,
      body: l.vtUnsavedBody,
      confirmLabel: l.vtDiscard,
      cancelLabel: l.vtKeepEditing,
      destructive: true,
    );
  }

  /// Switch to a category, guarding unsaved edits with a discard/keep prompt (B-072).
  Future<void> _trySelect(ProductDefinition def) async {
    if (_selectedCompany == null && _selected?.id == def.id) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _applyDef(def));
  }

  /// PROD-023: switch to a company's template, with the same guard.
  Future<void> _trySelectCompany(Company c) async {
    if (_selectedCompany?.id == c.id) return;
    if (!await _confirmDiscard() || !mounted) return;
    setState(() => _applyCompany(c));
  }

  /// Narrow layout: the dropdown's value is `co:<id>` or `def:<id>`.
  void _onPick(String key) {
    if (key.startsWith('co:')) {
      final id = key.substring(3);
      final c = _companies.where((c) => c.id == id);
      if (c.isNotEmpty) _trySelectCompany(c.first);
    } else if (key.startsWith('def:')) {
      final id = key.substring(4);
      final d = (_defs ?? const <ProductDefinition>[]).where((d) => d.id == id);
      if (d.isNotEmpty) _trySelect(d.first);
    }
  }

  String? get _pickKey => _selectedCompany != null
      ? 'co:${_selectedCompany!.id}'
      : (_selected != null ? 'def:${_selected!.id}' : null);

  // The _apply* helpers only mutate; callers wrap them in setState.
  void _applyDef(ProductDefinition def) {
    _selectedCompany = null;
    _selected = def;
    // A following category shows its company's template — what its paper prints.
    _loadEditor(effectiveTemplate(def, companyOf(def, _companies)));
  }

  void _applyCompany(Company c) {
    _selected = null;
    _selectedCompany = c;
    _loadEditor(c.voucherTemplate ?? const VoucherTemplate());
  }

  void _loadEditor(VoucherTemplate t) {
    _edited = t;
    _headerCtrl.text = t.headerText;
    _footerCtrl.text = t.footerText;
    _redeemCtrl.text = t.redeemInstructions;
    _prefixCtrl.text = t.qrPrefix;
    _suffixCtrl.text = t.qrSuffix;
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

  void _putDef(ProductDefinition d) {
    final i = _defs!.indexWhere((x) => x.id == d.id);
    if (i >= 0) _defs![i] = d;
  }

  void _putCompany(Company c) {
    final list = [..._companies];
    final i = list.indexWhere((x) => x.id == c.id);
    if (i >= 0) list[i] = c;
    _companies = list;
  }

  /// One template write, with the spinner and the saved / failed message.
  Future<void> _write(Future<void> Function(ApiClient api) body) async {
    setState(() => _saving = true);
    try {
      await body(ref.read(apiClientProvider));
      if (mounted) {
        setState(() {});
        showOk(context, AppLocalizations.of(context)!.vtSaved);
      }
    } catch (e) {
      if (mounted) showError(context, AppLocalizations.of(context)!.vtSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final company = _selectedCompany;
    final def = _selected;
    if (company == null && def == null) return;
    final t = _edited;
    await _write((api) async {
      if (company != null) {
        final updated = await CompanyRepository(api).setTemplate(company.id, t);
        _putCompany(updated);
        _selectedCompany = updated;
      } else {
        final updated = await DefinitionRepository(api).setTemplate(def!.id, template: t);
        _putDef(updated);
        _selected = updated;
      }
    });
  }

  /// PROD-023: a following category takes its own template — a copy of the
  /// company's, so nothing on paper changes until HQ edits it.
  Future<void> _customise() async {
    final def = _selected;
    if (def == null) return;
    final from = effectiveTemplate(def, companyOf(def, _companies));
    await _write((api) async {
      final updated = await DefinitionRepository(api).setTemplate(def.id, followsCompany: false, template: from);
      _putDef(updated);
      _applyDef(updated);
    });
  }

  Future<void> _backToCompany() async {
    final def = _selected;
    final company = def == null ? null : companyOf(def, _companies);
    if (def == null || company == null) return;
    final l = AppLocalizations.of(context)!;
    final ok = await showConfirm(
      context,
      title: l.vtBackToCompany,
      body: l.vtBackToCompanyBody(company.name),
      confirmLabel: l.vtConfirmChange,
      cancelLabel: l.defsCancel,
      icon: Icons.link,
    );
    if (!ok || !mounted) return;
    await _write((api) async {
      final updated = await DefinitionRepository(api).setTemplate(def.id, followsCompany: true);
      _putDef(updated);
      _applyDef(updated);
    });
  }

  /// PROD-023: what is on screen becomes the company's template, and this
  /// category follows it from now on.
  Future<void> _makeCompanyTemplate() async {
    final def = _selected;
    final company = def == null ? null : companyOf(def, _companies);
    if (def == null || company == null) return;
    final l = AppLocalizations.of(context)!;
    final followers = (_defs ?? const <ProductDefinition>[])
        .where((d) => d.id != def.id && followsCompany(d, company))
        .length;
    final ok = await showConfirm(
      context,
      title: l.vtMakeCompany,
      body: l.vtMakeCompanyBody(company.name, followers + 1),
      confirmLabel: l.vtConfirmChange,
      cancelLabel: l.defsCancel,
      icon: Icons.apartment_outlined,
    );
    if (!ok || !mounted) return;
    final t = _edited;
    await _write((api) async {
      _putCompany(await CompanyRepository(api).setTemplate(company.id, t));
      final updated = await DefinitionRepository(api).setTemplate(def.id, followsCompany: true);
      _putDef(updated);
      _applyDef(updated);
    });
  }

  /// Companies in catalog order, each with its categories; then the
  /// categories with no (known) company.
  List<_Group> _groups(List<ProductDefinition> defs) {
    final sorted = [..._companies]
      ..sort((a, b) => a.displayOrder != b.displayOrder
          ? a.displayOrder.compareTo(b.displayOrder)
          : a.name.compareTo(b.name));
    final out = <_Group>[];
    final placed = <String>{};
    for (final c in sorted) {
      final mine = defs.where((d) => d.companyId == c.id).toList();
      out.add(_Group(c, mine));
      placed.addAll(mine.map((d) => d.id));
    }
    final rest = defs.where((d) => !placed.contains(d.id)).toList();
    if (rest.isNotEmpty) out.add(_Group(null, rest));
    return out;
  }

  _TemplateEditor _editor({required String code, required String title, bool monoCode = true, Widget? notice}) =>
      _TemplateEditor(
        code: code,
        title: title,
        monoCode: monoCode,
        notice: notice,
        edited: _edited,
        saving: _saving,
        headerCtrl: _headerCtrl,
        footerCtrl: _footerCtrl,
        redeemCtrl: _redeemCtrl,
        prefixCtrl: _prefixCtrl,
        suffixCtrl: _suffixCtrl,
        onHeaderChanged: _onHeaderChanged,
        onFooterChanged: _onFooterChanged,
        onRedeemChanged: _onRedeemChanged,
        onPrefixChanged: _onPrefixChanged,
        onSuffixChanged: _onSuffixChanged,
        onToggle: (t) => setState(() => _edited = t),
        onSave: _save,
        dirty: _dirty,
        inScrollable: true,
      );

  /// The editing column for the current selection; null when nothing is selected.
  Widget? _editorPane(AppLocalizations l) {
    final company = _selectedCompany;
    if (company != null) {
      final mine = (_defs ?? const <ProductDefinition>[]).where((d) => d.companyId == company.id).toList();
      final follow = mine.where((d) => followsCompany(d, company)).length;
      return _editor(
        code: l.vtCompanyTemplate,
        title: company.name,
        monoCode: false,
        notice: _InheritanceNote(
          icon: Icons.apartment_outlined,
          text: l.vtCompanyScope(follow, mine.length - follow),
        ),
      );
    }
    final def = _selected;
    if (def == null) return null;
    final co = companyOf(def, _companies);
    if (followsCompany(def, co)) {
      return _FollowingPanel(
        def: def,
        companyName: co!.name,
        busy: _saving,
        onCustomise: _customise,
        onEditCompany: () => _trySelectCompany(co),
      );
    }
    return _editor(
      code: def.sku,
      title: def.name,
      notice: co != null
          ? _InheritanceNote(
              icon: Icons.tune,
              text: l.vtOwnBanner(co.name),
              actions: [
                TextButton.icon(
                  onPressed: _saving ? null : _backToCompany,
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(l.vtBackToCompany),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _makeCompanyTemplate,
                  icon: const Icon(Icons.apartment_outlined, size: 16),
                  label: Text(l.vtMakeCompany),
                ),
              ],
            )
          : _InheritanceNote(icon: Icons.info_outline, text: l.vtNoCompanyNote),
    );
  }

  /// The paper preview of what the current selection prints.
  Widget? _previewPane() {
    final company = _selectedCompany;
    if (company != null) {
      final sample = (_defs ?? const <ProductDefinition>[]).where((d) => d.companyId == company.id);
      return _ReceiptPreview(
        def: sample.isNotEmpty
            ? sample.first
            : ProductDefinition(id: '', name: company.name, defaultPrice: '10000', sku: ''),
        template: _edited,
        companyName: company.name,
      );
    }
    final def = _selected;
    if (def == null) return null;
    return _ReceiptPreview(def: def, template: _edited, companyName: companyOf(def, _companies)?.name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading) {
      return LoadingState(
        message: Localizations.localeOf(context).languageCode == 'ar'
            ? 'جارٍ تحميل القوالب…'
            : 'Loading templates…',
      );
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final defs = _defs ?? [];

    if (defs.isEmpty && _companies.isEmpty) {
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

    final groups = _groups(defs);
    final editor = _editorPane(l);
    final preview = _previewPane();

    // UX-78: leaving via the nav rail threw away every edit with no prompt —
    // the same loss the SKU switch already guards against.
    return PopScope<Object?>(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Resolved before the await so the prompt's async gap cannot leave us
        // reaching into a defunct element for it.
        final nav = Navigator.of(context);
        if (!await _confirmDiscard() || !mounted) return;
        setState(() => _allowPop = true);
        await nav.maybePop();
        if (mounted) setState(() => _allowPop = false);
      },
      child: Scaffold(
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
                          list: _TemplateList(
                            groups: groups,
                            selectedDefId: _selectedCompany == null ? _selected?.id : null,
                            selectedCompanyId: _selectedCompany?.id,
                            onSelectDef: _trySelect,
                            onSelectCompany: _trySelectCompany,
                          ),
                          editor: editor,
                          preview: preview,
                        )
                      : _NarrowLayout(
                          picker: _TargetDropdown(groups: groups, value: _pickKey, onPick: _onPick),
                          editor: editor,
                          preview: preview,
                        ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}

// ─── Shared props bundle ──────────────────────────────────────────────────────

typedef _TemplateToggleCb = void Function(VoucherTemplate);

/// PROD-023: one company and its categories (company null = "No company").
class _Group {
  final Company? company;
  final List<ProductDefinition> defs;
  const _Group(this.company, this.defs);
}

// ─── Wide layout (≥900px) ────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final Widget list;
  final Widget? editor;
  final Widget? preview;

  const _WideLayout({required this.list, required this.editor, required this.preview});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Company / category list column
        SizedBox(width: 280, child: list),
        const VerticalDivider(width: 1),
        // Editor + preview column
        Expanded(
          child: editor == null
              ? _SelectPrompt()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 32),
                        child: editor,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SectionLabel(AppLocalizations.of(context)!.vtPreview),
                            const SizedBox(height: IntesharSpacing.lg),
                            Center(child: preview),
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
  final Widget picker;
  final Widget? editor;
  final Widget? preview;

  const _NarrowLayout({required this.picker, required this.editor, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
      children: [
        picker,
        const SizedBox(height: IntesharSpacing.lg),
        if (editor != null) ...[
          editor!,
          const SizedBox(height: IntesharSpacing.xl),
          SectionLabel(l.vtPreview),
          const SizedBox(height: IntesharSpacing.lg),
          Center(child: preview),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: _SelectPrompt(),
          ),
      ],
    );
  }
}

// ─── Company / category list (wide sidebar) ──────────────────────────────────

/// PROD-023: each company (its own template) with its categories under it, each
/// marked "follows the company" or "own template"; categories with no company last.
class _TemplateList extends StatelessWidget {
  final List<_Group> groups;
  final String? selectedDefId;
  final String? selectedCompanyId;
  final ValueChanged<ProductDefinition> onSelectDef;
  final ValueChanged<Company> onSelectCompany;

  const _TemplateList({
    required this.groups,
    required this.selectedDefId,
    required this.selectedCompanyId,
    required this.onSelectDef,
    required this.onSelectCompany,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 24),
      children: [
        for (final g in groups) ...[
          if (g.company != null)
            _CompanyRow(
              company: g.company!,
              selected: selectedCompanyId == g.company!.id,
              onTap: () => onSelectCompany(g.company!),
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 4),
              child: Text(l.vtNoCompany,
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: FontWeight.w700)),
            ),
          for (final d in g.defs)
            Padding(
              padding: EdgeInsetsDirectional.only(start: g.company != null ? 16 : 0),
              child: _SkuRow(
                def: d,
                selected: selectedDefId == d.id,
                inheritance: g.company == null
                    ? null
                    : (followsCompany(d, g.company) ? _Inherit.follows : _Inherit.own),
                onTap: () => onSelectDef(d),
              ),
            ),
          const SizedBox(height: IntesharSpacing.sm),
        ],
      ],
    );
  }
}

enum _Inherit { follows, own }

class _CompanyRow extends StatelessWidget {
  final Company company;
  final bool selected;
  final VoidCallback onTap;

  const _CompanyRow({required this.company, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.xs),
      child: Material(
        color: selected ? context.tones.brand.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IntesharRadii.md),
          splashColor: context.tones.brand.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.md, vertical: IntesharSpacing.sm2),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? context.tones.brand : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(IntesharRadii.sm),
                  ),
                  child: Icon(Icons.apartment_outlined,
                      size: 20, color: selected ? context.tones.onBrand : cs.onSurface),
                ),
                const SizedBox(width: IntesharSpacing.sm2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company.name,
                          style: IntesharText.bodyLg(color: cs.onSurface, w: IntesharWeight.heavy, height: 1.2),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(l.vtCompanyTemplate,
                          style: IntesharType.sans(11, color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.edit_outlined, size: 14, color: context.tones.brandInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkuRow extends StatelessWidget {
  final ProductDefinition def;
  final bool selected;

  /// null = the category has no company (nothing to follow).
  final _Inherit? inheritance;
  final VoidCallback onTap;

  const _SkuRow({required this.def, required this.selected, required this.inheritance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final follows = inheritance == _Inherit.follows;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.xs),
      child: Material(
        color: selected ? context.tones.brand.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IntesharRadii.md),
          splashColor: context.tones.brand.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.md, vertical: IntesharSpacing.sm2),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? context.tones.brand : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(IntesharRadii.sm),
                  ),
                  child: Center(
                    child: Text(
                      def.sku,
                      style: IntesharType.mono(11,
                          color: selected ? context.tones.onBrand : cs.onSurface,
                          w: kMonoHeaviest,
                          letterSpacing: 0.4),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: IntesharSpacing.sm2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // UX-127: `bodyLg` is the list-row step, and the row ellipsizes.
                        def.name,
                        style: IntesharText.bodyLg(
                          color: cs.onSurface,
                          w: selected ? IntesharWeight.heavy : IntesharWeight.regular,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            Formatters.iqd(def.defaultPrice),
                            style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.2),
                          ),
                          if (inheritance != null) ...[
                            const SizedBox(width: IntesharSpacing.sm),
                            // Icon + words, never colour alone.
                            Icon(follows ? Icons.link : Icons.tune,
                                size: 12, color: follows ? cs.onSurfaceVariant : context.tones.brandInk),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                follows ? l.vtFollowsCompany : l.vtOwnTemplate,
                                style: IntesharType.sans(11,
                                    color: follows ? cs.onSurfaceVariant : context.tones.brandInk,
                                    w: follows ? FontWeight.w400 : FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.edit_outlined, size: 14, color: context.tones.brandInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Company / category dropdown (narrow) ────────────────────────────────────

class _TargetDropdown extends StatelessWidget {
  final List<_Group> groups;

  /// `co:<id>` or `def:<id>`.
  final String? value;
  final ValueChanged<String> onPick;

  const _TargetDropdown({required this.groups, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final items = <DropdownMenuItem<String>>[];
    for (final g in groups) {
      final c = g.company;
      if (c != null) {
        items.add(DropdownMenuItem(
          value: 'co:${c.id}',
          child: Row(children: [
            Icon(Icons.apartment_outlined, size: 16, color: context.tones.brandInk),
            const SizedBox(width: IntesharSpacing.sm),
            Expanded(
              child: Text('${c.name} · ${l.vtCompanyTemplate}',
                  style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ));
      } else {
        items.add(DropdownMenuItem(
          value: 'hdr:none',
          enabled: false,
          child: Text(l.vtNoCompany, style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: FontWeight.w700)),
        ));
      }
      for (final d in g.defs) {
        final follows = followsCompany(d, c);
        items.add(DropdownMenuItem(
          value: 'def:${d.id}',
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: c != null ? 20 : 0),
            child: Row(children: [
              Text(d.sku, style: IntesharType.mono(12, color: context.tones.brandInk, w: FontWeight.w700)),
              const SizedBox(width: IntesharSpacing.sm2),
              Expanded(
                child: Text(d.name, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
              ),
              if (c != null)
                Text(follows ? l.vtFollowsCompany : l.vtOwnTemplate,
                    style: IntesharType.sans(11, color: follows ? cs.onSurfaceVariant : context.tones.brandInk)),
            ]),
          ),
        ));
      }
    }
    return InkCard(
      padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.lg, vertical: IntesharSpacing.xs),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(l.vtSelectPrompt, style: Theme.of(context).textTheme.bodyMedium),
          isExpanded: true,
          items: items,
          onChanged: (v) {
            if (v != null) onPick(v);
          },
        ),
      ),
    );
  }
}

// ─── Inheritance note + the "follows its company" panel (PROD-023) ───────────

class _InheritanceNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final List<Widget> actions;

  const _InheritanceNote({required this.icon, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: context.tones.brandInk),
              const SizedBox(width: IntesharSpacing.sm2),
              Expanded(child: Text(text, style: IntesharType.sans(13, color: cs.onSurface))),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: IntesharSpacing.sm),
            Wrap(spacing: IntesharSpacing.sm, runSpacing: IntesharSpacing.xs, children: actions),
          ],
        ],
      ),
    );
  }
}

/// A category that follows its company has nothing of its own to edit: say so,
/// show the company's template in the preview, and offer the two ways out.
class _FollowingPanel extends StatelessWidget {
  final ProductDefinition def;
  final String companyName;
  final bool busy;
  final VoidCallback onCustomise;
  final VoidCallback onEditCompany;

  const _FollowingPanel({
    required this.def,
    required this.companyName,
    required this.busy,
    required this.onCustomise,
    required this.onEditCompany,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.sm2, vertical: IntesharSpacing.xs),
              decoration: BoxDecoration(
                color: context.tones.brand,
                borderRadius: BorderRadius.circular(IntesharRadii.xs),
              ),
              child: Text(def.sku, style: IntesharType.mono(12, color: context.tones.onBrand, w: kMonoHeaviest)),
            ),
            const SizedBox(width: IntesharSpacing.sm2),
            Expanded(
              child: Text(def.name,
                  style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: IntesharSpacing.lg),
        _InheritanceNote(icon: Icons.link, text: l.vtFollowsBanner(companyName)),
        const SizedBox(height: IntesharSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: busy ? null : onCustomise,
            icon: const Icon(Icons.tune, size: 18),
            label: Text(l.vtCustomise),
          ),
        ),
        const SizedBox(height: IntesharSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onEditCompany,
            icon: const Icon(Icons.apartment_outlined, size: 18),
            label: Text(l.vtEditCompany),
          ),
        ),
      ],
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
          const SizedBox(height: IntesharSpacing.lg),
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
  /// The badge (a SKU, or "Company template") and the name beside it.
  final String code;
  final String title;

  /// A SKU badge is set in the mono face; a words badge is not.
  final bool monoCode;

  /// PROD-023: what this template applies to (company scope, own / no company),
  /// shown under the name.
  final Widget? notice;
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

  /// UX-78: the template on screen differs from the saved one.
  final bool dirty;
  final bool inScrollable;

  const _TemplateEditor({
    required this.code,
    required this.title,
    this.monoCode = true,
    this.notice,
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
    required this.dirty,
    this.inScrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    // These two toggles have no l10n keys yet, so label them inline matching the
    // app's bilingual fallback pattern (see pos_home_page Expiry/Receipt labels).
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

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
                padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.sm2, vertical: IntesharSpacing.xs),
                decoration: BoxDecoration(
                  color: context.tones.brand,
                  borderRadius: BorderRadius.circular(IntesharRadii.xs),
                ),
                child: Text(
                  code,
                  style: monoCode
                      ? IntesharType.mono(12, color: context.tones.onBrand, w: kMonoHeaviest)
                      : IntesharType.sans(12, color: context.tones.onBrand, w: FontWeight.w700),
                ),
              ),
              const SizedBox(width: IntesharSpacing.sm2),
              Expanded(
                child: Text(
                  title,
                  style: IntesharType.sans(16,
                      color: cs.onSurface, w: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // UX-78: the unsaved state is stated on the thing being edited,
              // not left to the operator's memory. Icon + words, never colour
              // alone.
              if (dirty) ...[
                const SizedBox(width: IntesharSpacing.sm),
                StampPill(
                  label: isAr ? 'غير محفوظ' : 'Unsaved',
                  color: context.tones.brandInk,
                  icon: Icons.edit_outlined,
                  filled: false,
                ),
              ],
            ],
          ),
        ),

        if (notice != null) ...[
          notice!,
          const SizedBox(height: 20),
        ],

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
          density: CardDensity.flush,
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
              Divider(height: 1, color: cs.outline),
              _BrandSwitch(
                label: isAr ? 'إظهار اسم الشركة' : 'Show company name',
                value: edited.showCompanyName,
                onChanged: (v) =>
                    onToggle(edited.copyWith(showCompanyName: v)),
              ),
              Divider(height: 1, color: cs.outline),
              _BrandSwitch(
                label: isAr ? 'إظهار اسم الفئة' : 'Show category name',
                value: edited.showCategoryName,
                onChanged: (v) =>
                    onToggle(edited.copyWith(showCategoryName: v)),
              ),
              Divider(height: 1, color: cs.outline),
              _BrandSwitch(
                label: isAr ? 'طباعة شعار الوكيل الرئيسي' : 'Print main agent logo',
                value: edited.showAgentLogo,
                onChanged: (v) => onToggle(edited.copyWith(showAgentLogo: v)),
              ),
              Divider(height: 1, color: cs.outline),
              _BrandSwitch(
                label: isAr ? 'طباعة شعار الشركة (الفئة)' : 'Print company (category) logo',
                value: edited.showCompanyLogo,
                onChanged: (v) => onToggle(edited.copyWith(showCompanyLogo: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── QR section ───────────────────────────────────────────────────
        SectionLabel(l.vtQrSection),
        InkCard(
          padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.xs),
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
                        // UX-127: was an off-scale 13 at `w600`, which has no
                        // registered face.
                        style: IntesharText.bodyLg(
                          color: cs.onSurfaceVariant,
                          w: IntesharWeight.semibold,
                        ),
                      ),
                      const SizedBox(height: IntesharSpacing.sm),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          // UX-119: `compact` + `shrinkWrap` shrank this pair
                          // below 48dp. It chooses what the QR on every printed
                          // voucher encodes — PIN or serial — so it is not a
                          // control to make hard to hit.
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
                      const SizedBox(width: IntesharSpacing.md),
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
                        style: IntesharType.codec(
                          size: 12,
                          color: cs.onSurfaceVariant,
                          w: IntesharWeight.semibold,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          edited.qrPayload(
                              pin: _samplePin, serial: _sampleSerial),
                          style: IntesharType.mono(12, color: context.tones.brandInk, w: FontWeight.w600, letterSpacing: 0.4),
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
            hintText: 'Inteshar · www.inteshar.iq',
          ),
        ),
        const SizedBox(height: IntesharSpacing.xl),

        // ── Save button ──────────────────────────────────────────────────
        // UX-78: Save used to look identical before and after a change, so
        // "did that take?" was unanswerable without leaving and coming back.
        // It now carries the dirty state itself and goes inert with nothing to
        // write, and a line under it says which of the two is true.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (saving || !dirty) ? null : onSave,
            icon: saving
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      // ElevatedButton is a brand fill in this theme.
                      color: context.tones.onBrand,
                    ),
                  )
                : Icon(dirty ? Icons.save_outlined : Icons.check, size: 18),
            label: Text(l.vtSave),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          dirty
              ? (isAr
                  ? 'تغييرات غير محفوظة — اضغط حفظ القالب لتطبيقها على الطباعة.'
                  : 'Unsaved changes — tap Save to apply them to printing.')
              : (isAr
                  ? 'كل التغييرات محفوظة.'
                  : 'All changes saved.'),
          style: IntesharType.sans(12,
              color: dirty ? context.tones.brandInk : cs.onSurfaceVariant,
              w: dirty ? FontWeight.w700 : FontWeight.w400),
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
        style: IntesharType.codec(
          size: 14,
          color: cs.onSurface,
          w: IntesharWeight.regular,
        ),
      ),
      value: value,
      activeThumbColor: context.tones.brand,
      onChanged: onChanged,
    );
  }
}

/// A dashed placeholder box shown in the template preview where a logo will print. The real
/// image (owning main agent's logo / SKU company logo) is filled in at sale time.
class _LogoPlaceholder extends StatelessWidget {
  final String label;
  const _LogoPlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 110),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 14, color: Colors.black38),
          const SizedBox(width: IntesharSpacing.xs),
          Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.black45)),
        ],
      ),
    );
  }
}

// ─── 58mm thermal receipt preview ────────────────────────────────────────────

class _ReceiptPreview extends StatelessWidget {
  final ProductDefinition def;
  final VoucherTemplate template;

  /// The company printed on the COMPANY NAME line; a sample when unknown.
  final String? companyName;

  const _ReceiptPreview({required this.def, required this.template, this.companyName});

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
            // ── Branding logos ──────────────────────────────────────────
            // Placeholders: the OWNING main agent's logo is resolved per-sale (not known
            // here), and the company logo comes from the SKU's company. The real images
            // print on the receipt + show on the POS reveal.
            if (template.showAgentLogo) ...[
              _LogoPlaceholder(
                label: Localizations.localeOf(context).languageCode == 'ar'
                    ? 'شعار الوكيل الرئيسي'
                    : 'Main agent logo',
              ),
              const SizedBox(height: IntesharSpacing.sm),
            ],
            if (template.showCompanyLogo) ...[
              _LogoPlaceholder(
                label: Localizations.localeOf(context).languageCode == 'ar'
                    ? 'شعار الشركة'
                    : 'Company logo',
              ),
              const SizedBox(height: IntesharSpacing.sm),
            ],
            // ── Header ──────────────────────────────────────────────────
            if (template.headerText.isNotEmpty) ...[
              Text(
                template.headerText,
                textAlign: TextAlign.center,
                style: IntesharType.mono(14, color: Colors.black, w: FontWeight.w700, letterSpacing: 0.4),
              ),
              const SizedBox(height: IntesharSpacing.sm),
            ] else ...[
              Text(
                _sampleCompany,
                textAlign: TextAlign.center,
                style: IntesharType.mono(14, color: Colors.black54, w: FontWeight.w700, letterSpacing: 0.4),
              ),
              const SizedBox(height: IntesharSpacing.sm),
            ],

            // ── Company name (telecom) ───────────────────────────────────
            if (template.showCompanyName) ...[
              Text(
                companyName ?? _sampleCompanyName,
                textAlign: TextAlign.center,
                style: IntesharType.mono(14, color: Colors.black, w: FontWeight.w700, letterSpacing: 0.6),
              ),
              const SizedBox(height: IntesharSpacing.xs),
            ],

            // ── Category name (product-definition name) ──────────────────
            if (template.showCategoryName) ...[
              Text(
                def.name,
                textAlign: TextAlign.center,
                style: IntesharType.mono(11, color: Colors.black54),
              ),
              const SizedBox(height: IntesharSpacing.xs),
            ],

            // ── Product name ─────────────────────────────────────────────
            if (template.showProductName) ...[
              Text(
                def.name,
                textAlign: TextAlign.center,
                style: IntesharType.mono(12, color: Colors.black87),
              ),
              const SizedBox(height: IntesharSpacing.xs),
            ],

            // ── Price ────────────────────────────────────────────────────
            if (template.showPrice) ...[
              Text(
                Formatters.iqd(def.defaultPrice),
                textAlign: TextAlign.center,
                style: IntesharType.mono(12, color: Colors.black87, w: FontWeight.w600),
              ),
              const SizedBox(height: IntesharSpacing.xs),
            ],

            _DashedDivider(),
            const SizedBox(height: IntesharSpacing.sm),

            // ── Serial ───────────────────────────────────────────────────
            if (template.showSerial) ...[
              _ReceiptRow(label: 'SN', value: _sampleSerial),
              const SizedBox(height: 6),
            ],

            // ── PIN (larger, bold) ───────────────────────────────────────
            if (template.showPin) ...[
              const SizedBox(height: IntesharSpacing.xs),
              // PROD-030: the paper frames the PIN, so the preview does too.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1.5)),
                child: Text(
                  _samplePin,
                  textAlign: TextAlign.center,
                  style: IntesharType.mono(20, color: Colors.black, w: kMonoHeaviest, letterSpacing: 2),
                ),
              ),
              const SizedBox(height: IntesharSpacing.sm),
            ],

            // ── QR code ──────────────────────────────────────────────────
            if (template.qrEnabled && qrPayload.isNotEmpty) ...[
              _DashedDivider(),
              const SizedBox(height: IntesharSpacing.sm2),
              QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 120,
                backgroundColor: Colors.white,
              ),
              // PROD-022: like the paper — the QR's content is written under it only when
              // the PIN/serial it carries is not already printed above.
              if (!qrValueAlreadyPrinted(template, pin: _samplePin, serial: _sampleSerial)) ...[
                const SizedBox(height: 6),
                Text(
                  qrPayload,
                  textAlign: TextAlign.center,
                  style: IntesharType.mono(11, color: Colors.black54, letterSpacing: 0.3),
                ),
              ],
              const SizedBox(height: IntesharSpacing.sm),
            ],

            // ── Redeem instructions ──────────────────────────────────────
            if (template.redeemInstructions.isNotEmpty) ...[
              _DashedDivider(),
              const SizedBox(height: IntesharSpacing.sm),
              Text(
                template.redeemInstructions,
                textAlign: TextAlign.center,
                style: IntesharType.mono(11, color: Colors.black87).copyWith(height: 1.5),
              ),
              const SizedBox(height: IntesharSpacing.sm),
            ],

            // ── Footer ───────────────────────────────────────────────────
            if (template.footerText.isNotEmpty) ...[
              _DashedDivider(),
              const SizedBox(height: IntesharSpacing.sm),
              // UX-147 floors UI text at 11px; this is deliberately exempt.
              // It is not UI text — it is a DEPICTION of the thermal slip, and
              // the slip really does print this small. Raising it would make the
              // preview stop matching what comes out of the printer, which is
              // the only thing this widget is for.
              Text(
                template.footerText,
                textAlign: TextAlign.center,
                style: IntesharType.mono(9, color: Colors.black54).copyWith(height: 1.5),
              ),
              const SizedBox(height: IntesharSpacing.xs),
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
          style: IntesharType.mono(11, color: Colors.black54, w: FontWeight.w600),
        ),
        Expanded(
          child: Text(
            value,
            style: IntesharType.mono(11, color: Colors.black87, letterSpacing: 0.3),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
