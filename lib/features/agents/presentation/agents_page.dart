import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/agents/data/agent_repository.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';
import 'package:inteshar/features/agents/presentation/agent_form.dart';
import 'package:inteshar/features/agents/presentation/agent_strings.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/system_activity/domain/feed_rows.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// HQ admin directory for one agent tier (Main Agents or Sub Agents). Paged,
/// searchable; create/edit via the shared [AgentForm]; delete with confirm. The
/// page is reached only on HQ routes; the backend independently enforces that
/// create/update/delete are HQ-only.
class AgentsPage extends ConsumerStatefulWidget {
  final AgentTier tier;
  const AgentsPage({super.key, required this.tier});

  @override
  ConsumerState<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends ConsumerState<AgentsPage> {
  static const _pageSize = 50;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  final List<EntitySummaryRow> _items = [];
  int _page = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  AgentTier get tier => widget.tier;

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

  AgentRepository get _repo => AgentRepository(ref.read(apiClientProvider));

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
    });
    try {
      final res = await _repo.list(tier.typeName, search: _searchCtrl.text.trim(), page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(res.items);
        _hasMore = res.hasMore;
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
      final res = await _repo.list(tier.typeName, search: _searchCtrl.text.trim(), page: next, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(res.items);
        _page = next;
        _hasMore = res.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  Future<void> _openForm({String? editId}) async {
    final repo = _repo;
    Entity? existing;
    if (editId != null) {
      try {
        existing = await repo.read(editId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        }
        return;
      }
    }
    if (!mounted) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AgentForm(tier: tier, existing: existing)),
    );
    if (ok == true) _reload();
  }

  Future<void> _confirmDelete(EntitySummaryRow row) async {
    final s = AgentStrings.of(context, tier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTitle),
        content: Text(s.deleteBody(row.label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(row.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.deleted)));
      }
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AgentStrings.of(context, tier);
    return MaxWidthBox(
      child: Column(
        children: [
          PageHeader(
            eyebrow: s.pageEyebrow,
            title: s.pageTitle,
            subtitle: s.pageSubtitle,
            trailing: FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.newAgent),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: s.searchHint,
                isDense: true,
              ),
            ),
          ),
          Expanded(child: _buildBody(s)),
        ],
      ),
    );
  }

  Widget _buildBody(AgentStrings s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _reload);
    if (_items.isEmpty) {
      return EmptyState(message: '${s.empty}\n${s.emptyHint}', actionLabel: s.newAgent, onAction: () => _openForm());
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator()
                    : OutlinedButton(onPressed: _loadMore, child: Text(s.loadMore)),
              ),
            );
          }
          return _AgentCard(
            row: _items[i],
            s: s,
            onEdit: () => _openForm(editId: _items[i].id),
            onDelete: () => _confirmDelete(_items[i]),
          );
        },
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final EntitySummaryRow row;
  final AgentStrings s;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AgentCard({required this.row, required this.s, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = s.ar ? 'ar' : 'en';
    return InkCard(
      ruleColor: IntesharColors.saffron,
      padding: const EdgeInsets.all(16),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IntesharType.sans(17, color: cs.onSurface, w: FontWeight.w800)),
                    const SizedBox(height: 3),
                    SelectableText(row.id,
                        style: IntesharType.mono(11, color: cs.onSurfaceVariant, letterSpacing: 0.3)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(s.edit)),
                  PopupMenuItem(value: 'delete', child: Text(s.delete)),
                ],
              ),
            ],
          ),
          if (row.parentName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.north_east, size: 13, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(row.parentName, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(s.coverage, style: IntesharType.overline(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (row.governorates.isEmpty)
            Text(s.noRegions, style: IntesharType.sans(12.5, color: cs.onSurfaceVariant))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: row.governorates
                  .map((c) => StampPill(label: governorateLabel(c, locale), color: IntesharColors.saffron, filled: false))
                  .toList(),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.group_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(s.usersCount(row.userCount), style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
              const SizedBox(width: 16),
              Icon(Icons.account_tree_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 5),
              Text(s.childrenCount(row.childrenCount), style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}
