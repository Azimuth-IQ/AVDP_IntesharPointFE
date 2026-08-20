import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_dependents.dart';
import 'package:inteshar/features/entities/presentation/confirm_code_dialog.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// Opens the clear-out sheet for [entityId].
///
/// Returns true when ANYTHING was deleted — the account itself, or any of the
/// shops and sub-agents cleared out on the way there.
///
/// It deliberately does not mean "the account is gone". Clearing three shops and
/// then closing the sheet used to return false, so the hierarchy behind it kept
/// listing all three and the operator reasonably concluded the deletes had
/// failed. The caller's only question is "should I refresh?", so that is what
/// this answers.
Future<bool> showDeleteAgentSheet(
  BuildContext context,
  WidgetRef ref, {
  required String entityId,
  required String entityName,
}) async {
  // Tracked out here because the sheet can also be dismissed by the scrim, the
  // drag handle or the back gesture, none of which pop a result.
  var changed = false;
  final deleted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DeleteAgentSheet(
      entityId: entityId,
      entityName: entityName,
      onChanged: () => changed = true,
    ),
  );
  return deleted ?? changed;
}

/// Shows everything still attached to an account and lets it be cleared in the
/// order the server will accept.
///
/// Deleting is leaf-only, so an agent holding sub-agents and shops cannot go
/// until they do. A bare "you can't delete this" leaves the operator to work out
/// what is attached and where it lives; this shows the list, deletes each item
/// on the spot, and unlocks the account itself once nothing is left.
///
/// This class owns the I/O only — [DeleteAgentSheetBody] is the whole picture,
/// so the visuals can be previewed and pumped in a test without a server.
class DeleteAgentSheet extends ConsumerStatefulWidget {
  final String entityId;
  final String entityName;

  /// Fired after every successful deletion, so the caller can refresh even when
  /// the operator clears children and then dismisses without deleting the
  /// account itself.
  final VoidCallback? onChanged;

  const DeleteAgentSheet({
    super.key,
    required this.entityId,
    required this.entityName,
    this.onChanged,
  });

  @override
  ConsumerState<DeleteAgentSheet> createState() => _DeleteAgentSheetState();
}

class _DeleteAgentSheetState extends ConsumerState<DeleteAgentSheet> {
  EntityDependents? _deps;
  Object? _error;
  bool _loading = true;

  /// Ids currently being deleted — keeps a row from being fired twice and shows
  /// where the work is happening.
  final Set<String> _busy = {};

  bool get _isAr => _localeCode == 'ar';
  String get _localeCode => Localizations.localeOf(context).languageCode;

  EntityRepository get _entities => EntityRepository(ref.read(apiClientProvider));
  PosAdminRepository get _pos => PosAdminRepository(ref.read(apiClientProvider));

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
      final deps = await _entities.dependents(widget.entityId);
      if (mounted) setState(() => _deps = deps);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _t(String ar, String en) => _isAr ? ar : en;

  /// Prefer the server's own words — "Remove its 3 points of sale first" or
  /// "that code is not valid" is the whole reason the operator is here.
  void _reportFailure(Object e) {
    if (!mounted) return;
    _snack(serverReason(e) ?? friendlyError(e, context));
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _deleteStore(DependentStore store) async {
    final code = await showConfirmCodeDialog(
      context,
      title: _t('حذف نقطة البيع', 'Delete point of sale'),
      warning: _t(
        'سيتم حذف "${store.name}" وحساب المشغّل وسجلها نهائياً. لا يمكن التراجع.',
        'This permanently deletes "${store.name}", its operator login and its '
            'history. It cannot be undone.',
      ),
    );
    if (code == null || !mounted) return;

    setState(() => _busy.add(store.id));
    try {
      final phone = store.operatorPhone;
      if (phone != null && phone.isNotEmpty) {
        // The revoke path returns the POS slot to the host agent; a plain entity
        // delete would leave the host's quota counter short by one.
        await _pos.revoke(
            entityId: store.id, phone: phone, totp: code);
      } else {
        // A shop with no operator cannot be revoked by phone; it is a leaf, so a
        // direct delete is correct.
        await _entities.delete(store.id, totp: code);
      }
      _snack(_t('تم حذف نقطة البيع', 'Point of sale deleted'));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      _reportFailure(e);
    } finally {
      if (mounted) setState(() => _busy.remove(store.id));
    }
  }

  Future<void> _deleteSubAgent(DependentSubAgent sub) async {
    final code = await showConfirmCodeDialog(
      context,
      title: _t('حذف الوكيل الفرعي', 'Delete sub-agent'),
      warning: _t(
        'سيتم حذف "${sub.name}" وحساباته نهائياً. لا يمكن التراجع.',
        'This permanently deletes "${sub.name}" and its accounts. '
            'It cannot be undone.',
      ),
    );
    if (code == null || !mounted) return;

    setState(() => _busy.add(sub.id));
    try {
      await _entities.delete(sub.id, totp: code);
      _snack(_t('تم حذف الوكيل الفرعي', 'Sub-agent deleted'));
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      _reportFailure(e);
    } finally {
      if (mounted) setState(() => _busy.remove(sub.id));
    }
  }

  Future<void> _deleteTheAgent() async {
    final code = await showConfirmCodeDialog(
      context,
      title: _t('حذف الحساب', 'Delete the account'),
      warning: _t(
        'سيتم حذف "${widget.entityName}" نهائياً. لا يمكن التراجع.',
        'This permanently deletes "${widget.entityName}". It cannot be undone.',
      ),
    );
    if (code == null || !mounted) return;

    setState(() => _busy.add(widget.entityId));
    try {
      await _entities.delete(widget.entityId, totp: code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _reportFailure(e);
      await _load(); // the blockers may have changed under us
    } finally {
      if (mounted) setState(() => _busy.remove(widget.entityId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DeleteAgentSheetBody(
      entityName: widget.entityName,
      entityId: widget.entityId,
      dependents: _deps,
      loading: _loading,
      error: _error,
      busyIds: _busy,
      onRetry: _load,
      onDeleteStore: _deleteStore,
      onDeleteSubAgent: _deleteSubAgent,
      onDeleteSelf: _deleteTheAgent,
    );
  }
}

/// The whole visual surface, with no I/O — every state it can be in is decided
/// by its inputs, so it can be previewed and pumped in a test.
///
/// Points of sale are listed FIRST because that is where the sequence starts: a
/// sub-agent still holding shops cannot be deleted either.
class DeleteAgentSheetBody extends StatelessWidget {
  final String entityName;
  final String entityId;
  final EntityDependents? dependents;
  final bool loading;
  final Object? error;
  final Set<String> busyIds;
  final VoidCallback onRetry;
  final ValueChanged<DependentStore> onDeleteStore;
  final ValueChanged<DependentSubAgent> onDeleteSubAgent;
  final VoidCallback onDeleteSelf;

  const DeleteAgentSheetBody({
    super.key,
    required this.entityName,
    required this.entityId,
    required this.dependents,
    required this.loading,
    required this.error,
    required this.busyIds,
    required this.onRetry,
    required this.onDeleteStore,
    required this.onDeleteSubAgent,
    required this.onDeleteSelf,
  });

  bool _isAr(BuildContext c) => Localizations.localeOf(c).languageCode == 'ar';
  String _t(BuildContext c, String ar, String en) => _isAr(c) ? ar : en;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deps = dependents;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(_t(context, 'حذف حساب', 'Delete account')),
              Text(entityName,
                  style: IntesharType.display(24, color: cs.onSurface)),
              // Only while there IS a list to clear — repeating the instruction
              // over an empty, already-unlocked sheet reads as a refusal.
              if (deps != null && !deps.deletable) ...[
                const SizedBox(height: 4),
                Text(
                  _t(
                    context,
                    'لا يمكن حذف حساب ما دامت تتبعه حسابات أخرى. احذف ما يلي أولاً.',
                    'An account cannot be deleted while other accounts hang off '
                        'it. Clear the list below first.',
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 16),
              if (loading && deps == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (error != null)
                _errorBlock(context, cs)
              else if (deps != null) ...[
                _progress(context, deps, cs),
                const SizedBox(height: 12),
                Flexible(child: _dependentsList(context, deps, cs)),
                const SizedBox(height: 12),
                _finalAction(context, deps, cs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBlock(BuildContext context, ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          Text(friendlyError(error, context), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('deleteAgentRetry'),
            onPressed: onRetry,
            child: Text(_t(context, 'إعادة المحاولة', 'Try again')),
          ),
        ]),
      );

  /// One honest line: what is left, and whether the account is unlocked yet.
  Widget _progress(BuildContext context, EntityDependents deps, ColorScheme cs) {
    final done = deps.deletable;
    final parts = <String>[
      if (deps.subAgentCount > 0)
        _t(context, '${deps.subAgentCount} وكيل فرعي',
            '${deps.subAgentCount} sub-agents'),
      if (deps.storeCount > 0)
        _t(context, '${deps.storeCount} نقطة بيع',
            '${deps.storeCount} points of sale'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: done ? cs.primaryContainer : cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(done ? Icons.check_circle_outline : Icons.info_outline,
            size: 18, color: done ? cs.onPrimaryContainer : cs.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            done
                ? _t(context, 'لا توجد حسابات تابعة — يمكن الحذف الآن.',
                    'Nothing is attached — this can be deleted now.')
                : _t(context, 'متبقٍ: ${parts.join(' و ')}',
                    'Still attached: ${parts.join(' and ')}'),
            style: TextStyle(
                color: done ? cs.onPrimaryContainer : cs.onErrorContainer,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }

  Widget _dependentsList(
      BuildContext context, EntityDependents deps, ColorScheme cs) {
    if (deps.deletable) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (deps.stores.isNotEmpty) ...[
            SectionLabel(_t(context, 'نقاط البيع', 'Points of sale')),
            ...deps.stores.map((s) => _storeRow(context, s, cs)),
            const SizedBox(height: 8),
          ],
          if (deps.subAgents.isNotEmpty) ...[
            SectionLabel(_t(context, 'الوكلاء الفرعيون', 'Sub-agents')),
            ...deps.subAgents.map((s) => _subAgentRow(context, s, cs)),
          ],
        ],
      ),
    );
  }

  Widget _storeRow(BuildContext context, DependentStore store, ColorScheme cs) {
    final locale = Localizations.localeOf(context).languageCode;
    final busy = busyIds.contains(store.id);
    final subtitle = [
      if ((store.hostName ?? '').isNotEmpty)
        _t(context, 'تحت ${store.hostName}', 'under ${store.hostName}'),
      if ((store.governorate ?? '').isNotEmpty)
        governorateLabel(store.governorate!, locale),
      if ((store.operatorPhone ?? '').isNotEmpty) store.operatorPhone!,
    ].join(' · ');

    return _row(
      context: context,
      icon: Icons.storefront_outlined,
      title: store.name,
      subtitle: subtitle,
      busy: busy,
      onDelete: busy ? null : () => onDeleteStore(store),
      cs: cs,
    );
  }

  Widget _subAgentRow(
      BuildContext context, DependentSubAgent sub, ColorScheme cs) {
    final locale = Localizations.localeOf(context).languageCode;
    final busy = busyIds.contains(sub.id);
    final blocked = !sub.isDeletable;
    final subtitle = [
      if ((sub.governorate ?? '').isNotEmpty)
        governorateLabel(sub.governorate!, locale),
      if (blocked)
        _t(context, '${sub.storeCount} نقطة بيع يجب حذفها أولاً',
            '${sub.storeCount} points of sale must go first'),
    ].join(' · ');

    return _row(
      context: context,
      icon: Icons.account_tree_outlined,
      title: sub.name,
      subtitle: subtitle,
      busy: busy,
      // Disabled rather than hidden: the operator can see it is next, and why it
      // is not available yet.
      onDelete: (busy || blocked) ? null : () => onDeleteSubAgent(sub),
      cs: cs,
    );
  }

  Widget _row({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback? onDelete,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cs.onSurface)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        if (busy)
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          IconButton(
            onPressed: onDelete,
            tooltip: _t(context, 'حذف', 'Delete'),
            icon: Icon(Icons.delete_outline,
                color: onDelete == null ? cs.outline : cs.error),
          ),
      ]),
    );
  }

  Widget _finalAction(
      BuildContext context, EntityDependents deps, ColorScheme cs) {
    final busy = busyIds.contains(entityId);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const Key('deleteAgentFinalAction'),
        style: FilledButton.styleFrom(
          backgroundColor:
              deps.deletable ? cs.error : cs.surfaceContainerHighest,
          foregroundColor: deps.deletable ? cs.onError : cs.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onPressed: (!deps.deletable || busy) ? null : onDeleteSelf,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.delete_forever_outlined, size: 18),
        label: Text(deps.deletable
            ? _t(context, 'حذف $entityName', 'Delete $entityName')
            : _t(context, 'احذف الحسابات التابعة أولاً',
                'Clear the attached accounts first')),
      ),
    );
  }
}
