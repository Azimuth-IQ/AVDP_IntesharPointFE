import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/shared/widgets/app_search_field.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// Server-searched, single-select entity picker (B-023 P1) — the shared
/// replacement for the "download every entity into a dropdown" pattern.
/// Type-to-search hits `GET /api/entity/search` (debounced, paged, tenancy
/// scoped server-side); tapping a row returns it, dismissing returns null.
///
/// [types] narrows the picker to given tiers (e.g. agents only);
/// [where] applies an extra client-side row filter (e.g. exclude self).
Future<EntitySummaryRow?> showEntitySearchPicker(
  BuildContext context, {
  required EntityRepository repository,
  String? title,
  List<EntityType>? types,
  bool Function(EntitySummaryRow row)? where,
}) {
  return showDialog<EntitySummaryRow>(
    context: context,
    builder: (_) => _EntitySearchDialog(
      repository: repository,
      title: title,
      types: types,
      where: where,
    ),
  );
}

class _PS {
  final bool ar;
  const _PS(this.ar);
  factory _PS.of(BuildContext c) =>
      _PS(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String a) => ar ? a : en;
  String get title => p('Select account', 'اختيار حساب');
  String get search => p('Search by name…', 'بحث بالاسم…');
  String get noMatches => p('No matching accounts', 'لا توجد حسابات مطابقة');
  String get loadMore => p('Load more', 'تحميل المزيد');
  String get retry => p('Retry', 'إعادة المحاولة');
  String get cancel => p('Cancel', 'إلغاء');
  String get inactive => p('Disabled', 'معطّل');
}

/// Inline, server-searched multi-select entity list (B-023 P1) — the shared
/// box behind the notification/slider targeting editors. The parent owns
/// [selectedIds]; this widget owns the debounced search + paged results and
/// reports toggles via [onToggle]. Rows checked in an earlier search stay
/// selected (the id set is independent of the visible page).
class EntityMultiSearchList extends StatefulWidget {
  const EntityMultiSearchList({
    super.key,
    required this.repository,
    required this.selectedIds,
    required this.onToggle,
    this.height = 240,
  });

  final EntityRepository repository;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggle;
  final double height;

  @override
  State<EntityMultiSearchList> createState() => _EntityMultiSearchListState();
}

class _EntityMultiSearchListState extends State<EntityMultiSearchList> {
  final List<EntitySummaryRow> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _page = 0;
  String _query = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = v.trim();
      _reload();
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.search(q: _query);
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _page = 0;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final page = await widget.repository.search(q: _query, page: next);
      if (!mounted) return;
      setState(() {
        _rows.addAll(page.items);
        _hasMore = page.hasMore;
        _page = next;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _PS.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // UX-133: the app's one search box, rather than a sixteenth variation.
        AppSearchField(
          controller: _searchCtrl,
          hintText: s.search,
          onChanged: _onSearch,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 6),
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(IntesharRadii.sm),
          ),
          child: _box(s, cs),
        ),
      ],
    );
  }

  Widget _box(_PS s, ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(friendlyError(_error!, context),
              textAlign: TextAlign.center,
              style: IntesharText.body(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _reload, child: Text(s.retry)),
        ]),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(s.noMatches,
            style: IntesharText.body(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      itemCount: _rows.length + (_hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= _rows.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: _loadMore, child: Text(s.loadMore)),
            ),
          );
        }
        final e = _rows[i];
        return CheckboxListTile(
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: widget.selectedIds.contains(e.id),
          onChanged: (v) => widget.onToggle(e.id, v ?? false),
          title: Text(e.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  IntesharText.body(
                      color: cs.onSurface, w: IntesharWeight.semibold)),
          subtitle: Text(e.type.label,
              style: IntesharText.caption(
                  color: cs.onSurfaceVariant, w: IntesharWeight.regular)),
        );
      },
    );
  }
}

class _EntitySearchDialog extends StatefulWidget {
  const _EntitySearchDialog({
    required this.repository,
    this.title,
    this.types,
    this.where,
  });

  final EntityRepository repository;
  final String? title;
  final List<EntityType>? types;
  final bool Function(EntitySummaryRow row)? where;

  @override
  State<_EntitySearchDialog> createState() => _EntitySearchDialogState();
}

class _EntitySearchDialogState extends State<_EntitySearchDialog> {
  final List<EntitySummaryRow> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;
  int _page = 0;
  String _query = '';
  Timer? _debounce;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _query = v.trim();
      _reload();
    });
  }

  List<EntitySummaryRow> _filtered(List<EntitySummaryRow> items) =>
      widget.where == null ? items : items.where(widget.where!).toList();

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page =
          await widget.repository.search(q: _query, types: widget.types);
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(_filtered(page.items));
        _hasMore = page.hasMore;
        _page = 0;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final page = await widget.repository
          .search(q: _query, types: widget.types, page: next);
      if (!mounted) return;
      setState(() {
        _rows.addAll(_filtered(page.items));
        _hasMore = page.hasMore;
        _page = next;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _PS.of(context);
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title ?? s.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppSearchField(
            controller: _searchCtrl,
            hintText: s.search,
            autofocus: true,
            onChanged: _onSearch,
            padding: EdgeInsets.zero,
          ),
          IntesharSpacing.gapSm,
          // UX-111: this was a hard SizedBox(height: 300) in a non-scrollable
          // AlertDialog column, and `autofocus` opens the keyboard on entry —
          // the content then overflowed its box and painted over the Cancel
          // button, leaving no way out. Flexible lets the list give way instead
          // (AlertDialog bounds its content, and Dialog already subtracts the
          // IME inset), while the cap keeps a tall screen from filling up.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _list(s, cs),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
      ],
    );
  }

  Widget _list(_PS s, ColorScheme cs) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(friendlyError(_error!, context),
              textAlign: TextAlign.center,
              style: IntesharText.body(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _reload, child: Text(s.retry)),
        ]),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(s.noMatches,
            style: IntesharText.body(color: cs.onSurfaceVariant)),
      );
    }
    return ListView.builder(
      itemCount: _rows.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _rows.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : OutlinedButton(
                      onPressed: _loadMore, child: Text(s.loadMore)),
            ),
          );
        }
        final r = _rows[i];
        final subtitle = [
          r.type.label,
          if (r.parentName.isNotEmpty) r.parentName,
          if (!r.active) s.inactive,
        ].join(' · ');
        return ListTile(
          dense: true,
          onTap: () => Navigator.pop(context, r),
          title: Text(r.label, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle,
              style: IntesharText.caption(
                  color: cs.onSurfaceVariant, w: IntesharWeight.regular),
              overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}
