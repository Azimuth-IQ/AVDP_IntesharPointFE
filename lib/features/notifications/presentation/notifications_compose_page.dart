import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

// ─── Local strings (inline ar/en — no .arb dependency) ───────────────────────

class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) =>
      _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('HQ', 'المقر الرئيسي');
  String get title => p('Notifications', 'الإشعارات');
  String get subtitle =>
      p('Compose and broadcast messages to agents and stores',
          'اكتب رسائل وأرسلها للوكلاء والمتاجر');

  // Compose form
  String get composeHeading => p('New Notification', 'إشعار جديد');
  String get fieldTitle => p('Title', 'العنوان');
  String get fieldBody => p('Message', 'الرسالة');
  String get audienceLabel => p('Send to', 'إرسال إلى');
  String get optAll => p('Everyone', 'الجميع');
  String get optAgent1 => p('Main Agents', 'الوكلاء الرئيسيون');
  String get optAgent2 => p('Sub Agents', 'الوكلاء الفرعيون');
  String get optStore => p('Stores', 'المتاجر');
  String get optEntity => p('Specific Entity', 'كيان محدد');
  String get entityIdField => p('Entity ID', 'معرف الكيان');
  String get sendBtn => p('Send Notification', 'إرسال الإشعار');
  String get errTitle => p('Title is required', 'العنوان مطلوب');
  String get errBody => p('Message is required', 'الرسالة مطلوبة');
  String get errEntityId =>
      p('Entity ID is required for a specific audience',
          'معرف الكيان مطلوب لجمهور محدد');
  String get successMsg => p('Notification sent!', 'تم إرسال الإشعار!');

  // History section
  String get historyLabel => p('Sent notifications', 'الإشعارات المرسلة');
  String get historyEmpty =>
      p('No notifications have been sent yet.',
          'لم يُرسل أي إشعار بعد.');
  String get loadMore => p('Load more', 'تحميل المزيد');
  String get audienceAll => p('Everyone', 'الجميع');
  String audienceTier(String tier) =>
      p('Group: $tier', 'مجموعة: $tier');
  String audienceEntity(String name) =>
      p('Direct: $name', 'مباشر: $name');
}

// ─── Audience option ──────────────────────────────────────────────────────────

enum _AudienceOpt { all, agent1, agent2, store, entity }

extension _AudienceOptX on _AudienceOpt {
  String get audienceType => switch (this) {
        _AudienceOpt.entity => 'ENTITY',
        _AudienceOpt.all => 'ALL',
        _ => 'TIER',
      };

  String get audienceTier => switch (this) {
        _AudienceOpt.agent1 => 'AGENT1',
        _AudienceOpt.agent2 => 'AGENT2',
        _AudienceOpt.store => 'STORE',
        _ => '',
      };

  String label(_S s) => switch (this) {
        _AudienceOpt.all => s.optAll,
        _AudienceOpt.agent1 => s.optAgent1,
        _AudienceOpt.agent2 => s.optAgent2,
        _AudienceOpt.store => s.optStore,
        _AudienceOpt.entity => s.optEntity,
      };
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class NotificationsComposePage extends ConsumerStatefulWidget {
  const NotificationsComposePage({super.key});

  @override
  ConsumerState<NotificationsComposePage> createState() =>
      _NotificationsComposePageState();
}

class _NotificationsComposePageState
    extends ConsumerState<NotificationsComposePage> {
  // ── Compose form state ────────────────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _entityIdCtrl = TextEditingController();
  _AudienceOpt _audience = _AudienceOpt.all;
  bool _sending = false;
  String? _formError;

  // ── History state ─────────────────────────────────────────────────────────
  List<AppNotification> _history = [];
  bool _historyLoading = true;
  bool _historyLoadingMore = false;
  bool _historyHasMore = false;
  int _historyPage = 0;
  Object? _historyError;

  NotificationRepository get _repo =>
      NotificationRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _entityIdCtrl.dispose();
    super.dispose();
  }

  // ── History loaders ───────────────────────────────────────────────────────

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final paged = await _repo.inbox(page: 0);
      if (!mounted) return;
      setState(() {
        _history = paged.items;
        _historyPage = 0;
        _historyHasMore = paged.hasMore;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e;
        _historyLoading = false;
      });
    }
  }

  Future<void> _loadHistoryMore() async {
    if (_historyLoadingMore || !_historyHasMore) return;
    setState(() => _historyLoadingMore = true);
    try {
      final next = _historyPage + 1;
      final paged = await _repo.inbox(page: next);
      if (!mounted) return;
      setState(() {
        _history = [..._history, ...paged.items];
        _historyPage = next;
        _historyHasMore = paged.hasMore;
        _historyLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _historyLoadingMore = false);
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final s = _S.of(context);
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final entityId = _entityIdCtrl.text.trim();

    if (title.isEmpty) {
      setState(() => _formError = s.errTitle);
      return;
    }
    if (body.isEmpty) {
      setState(() => _formError = s.errBody);
      return;
    }
    if (_audience == _AudienceOpt.entity && entityId.isEmpty) {
      setState(() => _formError = s.errEntityId);
      return;
    }

    setState(() {
      _sending = true;
      _formError = null;
    });
    try {
      await _repo.send(
        title: title,
        body: body,
        audienceType: _audience.audienceType,
        audienceTier: _audience.audienceTier,
        audienceEntityId: entityId,
      );
      if (!mounted) return;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      _entityIdCtrl.clear();
      setState(() {
        _sending = false;
        _audience = _AudienceOpt.all;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.successMsg),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Reload history so the new notification appears at the top.
      _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _formError = friendlyError(e, context);
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return MaxWidthBox(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              eyebrow: s.eyebrow,
              title: s.title,
              subtitle: s.subtitle,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
              child: _ComposeCard(
                s: s,
                titleCtrl: _titleCtrl,
                bodyCtrl: _bodyCtrl,
                entityIdCtrl: _entityIdCtrl,
                audience: _audience,
                onAudienceChange: (v) => setState(() => _audience = v),
                sending: _sending,
                formError: _formError,
                onSend: _send,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 12),
              child: SectionLabel(
                s.historyLabel,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          ..._historySliver(s),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _historySliver(_S s) {
    if (_historyLoading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_historyError != null && _history.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: ErrorState(
            error: _historyError!,
            onRetry: _loadHistory,
          ),
        ),
      ];
    }
    if (_history.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: EmptyState(message: s.historyEmpty),
        ),
      ];
    }
    return [
      SliverPadding(
        padding:
            const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
        sliver: SliverList.separated(
          itemCount: _history.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) =>
              _HistoryCard(n: _history[i], s: s),
        ),
      ),
      if (_historyHasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Center(
              child: _historyLoadingMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadHistoryMore,
                      icon: const Icon(Icons.expand_more, size: 18),
                      label: Text(s.loadMore),
                    ),
            ),
          ),
        ),
    ];
  }
}

// ─── Compose card ─────────────────────────────────────────────────────────────

class _ComposeCard extends StatelessWidget {
  final _S s;
  final TextEditingController titleCtrl;
  final TextEditingController bodyCtrl;
  final TextEditingController entityIdCtrl;
  final _AudienceOpt audience;
  final ValueChanged<_AudienceOpt> onAudienceChange;
  final bool sending;
  final String? formError;
  final VoidCallback onSend;

  const _ComposeCard({
    required this.s,
    required this.titleCtrl,
    required this.bodyCtrl,
    required this.entityIdCtrl,
    required this.audience,
    required this.onAudienceChange,
    required this.sending,
    required this.onSend,
    this.formError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      ruleColor: IntesharColors.saffron,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.composeHeading,
            style: IntesharType.sans(
              15,
              color: cs.onSurface,
              w: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: titleCtrl,
            decoration: InputDecoration(labelText: s.fieldTitle),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: bodyCtrl,
            decoration: InputDecoration(labelText: s.fieldBody),
            maxLines: 4,
            minLines: 3,
            textInputAction: TextInputAction.newline,
          ),
          const SizedBox(height: 14),
          Text(
            s.audienceLabel,
            style: IntesharType.sans(
              12,
              color: IntesharColors.inkSoft,
              w: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _AudienceOpt.values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _AudienceChip(
                    label: _AudienceOpt.values[i].label(s),
                    selected: audience == _AudienceOpt.values[i],
                    onTap: () => onAudienceChange(_AudienceOpt.values[i]),
                  ),
                ],
              ],
            ),
          ),
          if (audience == _AudienceOpt.entity) ...[
            const SizedBox(height: 12),
            TextField(
              controller: entityIdCtrl,
              decoration: InputDecoration(labelText: s.entityIdField),
              textInputAction: TextInputAction.done,
            ),
          ],
          if (formError != null) ...[
            const SizedBox(height: 10),
            Text(
              formError!,
              style: IntesharType.sans(12.5, color: cs.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.send_outlined, size: 18),
            label: Text(s.sendBtn),
          ),
        ],
      ),
    );
  }
}

// ─── Audience chip ────────────────────────────────────────────────────────────

class _AudienceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AudienceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected
        ? IntesharColors.saffron.withValues(alpha: 0.16)
        : cs.surfaceContainerHighest;
    final fg =
        selected ? IntesharColors.saffronDeep : cs.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: IntesharType.sans(
              12.5,
              color: fg,
              w: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── History card ─────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final AppNotification n;
  final _S s;
  const _HistoryCard({required this.n, required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String audienceValue() {
      if (n.audienceType == 'TIER') return s.audienceTier(n.audienceTier);
      if (n.audienceType == 'ENTITY') {
        final label = n.audienceEntityName.isNotEmpty
            ? n.audienceEntityName
            : n.audienceEntityId;
        return s.audienceEntity(label);
      }
      return s.audienceAll;
    }

    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(
                    14,
                    color: cs.onSurface,
                    w: FontWeight.w700,
                  ),
                ),
              ),
              if (n.sentAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  DateFormat('MM-dd HH:mm').format(n.sentAt!),
                  style: IntesharType.mono(
                    10,
                    color: IntesharColors.lichen,
                  ),
                ),
              ],
            ],
          ),
          if (n.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              n.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          StampPill(
            label: audienceValue(),
            color: IntesharColors.saffron,
            icon: Icons.people_outline,
            fontSize: 10,
          ),
        ],
      ),
    );
  }
}
