import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/companies/data/company_repository.dart';
import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/image_upload_field.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

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
    final idCtrl = TextEditingController(
        text: existing?.id ?? 'def-${DateTime.now().millisecondsSinceEpoch}');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    final priceCtrl = TextEditingController(text: existing?.defaultPrice ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DefinitionFormSheet(
        title: existing == null ? l.defsFormTitleNew : l.defsFormTitleEdit,
        idCtrl: idCtrl,
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
            id: idCtrl.text.trim(),
            name: nameCtrl.text.trim(),
            sku: skuCtrl.text.trim().toUpperCase(),
            defaultPrice: priceCtrl.text.trim(),
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

  Future<void> _delete(ProductDefinition def, {bool force = false}) async {
    final l = AppLocalizations.of(context)!;
    // The first delete shows the generic confirm; a forced retry skips it (the user
    // already confirmed via the "delete anyway" dialog below).
    if (!force) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.defsDeleteTitle),
          content: Text(l.defsDeleteConfirm(def.name)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.defsCancel)),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              child: Text(l.defsDelete),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    try {
      final api = ref.read(apiClientProvider);
      final repo = DefinitionRepository(api);
      await repo.delete(def.id, force: force);
      _load();
    } catch (e) {
      if (!mounted) return;
      final apiErr = ApiException.from(e);
      // 409 = the category still has vouchers referencing it. Show the backend's
      // explanatory message and offer a forced delete (admin override).
      if (apiErr?.statusCode == 409) {
        final forceConfirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.defsDeleteTitle),
            content: Text(apiErr!.message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l.defsCancel)),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error),
                child: Text(l.defsDeleteAnyway),
              ),
            ],
          ),
        );
        if (forceConfirm == true) await _delete(def, force: true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErr?.message ?? l.commonDeleteFailed('$e'))),
      );
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: IntesharColors.saffron.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      defs.length.toString(),
                      style: IntesharType.display(20,
                          color: IntesharColors.saffronDeep, w: FontWeight.w900),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.defsTitlesLabel,
                      style: IntesharType.sans(13,
                          color: IntesharColors.saffronDeep, w: FontWeight.w700),
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
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _DefinitionRow(
      {required this.def, required this.onEdit, required this.onDelete});

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
        onTap: widget.onEdit,
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
                      ? IntesharColors.saffron
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(IntesharRadii.sm),
                ),
                alignment: Alignment.center,
                child: monoText(
                  widget.def.sku,
                  size: 13,
                  color: _hover ? IntesharColors.ink : cs.onSurface,
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
                        15,
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
                        style: IntesharType.sans(10,
                            color: IntesharColors.lichen, w: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      monoText(
                        Formatters.iqd(widget.def.defaultPrice),
                        size: 13,
                        color: cs.onSurface,
                        w: FontWeight.w700,
                      ),
                    ],
                  ),
                ),
              ),
              // Edit / Delete menu — an explicit delete control so the action is
              // discoverable on web (HQ's main surface), where swipe-to-delete is
              // invisible (B-072). Swipe still works as a shortcut on touch.
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
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
  final TextEditingController idCtrl;
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
    required this.idCtrl,
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
  String? _priceError;

  // Validates the category (denomination) form before saving: requires a
  // non-empty name and SKU and a numeric default price > 0, and trims +
  // uppercases the SKU. Returns true when valid; otherwise sets inline error
  // texts and returns false so the save is blocked.
  bool _validate({required bool ar}) {
    final name = widget.nameCtrl.text.trim();
    final sku = widget.skuCtrl.text.trim().toUpperCase();
    if (widget.skuCtrl.text != sku) widget.skuCtrl.text = sku;
    final price = num.tryParse(widget.priceCtrl.text.trim());
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
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: cs.outline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            SectionLabel(widget.isNew ? l.defsMintLabel : l.defsAmendLabel),
            Text(
              widget.title,
              style: IntesharType.display(28, color: cs.onSurface),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: widget.nameCtrl,
              decoration: InputDecoration(
                  labelText: l.defsFieldName, errorText: _nameError),
              onChanged: _nameError == null
                  ? null
                  : (_) => setState(() => _nameError = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.skuCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                  labelText: l.defsFieldSku, errorText: _skuError),
              onChanged: _skuError == null
                  ? null
                  : (_) => setState(() => _skuError = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.priceCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: l.defsFieldPrice, errorText: _priceError),
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
            if (widget.isNew) ...[
              const SizedBox(height: 12),
              TextField(
                controller: widget.idCtrl,
                decoration: InputDecoration(labelText: l.defsFieldId),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')));
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
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
