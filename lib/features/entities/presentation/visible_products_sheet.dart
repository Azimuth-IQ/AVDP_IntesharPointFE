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
/// Returns true when at least one visibility was actually written, so the caller
/// can refresh (UX-159).
///
/// It used to return `Future<void>` while writing `setRestricted` — the only
/// sheet in the app that mutated and reported nothing. That was harmless purely
/// by accident: the hierarchy does not currently display restriction state, so
/// there was nothing on screen to go stale. The moment it does, this becomes the
/// same "panel doesn't update after I change something" the client already
/// reported. A mutating sheet says whether it mutated.
Future<bool> showVisibleProductsSheet(
  BuildContext context, {
  required String entityId,
  required String entityName,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VisibleProductsSheet(entityId: entityId, entityName: entityName),
  );
  return changed ?? false;
}

class _VisibleProductsSheet extends ConsumerStatefulWidget {
  const _VisibleProductsSheet({required this.entityId, required this.entityName});
  final String entityId;
  final String entityName;

  @override
  ConsumerState<_VisibleProductsSheet> createState() => _VisibleProductsSheetState();
}

class _VisibleProductsSheetState extends ConsumerState<_VisibleProductsSheet> {
  /// Whether any visibility was successfully written this session — the value
  /// this sheet pops with (UX-159).
  bool _changed = false;

  List<ProductDefinition> _defs = const [];
  Map<String, String> _companyNames = const {}; // companyId -> name
  Set<String> _restricted = {}; // own (editable) hidden SKUs
  Set<String> _inherited = {}; // ancestor-hidden SKUs (locked)
  bool _loading = true;
  Object? _error;

  /// UX-83: busy state is scoped to what was actually tapped, not to the sheet.
  ///
  /// [_pendingSkus] holds the rows with a write in flight — only those rows lock,
  /// and each shows its own spinner. [_bulkHiding] is the bulk action currently
  /// running (true = "Hide all", false = "Show all", null = none); it names WHICH
  /// button to spin, because a single page-wide flag put the spinner on "Hide
  /// all" even when the operator had pressed "Show all".
  final Set<String> _pendingSkus = {};
  bool? _bulkHiding;

  bool get _bulkRunning => _bulkHiding != null;

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
    setState(() {
      hidden ? _restricted.add(sku) : _restricted.remove(sku);
      _pendingSkus.add(sku);
    });
    try {
      await _repo.setRestricted(sku: sku, entityId: widget.entityId, restricted: hidden);
      _changed = true;
    } catch (e) {
      if (!mounted) return;
      setState(() => _restricted = prev); // revert on failure
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _pendingSkus.remove(sku));
    }
  }

  /// Bulk: hide (or show) every toggleable definition, then reconcile with the server.
  ///
  /// This one genuinely touches every row, so locking the list is honest here —
  /// unlike a single row's toggle, which now locks only itself.
  Future<void> _setAll(bool hidden) async {
    setState(() => _bulkHiding = hidden);
    try {
      final targets = hidden
          ? _toggleable.where((d) => !_restricted.contains(d.sku)).map((d) => d.sku)
          : _toggleable.where((d) => _restricted.contains(d.sku)).map((d) => d.sku);
      final list = targets.toList();
      for (final sku in list) {
        await _repo.setRestricted(sku: sku, entityId: widget.entityId, restricted: hidden);
      }
      // A partial run still changed something — report it, or a failure halfway
      // through would leave the caller believing nothing happened.
      if (list.isNotEmpty) _changed = true;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    } finally {
      if (mounted) setState(() => _bulkHiding = null);
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
                    onPressed: () => Navigator.pop(context, _changed),
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
    final pending = _pendingSkus.contains(d.sku);
    return CheckboxListTile(
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: inherited ? false : visible,
      // Inherited (parent-hidden) rows are locked here — they're managed higher
      // up. A row with its own write in flight locks too, but only itself.
      onChanged: (inherited || pending || _bulkRunning)
          ? null
          : (v) => _setHidden(d.sku, !(v ?? false)),
      title: Text(d.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IntesharType.sans(13.5,
              color: inherited ? cs.onSurfaceVariant : cs.onSurface, w: FontWeight.w600)),
      subtitle: inherited
          ? Text(ar ? 'مخفي من قِبل حساب أعلى' : 'Hidden by a parent account',
              style: IntesharType.sans(11, color: cs.onSurfaceVariant))
          : Text(d.sku, style: IntesharType.mono(10.5, color: cs.onSurfaceVariant)),
      // The spinner belongs on the row that was tapped — that is the whole point
      // of scoping the busy state.
      secondary: pending
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : inherited
              ? Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant)
              : null,
    );
  }

  Widget _footer(bool ar) {
    // Each button spins only for its OWN action; both disable while either runs,
    // because they contradict each other.
    Widget icon(bool hiding, IconData rest) => _bulkHiding == hiding
        ? const SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(rest, size: 16);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _bulkRunning ? null : () => _setAll(false),
            icon: icon(false, Icons.done_all),
            label: Text(ar ? 'إظهار الكل' : 'Show all'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _bulkRunning ? null : () => _setAll(true),
            icon: icon(true, Icons.block),
            label: Text(ar ? 'إخفاء الكل' : 'Hide all'),
          ),
        ),
      ]),
    );
  }
}
