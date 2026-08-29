import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/notifications/application/notification_provider.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/sheet_frame.dart';

// ─── Local strings (inline ar/en — no .arb dependency) ───────────────────────

class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) =>
      _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('Messages', 'الرسائل');
  String get title => p('Notifications', 'الإشعارات');
  String get subtitle =>
      p('Messages from headquarters', 'رسائل من المقر الرئيسي');
  String get empty => p('No notifications yet', 'لا توجد إشعارات بعد');
  String get emptyHint =>
      p('You will receive messages from HQ here.',
          'ستصلك الرسائل من المقر الرئيسي هنا.');
  String get loadMore => p('Load more', 'تحميل المزيد');
  String unreadCount(int n) => p('$n unread', '$n غير مقروء');
  String get audienceAll => p('Everyone', 'الجميع');
  String audienceTier(String tier) =>
      p('Group: $tier', 'مجموعة: $tier');
  String audienceEntity(String name) =>
      p('Direct: $name', 'مباشر: $name');
  String get from => p('From', 'من');
  String get to => p('To', 'إلى');
  String get sent => p('Sent', 'أُرسل');
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class NotificationsInboxPage extends ConsumerStatefulWidget {
  const NotificationsInboxPage({super.key});

  @override
  ConsumerState<NotificationsInboxPage> createState() =>
      _NotificationsInboxPageState();
}

class _NotificationsInboxPageState
    extends ConsumerState<NotificationsInboxPage> {
  List<AppNotification> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 0;
  Object? _error;

  NotificationRepository get _repo =>
      NotificationRepository(ref.read(apiClientProvider));

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
      final paged = await _repo.inbox(page: 0);
      if (!mounted) return;
      setState(() {
        _items = paged.items;
        _page = 0;
        _hasMore = paged.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final paged = await _repo.inbox(page: next);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...paged.items];
        _page = next;
        _hasMore = paged.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead || n.id.isEmpty) return;
    try {
      await _repo.markRead(n.id);
      if (!mounted) return;
      // Optimistic update: flip the local item immediately.
      setState(() {
        _items = [
          for (final item in _items)
            item.id == n.id ? item.copyWith(isRead: true) : item,
        ];
      });
      // Refresh the nav-badge provider so the badge count decrements.
      ref.invalidate(notificationsUnreadCountProvider);
    } catch (_) {
      // Silent: leave the item in its current read state.
    }
  }

  void _openDetail(AppNotification n) {
    // Mark as read when the detail sheet opens (best-effort).
    _markRead(n);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetailSheet(n: n),
    );
  }

  int get _unreadCount => _items.where((n) => !n.isRead).length;

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && _items.isEmpty) {
      body = ErrorState(error: _error!, onRetry: _load);
    } else if (_items.isEmpty) {
      body = EmptyState(message: '${s.empty}\n${s.emptyHint}');
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding:
              const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 32),
          itemCount: _items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: IntesharSpacing.sm2),
          itemBuilder: (ctx, i) {
            if (i == _items.length) {
              if (!_hasMore) return const SizedBox(height: IntesharSpacing.xs);
              return Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Center(
                  child: _loadingMore
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : OutlinedButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: Text(s.loadMore),
                        ),
                ),
              );
            }
            return _NotifCard(
              n: _items[i],
              s: s,
              onTap: () => _openDetail(_items[i]),
            );
          },
        ),
      );
    }

    return MaxWidthBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            eyebrow: s.eyebrow,
            title: s.title,
            subtitle: s.subtitle,
            trailing: IconButton.filledTonal(
              tooltip: s.title,
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ),
          // ── Unread banner — shown when there are unread items ──────────
          if (!_loading && _unreadCount > 0)
            Padding(
              padding:
                  const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
              child: NotificationsUnreadBanner(count: _unreadCount, label: s.unreadCount(_unreadCount)),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

// ─── Unread banner ────────────────────────────────────────────────────────────

/// Standalone gold banner showing an unread count. Can be embedded in the
/// inbox page header or exported into any role's scaffold (e.g. shown below
/// the navigation rail when [notificationsUnreadCountProvider] > 0).
class NotificationsUnreadBanner extends StatelessWidget {
  final int count;
  final String label;
  const NotificationsUnreadBanner({
    super.key,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: IntesharSpacing.md, vertical: IntesharSpacing.sm2),
      decoration: BoxDecoration(
        color: context.tones.brand.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(
          color: context.tones.brand.withValues(alpha: 0.36),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_outlined,
            size: 18,
            color: context.tones.brandInk,
          ),
          const SizedBox(width: IntesharSpacing.sm2),
          Expanded(
            child: Text(
              label,
              style: IntesharType.sans(
                14,
                color: context.tones.brandInk,
                w: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Notification card ────────────────────────────────────────────────────────

class _NotifCard extends StatelessWidget {
  final AppNotification n;
  final _S s;
  final VoidCallback onTap;
  const _NotifCard({
    required this.n,
    required this.s,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = !n.isRead;
    return InkCard(
      ruleColor: unread ? context.tones.brand : null,
      density: CardDensity.dense,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (unread
                      ? context.tones.brand
                      : cs.onSurfaceVariant)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              unread
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_outlined,
              size: 18,
              color: unread
                  ? context.tones.brandInk
                  : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: IntesharSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(
                    14,
                    color: cs.onSurface,
                    w: unread ? FontWeight.w800 : IntesharWeight.semibold,
                  ),
                ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: IntesharSpacing.xs),
                  Text(
                    n.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: IntesharType.sans(
                      12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: IntesharSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.tones.brandInk,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              if (n.sentAt != null) ...[
                const SizedBox(height: IntesharSpacing.xs),
                Text(
                  DateFormat('MM-dd HH:mm').format(n.sentAt!),
                  style: IntesharType.mono(
                    11,
                    color: IntesharColors.lichen,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Detail bottom sheet ─────────────────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final AppNotification n;
  const _DetailSheet({required this.n});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
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

    // UX-131: this sheet hand-rolled its own shell — a third max-height (0.75),
    // an off-scale 22 title and a re-typed copy of the brand rule — while the
    // call site already asks the framework for the grab handle. The shared
    // frame owns all of that now (`handle: false` so there is exactly one pill).
    return SheetFrame(
      handle: false,
      title: n.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            n.body,
            style: IntesharText.title(
              color: cs.onSurface,
              w: IntesharWeight.regular,
              height: 1.55,
            ),
          ),
          IntesharSpacing.gapXl,
          if (n.senderName.isNotEmpty) _kvRow(context, s.from, n.senderName),
          _kvRow(context, s.to, audienceValue()),
          if (n.sentAt != null)
            _kvRow(
              context,
              s.sent,
              DateFormat('yyyy-MM-dd HH:mm').format(n.sentAt!),
            ),
        ],
      ),
    );
  }
}

// ─── Shared kv row ────────────────────────────────────────────────────────────

Widget _kvRow(BuildContext context, String label, String value) {
  final cs = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: IntesharSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: IntesharType.sans(
              12,
              color: cs.onSurfaceVariant,
              w: IntesharWeight.semibold,
            ),
          ),
        ),
        const SizedBox(width: IntesharSpacing.md),
        Expanded(
          child: Text(
            value,
            style: IntesharType.sans(
              14,
              color: cs.onSurface,
              w: IntesharWeight.regular,
            ),
          ),
        ),
      ],
    ),
  );
}
