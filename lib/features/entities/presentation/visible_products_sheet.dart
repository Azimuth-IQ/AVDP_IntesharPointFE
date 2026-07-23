import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/features/companies/data/company_repository.dart';
import 'package:inteshar/features/inventory/data/definition_repository.dart';
import 'package:inteshar/features/inventory/data/definition_restriction_repository.dart';
import 'package:inteshar/features/inventory/domain/product_definition.dart';
import 'package:inteshar/shared/widgets/error_state.dart';

/// B-081: HQ picks which voucher definitions an account (and its whole subtree)
/// can see & sell — a "Visible products" checklist over the full catalog. Ticked =
/// visible; unticking hides it for this account and everything under it. Rows a
/// PARENT already hid are shown locked (managed higher up the tree).
Future<void> showVisibleProductsSheet(
  BuildContext context, {
  required String entityId,
  required String entityName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VisibleProductsSheet(entityId: entityId, entityName: entityName),
  );
}

class _VisibleProductsSheet extends ConsumerStatefulWidget {
  const _VisibleProductsSheet({required this.entityId, required this.entityName});
  final String entityId;
  final String entityName;

  @override
  ConsumerState<_VisibleProductsSheet> createState() => _VisibleProductsSheetState();
}

class _VisibleProductsSheetState extends ConsumerState<_VisibleProductsSheet> {
  List<ProductDefinition> _defs = const [];
  Map<String, String> _companyNames = const {}; // companyId -> name
  Set<String> _restricted = {}; // own (editable) hidden SKUs
  Set<String> _inherited = {}; // ancestor-hidden SKUs (locked)
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  DefinitionRestrictionRepository get _repo =>
      DefinitionRestrictionRepository(ref.read(apiClientProvider));

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
      final results = await Future.wait([
        DefinitionRepository(api).readAll(),
        CompanyRepository(api).readAll(),
        _repo.visibility(widget.entityId),
      ]);
      final defs = results[0] as List<ProductDefinition>;
      final companies = results[1] as List;
      final vis = results[2] as DefinitionVisibility;
      if (!mounted) return;
      setState(() {
        _defs = defs;
        _companyNames = {for (final c in companies) c.id as String: c.name as String};
        _restricted = {...vis.restricted};
        _inherited = {...vis.inherited};
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  /// The SKUs the operator may toggle here (everything except ancestor-locked ones).
  Iterable<ProductDefinition> get _toggleable =>
      _defs.where((d) => !_inherited.contains(d.sku));

  Future<void> _setHidden(String sku, bool hidden) async {
    final prev = {..._restricted};
    setState(() => hidden ? _restricted.add(sku) : _restricted.remove(sku));
    try {
      await _repo.setRestricted(sku: sku, entityId: widget.entityId, restricted: hidden);
    } catch (e) {
      if (!mounted) return;
      setState(() => _restricted = prev); // revert on failure
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    }
  }

  /// Bulk: hide (or show) every toggleable definition, then reconcile with the server.
  Future<void> _setAll(bool hidden) async {
    setState(() => _busy = true);
    try {
      final targets = hidden
          ? _toggleable.where((d) => !_restricted.contains(d.sku)).map((d) => d.sku)
          : _toggleable.where((d) => _restricted.contains(d.sku)).map((d) => d.sku);
      for (final sku in targets.toList()) {
        await _repo.setRestricted(sku: sku, entityId: widget.entityId, restricted: hidden);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ar ? 'المنتجات المتاحة' : 'Visible products',
                          style: IntesharType.sans(17, color: cs.onSurface, w: FontWeight.w800)),
                      Text(widget.entityName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  ar
                      ? 'أزل العلامة لإخفاء المنتج عن هذا الحساب وكل ما تحته.'
                      : 'Untick to hide a product for this account and everything under it.',
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant),
                ),
              ),
              Flexible(child: _body(ar, cs)),
              if (!_loading && _error == null) _footer(ar),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(bool ar, ColorScheme cs) {
    if (_loading) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    if (_defs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(child: Text(ar ? 'لا توجد منتجات في الكتالوج بعد.' : 'No products in the catalog yet.',
            style: IntesharType.sans(14, color: cs.onSurfaceVariant))),
      );
    }
    // Group by company; named companies first (alpha), uncategorized last.
    final groups = <String, List<ProductDefinition>>{};
    for (final d in _defs) {
      groups.putIfAbsent(d.companyId, () => []).add(d);
    }
    String label(String id) => id.isEmpty
        ? (ar ? 'غير مصنّف' : 'Uncategorized')
        : (_companyNames[id] ?? (ar ? 'غير مصنّف' : 'Uncategorized'));
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return label(a).toLowerCase().compareTo(label(b).toLowerCase());
      });
    for (final k in keys) {
      groups[k]!.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final k in keys) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
            child: Text(label(k).toUpperCase(),
                style: IntesharType.sans(11, color: cs.onSurfaceVariant, w: FontWeight.w800)),
          ),
          for (final d in groups[k]!) _row(d, ar, cs),
        ],
      ],
    );
  }

  Widget _row(ProductDefinition d, bool ar, ColorScheme cs) {
    final inherited = _inherited.contains(d.sku);
    final visible = !inherited && !_restricted.contains(d.sku);
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: inherited ? false : visible,
      // Inherited (parent-hidden) rows are locked here — they're managed higher up.
      onChanged: (inherited || _busy) ? null : (v) => _setHidden(d.sku, !(v ?? false)),
      title: Text(d.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IntesharType.sans(13.5,
              color: inherited ? cs.onSurfaceVariant : cs.onSurface, w: FontWeight.w600)),
      subtitle: inherited
          ? Text(ar ? 'مخفي من قِبل حساب أعلى' : 'Hidden by a parent account',
              style: IntesharType.sans(11, color: cs.onSurfaceVariant))
          : Text(d.sku, style: IntesharType.mono(10.5, color: cs.onSurfaceVariant)),
      secondary: inherited ? Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant) : null,
    );
  }

  Widget _footer(bool ar) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _setAll(false),
            icon: const Icon(Icons.done_all, size: 16),
            label: Text(ar ? 'إظهار الكل' : 'Show all'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _setAll(true),
            icon: _busy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.block, size: 16),
            label: Text(ar ? 'إخفاء الكل' : 'Hide all'),
          ),
        ),
      ]),
    );
  }
}
