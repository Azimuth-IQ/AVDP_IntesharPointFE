import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/companies/data/company_repository.dart';
import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/inventory/domain/sku_from_name.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
import 'package:inteshar/shared/widgets/confirm_dialog.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/loading_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/sheet_frame.dart';

class DefinitionsPage extends ConsumerStatefulWidget {
  const DefinitionsPage({super.key});

  @override
  ConsumerState<DefinitionsPage> createState() => _DefinitionsPageState();
}

class _DefinitionsPageState extends ConsumerState<DefinitionsPage> {
  List<ProductDefinition>? _defs;
  Object? _error;
  bool _loading = true;
  String _search = '';

  /// Category ids with a delete in flight (UX-87) — guards BOTH entry points.
  final Set<String> _deleting = {};

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
      final api = ref.read(apiClientProvider);
      final repo = DefinitionRepository(api);
      final defs = await repo.readAll();
      if (mounted) setState(() => _defs = defs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForm({ProductDefinition? existing}) async {
    final l = AppLocalizations.of(context)!;
    final api = ref.read(apiClientProvider);
    List<Company> companies = [];
    try {
      companies = await CompanyRepository(api).readAll();
    } catch (_) {
      // Non-fatal: the category can be saved without a company.
    }
    if (!mounted) return;
    String? selectedCompanyId =
        (existing != null && existing.companyId.isNotEmpty) ? existing.companyId : null;
    String imageUrl = existing?.imageUrl ?? '';
    // UX-75: the document id is generated here and never shown. It is a storage
    // key with no format rule and no uniqueness check the operator could satisfy,
    // and stock and prices hang off it — the operator-facing identity is the SKU,
    // which the form asks for properly.
    final id = existing?.id ?? 'def-${DateTime.now().millisecondsSinceEpoch}';
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    // UX-70: this field is money and is now typed like every other money field
    // in the app — thousands-grouped as you type, read back with [parseAmount].
    // So it also has to OPEN grouped, or the first keystroke would reformat a
    // number the operator never touched.
    final existingPrice = num.tryParse(existing?.defaultPrice ?? '');
    final priceCtrl = TextEditingController(
      text: existingPrice == null
          ? (existing?.defaultPrice ?? '')
          : Formatters.money(existingPrice),
    );
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DefinitionFormSheet(
        title: existing == null ? l.defsFormTitleNew : l.defsFormTitleEdit,
        nameCtrl: nameCtrl,
        skuCtrl: skuCtrl,
        priceCtrl: priceCtrl,
        descCtrl: descCtrl,
        isNew: existing == null,
        companies: companies,
        initialCompanyId: selectedCompanyId,
        onCompanyChanged: (v) => selectedCompanyId = v,
        initialImageUrl: imageUrl,
        onImageUrlChanged: (v) => imageUrl = v,
        onSave: () async {
          final repo = DefinitionRepository(api);
          final def = ProductDefinition(
            id: id,
            name: nameCtrl.text.trim(),
            sku: skuCtrl.text.trim().toUpperCase(),
            // UX-70: the field carries separators now, so the digits go to the
            // server — `"5,000"` on the wire would land as a null Double.
            defaultPrice:
                (parseAmount(priceCtrl.text) ?? 0).toString(),
            description: descCtrl.text.trim(),
            companyId: selectedCompanyId ?? '',
            imageUrl: imageUrl,
            template: existing?.template ?? const VoucherTemplate(),
          );
          if (existing == null) {
            await repo.create(def);
          } else {
            await repo.update(def);
          }
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  /// UX-87: the confirm closes the instant it is tapped and the DELETE then ran
  /// unguarded — and this category has TWO delete entry points (the swipe and
  /// the row menu), so the second tap did not even have to be on the same
  /// control. [_deleting] gates both, and the row goes inert while it runs.
  ///
  /// The forced retry is a loop rather than recursion so the guard is held for
  /// the whole sequence instead of blocking its own second pass.
  Future<void> _delete(ProductDefinition def) async {
    final l = AppLocalizations.of(context)!;
    if (_deleting.contains(def.id)) return;
    final confirmed = await showConfirm(
      context,
      title: l.defsDeleteTitle,
      body: l.defsDeleteConfirm(def.name),
      confirmLabel: l.defsDelete,
      cancelLabel: l.defsCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    var force = false;
    while (true) {
      setState(() => _deleting.add(def.id));
      Object? failure;
      try {
        await DefinitionRepository(ref.read(apiClientProvider))
            .delete(def.id, force: force);
      } catch (e) {
        failure = e;
      }
      if (!mounted) return;
      setState(() => _deleting.remove(def.id));
      if (failure == null) {
        await _load();
        return;
      }
      final apiErr = ApiException.from(failure);
      // 409 = the category still has vouchers referencing it. Show the backend's
      // explanatory message and offer a forced delete (admin override).
      if (apiErr?.statusCode == 409 && !force) {
        final again = await showConfirm(
          context,
          title: l.defsDeleteTitle,
          body: apiErr!.message,
          confirmLabel: l.defsDeleteAnyway,
          cancelLabel: l.defsCancel,
          destructive: true,
        );
        if (!again || !mounted) return;
        force = true;
        continue;
      }
      showError(context, apiErr?.message ?? failure);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    if (_loading) {
      return LoadingState(
        message: Localizations.localeOf(context).languageCode == 'ar'
            ? 'جارٍ تحميل الفئات…'
            : 'Loading categories…',
      );
    }
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: _load);
    }

    final defs = _defs ?? [];
    final filtered = _search.isEmpty
        ? defs
        : defs.where((d) {
            final q = _search.toLowerCase();
            return d.name.toLowerCase().contains(q) ||
                d.sku.toLowerCase().contains(q) ||
                d.description.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      body: MaxWidthBox(
        child: Column(
          children: [
            PageHeader(
              eyebrow: l.navCatalog,
              title: l.navCatalog,
              subtitle: l.defsSubtitle,
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: IntesharSpacing.lg, vertical: IntesharSpacing.sm2),
                decoration: BoxDecoration(
                  color: context.tones.brand.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      defs.length.toString(),
                      style: IntesharType.display(20,
                          color: context.tones.brandInk, w: FontWeight.w900),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.defsTitlesLabel,
                      style: IntesharType.sans(14,
                          color: context.tones.brandInk, w: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 12),
              child: TextField(
                decoration: InputDecoration(
                  hintText: l.defsSearchHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? EmptyState(
                      message: defs.isEmpty
                          ? l.defsEmptyFirst
                          : l.defsEmptySearch(_search),
                      actionLabel: defs.isEmpty ? l.defsAddFirst : null,
                      onAction: defs.isEmpty ? () => _showForm() : null,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                                16, 0, 16, 24),
                            sliver: SliverToBoxAdapter(
                              child: InkCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    // Column header
                                    Padding(
                                      padding: const EdgeInsetsDirectional
                                          .fromSTEB(16, 10, 12, 10),
                                      child: _DefsTableHeader(l: l),
                                    ),
                                    const Hairline(),
                                    // Rows
                                    ...filtered.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final def = entry.value;
                                      return Column(
                                        children: [
                                          Dismissible(
                                            key: ValueKey(def.id),
                                            direction:
                                                DismissDirection.endToStart,
                                            background: Container(
                                              alignment: AlignmentDirectional
                                                  .centerEnd,
                                              padding:
                                                  const EdgeInsetsDirectional
                                                      .only(end: 22),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error
                                                    .withValues(alpha: 0.10),
                                              ),
                                              child: StampPill(
                                                label: l.defsDelete,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                                icon: Icons.delete_outline,
                                              ),
                                            ),
                                            confirmDismiss: (_) async {
                                              await _delete(def);
                                              return false;
                                            },
                                            child: _DefinitionRow(
                                              def: def,
                                              busy: _deleting.contains(def.id),
                                              onEdit: () =>
                                                  _showForm(existing: def),
                                              onDelete: () => _delete(def),
                                            ),
                                          ),
                                          if (i < filtered.length - 1)
                                            const Hairline(),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.add),
        label: Text(l.defsNewDenomination),
      ),
    );
  }
}

// ── Table header ─────────────────────────────────────────────────────────────

class _DefsTableHeader extends StatelessWidget {
  final AppLocalizations l;
  const _DefsTableHeader({required this.l});

  @override
  Widget build(BuildContext context) {
    final style =
        IntesharType.sans(11, color: IntesharColors.lichen, w: FontWeight.w700);
    return Row(
      children: [
        // SKU avatar placeholder width
        const SizedBox(width: 52),
        Expanded(child: Text(l.defsFieldName, style: style)),
        SizedBox(
          width: 120,
          child: Text(l.defsPrice, textAlign: TextAlign.end, style: style),
        ),
        // Edit button placeholder
        const SizedBox(width: 40),
      ],
    );
  }
}

// ── Definition row ────────────────────────────────────────────────────────────

class _DefinitionRow extends StatefulWidget {
  final ProductDefinition def;

  /// A delete is in flight for this row — every control is inert (UX-87).
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _DefinitionRow(
      {required this.def,
      this.busy = false,
      required this.onEdit,
      required this.onDelete});

  @override
  State<_DefinitionRow> createState() => _DefinitionRowState();
}

class _DefinitionRowState extends State<_DefinitionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.busy ? null : widget.onEdit,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // SKU tile — saffron on hover, recessed otherwise
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _hover
                      ? context.tones.brand
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(IntesharRadii.sm),
                ),
                alignment: Alignment.center,
                child: monoText(
                  widget.def.sku,
                  // UX-127: was an off-scale 13. `body` is monoText's own step
                  // and the size the identical SKU tile on the inventory screen
                  // uses — a longer SKU also has to fit this 42px tile.
                  size: IntesharScale.body,
                  // Hover paints the tile with the brand, so the SKU rides on
                  // the measured on-brand foreground, not a fixed ink.
                  color: _hover ? context.tones.onBrand : cs.onSurface,
                  w: FontWeight.w900,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 14),
              // Name + description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.def.name,
                      style: IntesharType.sans(
                        16,
                        color: cs.onSurface,
                        w: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.def.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.def.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IntesharType.sans(12, color: IntesharColors.lichen),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Price (right-aligned, monospace)
              SizedBox(
                width: 120,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l.defsPrice,
                        style: IntesharType.sans(11,
                            color: IntesharColors.lichen, w: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      monoText(
                        // UX-127: was an off-scale 13; this is the row's figure
                        // and it has a 120px column to itself.
                        Formatters.iqd(widget.def.defaultPrice),
                        size: IntesharScale.bodyLg,
                        color: cs.onSurface,
                        w: IntesharWeight.bold,
                      ),
                    ],
                  ),
                ),
              ),
              // Edit / Delete menu — an explicit delete control so the action is
              // discoverable on web (HQ's main surface), where swipe-to-delete is
              // invisible (B-072). Swipe still works as a shortcut on touch.
              PopupMenuButton<String>(
                enabled: !widget.busy,
                icon: widget.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
                tooltip: l.defsEdit,
                onSelected: (v) => v == 'edit' ? widget.onEdit() : widget.onDelete(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(l.defsEdit),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: cs.error),
                      title: Text(l.defsDelete, style: TextStyle(color: cs.error)),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Definition form sheet ────────────────────────────────────────────────────

class _DefinitionFormSheet extends StatefulWidget {
  final String title;
  final TextEditingController nameCtrl;
  final TextEditingController skuCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController descCtrl;
  final bool isNew;
  final List<Company> companies;
  final String? initialCompanyId;
  final ValueChanged<String?> onCompanyChanged;
  final String initialImageUrl;
  final ValueChanged<String> onImageUrlChanged;
  final Future<void> Function() onSave;

  const _DefinitionFormSheet({
    required this.title,
    required this.nameCtrl,
    required this.skuCtrl,
    required this.priceCtrl,
    required this.descCtrl,
    required this.isNew,
    required this.companies,
    required this.initialCompanyId,
    required this.onCompanyChanged,
    required this.initialImageUrl,
    required this.onImageUrlChanged,
    required this.onSave,
  });

  @override
  State<_DefinitionFormSheet> createState() => _DefinitionFormSheetState();
}

class _DefinitionFormSheetState extends State<_DefinitionFormSheet> {
  bool _saving = false;
  late String? _companyId = widget.initialCompanyId;
  late String _imageUrl = widget.initialImageUrl;
  String? _nameError;
  String? _skuError;
  /// True once the operator has typed in the code field themselves — from then
  /// on it stops tracking the name, so a deliberate code is never overwritten.
  bool _skuEdited = false;
  String? _priceError;

  // Validates the category (denomination) form before saving: requires a
  // non-empty name and SKU and a numeric default price > 0, and trims +
  // uppercases the SKU. Returns true when valid; otherwise sets inline error
  // texts and returns false so the save is blocked.
  bool _validate({required bool ar}) {
    final name = widget.nameCtrl.text.trim();
    final sku = widget.skuCtrl.text.trim().toUpperCase();
    if (widget.skuCtrl.text != sku) widget.skuCtrl.text = sku;
    // UX-70: `num.tryParse` rejected `5,000` — the format the app itself types
    // into every other money field, and the format the grid above FORCES — so
    // the error said "Enter a price greater than 0", blaming the value rather
    // than the separators. `parseAmount` is the app's one money reader.
    final price = parseAmount(widget.priceCtrl.text);
    setState(() {
      _nameError =
          name.isEmpty ? (ar ? 'الاسم مطلوب' : 'Name is required') : null;
      _skuError =
          sku.isEmpty ? (ar ? 'رمز المنتج مطلوب' : 'SKU is required') : null;
      _priceError = (price == null || price <= 0)
          ? (ar ? 'أدخل سعراً أكبر من صفر' : 'Enter a price greater than 0')
          : null;
    });
    return _nameError == null && _skuError == null && _priceError == null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    // UX-77: this sheet used to re-decide the handle, the keyboard inset, the
    // height cap and the title size for itself, and its action row was the LAST
    // child of the scroll view — so on a 360dp POS with the keyboard up you
    // scrolled past every field to reach Save. `SheetFrame` owns those four
    // decisions and pins the footer above the scroll area.
    return SheetFrame(
      eyebrow: widget.isNew ? l.defsMintLabel : l.defsAmendLabel,
      title: widget.title,
      footer: _actions(l),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.nameCtrl,
              decoration: InputDecoration(
                  labelText: l.defsFieldName, errorText: _nameError),
              onChanged: (v) {
                // C-05: "ورمز المادة من نرفعة ياخذ اسم الفئة وليس اني اقوم
                // بكتابتة" — the code follows the category name instead of being
                // typed twice. It stops following the moment someone edits the
                // code deliberately, and never moves on an existing product,
                // where the SKU is the identity that stock and prices hang off.
                if (widget.isNew && !_skuEdited) {
                  widget.skuCtrl.text = skuFromName(v);
                }
                if (_nameError != null || _skuError != null) {
                  setState(() {
                    _nameError = null;
                    _skuError = null;
                  });
                } else {
                  setState(() {}); // reflect the derived code
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.skuCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l.defsFieldSku,
                errorText: _skuError,
                helperText: widget.isNew && !_skuEdited
                    ? (Localizations.localeOf(context).languageCode == 'ar'
                        ? 'مشتق من اسم الفئة — يمكنك تعديله'
                        : 'Derived from the category name — you can edit it')
                    : null,
              ),
              onChanged: (_) {
                _skuEdited = true;
                if (_skuError != null) setState(() => _skuError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.priceCtrl,
              keyboardType: TextInputType.number,
              // UX-70: same three pieces as every other money entry in the app
              // — group as you type, name the currency, read back with
              // `parseAmount`. This is the field every unpriced agent inherits,
              // so it was the worst place to keep a second convention.
              inputFormatters: const [ThousandsInputFormatter()],
              decoration: InputDecoration(
                labelText: l.defsFieldPrice,
                errorText: _priceError,
                suffixText: Formatters.currencyUnit(
                    Localizations.localeOf(context).languageCode),
              ),
              onChanged: _priceError == null
                  ? null
                  : (_) => setState(() => _priceError = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.descCtrl,
              maxLines: 2,
              decoration: InputDecoration(labelText: l.defsFieldDescription),
            ),
            const SizedBox(height: 12),
            ImageUploadField(
              value: _imageUrl.isEmpty ? null : _imageUrl,
              kind: 'product-image',
              label: ar ? 'صورة المنتج' : 'Product Image',
              onChanged: (v) {
                setState(() => _imageUrl = v);
                widget.onImageUrlChanged(v);
              },
            ),
            if (widget.companies.isNotEmpty) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final ar = Localizations.localeOf(context).languageCode == 'ar';
                return DropdownButtonFormField<String?>(
                  initialValue: _companyId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: ar ? 'الشركة' : 'Company'),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(ar ? 'بدون شركة' : 'No company')),
                    ...widget.companies.map(
                      (c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _companyId = v);
                    widget.onCompanyChanged(v);
                  },
                );
              }),
            ],
          ],
        ),
    );
  }

  /// UX-77: the action row, pinned by [SheetFrame.footer] instead of trailing
  /// the fields. Validation still runs against the whole form, so an error on a
  /// field that has scrolled out of view is still what blocks the save.
  Widget _actions(AppLocalizations l) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(l.defsCancel),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    if (!_validate(ar: ar)) return;
                    setState(() => _saving = true);
                    try {
                      await widget.onSave();
                    } catch (e) {
                      if (mounted) {
                        // ignore: use_build_context_synchronously
                        showError(context, e);
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.defsSave),
          ),
        ),
      ],
    );
  }
}
