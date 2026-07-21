import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/shared/widgets/empty_state.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

// ─── Local strings (inline ar/en) ────────────────────────────────────────────
class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) => _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String arT) => ar ? arT : en;

  String get eyebrow => p('HQ', 'المقر الرئيسي');
  String get title => p('Notifications', 'الإشعارات');
  String get subtitle => p('Compose and broadcast messages to agents and stores', 'اكتب رسائل وأرسلها للوكلاء والمتاجر');
  String get composeHeading => p('New Notification', 'إشعار جديد');
  String get kindLabel => p('Kind', 'النوع');
  String get kindNotification => p('Notification', 'إشعار');
  String get kindAlert => p('Alert', 'تنبيه');
  String get fieldTitle => p('Title', 'العنوان');
  String get fieldBody => p('Message', 'الرسالة');
  String get audienceLabel => p('Send to', 'إرسال إلى');
  String get modeAll => p('Everyone', 'الجميع');
  String get modeType => p('By type', 'حسب النوع');
  String get modeEntity => p('Specific entities', 'كيانات محددة');
  String get typeHq => p('HQ', 'المقر');
  String get typeAgent1 => p('Main Agents', 'الوكلاء الرئيسيون');
  String get typeAgent2 => p('Sub Agents', 'الوكلاء الفرعيون');
  String get typeStore => p('Stores', 'المتاجر');
  String get posOnly => p('POS operators only', 'مستخدمو نقاط البيع فقط');
  String get posOnlyHint => p('Only POS users within the scope receive it', 'يصل فقط لمستخدمي نقاط البيع ضمن النطاق');
  String get searchHint => p('Search entities…', 'ابحث عن الكيانات…');
  String selected(int n) => p('$n selected', '$n محدد');
  String get sendBtn => p('Send Notification', 'إرسال الإشعار');
  String get errTitle => p('Title is required', 'العنوان مطلوب');
  String get errBody => p('Message is required', 'الرسالة مطلوبة');
  String get errTypes => p('Pick at least one type', 'اختر نوعًا واحدًا على الأقل');
  String get errEntities => p('Pick at least one entity', 'اختر كيانًا واحدًا على الأقل');
  String get successMsg => p('Notification sent!', 'تم إرسال الإشعار!');
  String get historyLabel => p('Sent notifications', 'الإشعارات المرسلة');
  String get historyEmpty => p('No notifications have been sent yet.', 'لم يُرسل أي إشعار بعد.');
  String get loadMore => p('Load more', 'تحميل المزيد');
  String get toEveryone => p('Everyone', 'الجميع');
  String get posBadge => p('POS only', 'نقاط البيع فقط');

  String tierLabel(String t) => switch (t) {
        'INTESHAR' => typeHq,
        'AGENT1' => typeAgent1,
        'AGENT2' => typeAgent2,
        'STORE' => typeStore,
        _ => t,
      };
}

const _tierOptions = [
  ('INTESHAR', 'typeHq'),
  ('AGENT1', 'typeAgent1'),
  ('AGENT2', 'typeAgent2'),
  ('STORE', 'typeStore'),
];

// ─── Page ─────────────────────────────────────────────────────────────────────
class NotificationsComposePage extends ConsumerStatefulWidget {
  const NotificationsComposePage({super.key});
  @override
  ConsumerState<NotificationsComposePage> createState() => _NotificationsComposePageState();
}

class _NotificationsComposePageState extends ConsumerState<NotificationsComposePage> {
  List<AppNotification> _history = [];
  bool _historyLoading = true;
  bool _historyLoadingMore = false;
  bool _historyHasMore = false;
  int _historyPage = 0;
  Object? _historyError;

  NotificationRepository get _repo => NotificationRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

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
      if (mounted) setState(() { _historyError = e; _historyLoading = false; });
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
      if (mounted) setState(() => _historyLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return MaxWidthBox(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
              child: _ComposeCard(s: s, onSent: _loadHistory),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 12),
              child: SectionLabel(s.historyLabel, padding: EdgeInsets.zero),
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
      return [const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())))];
    }
    if (_historyError != null && _history.isEmpty) {
      return [SliverToBoxAdapter(child: ErrorState(error: _historyError!, onRetry: _loadHistory))];
    }
    if (_history.isEmpty) {
      return [SliverToBoxAdapter(child: EmptyState(message: s.historyEmpty))];
    }
    return [
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
        sliver: SliverList.separated(
          itemCount: _history.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => _HistoryCard(n: _history[i], s: s),
        ),
      ),
      if (_historyHasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Center(
              child: _historyLoadingMore
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : OutlinedButton.icon(onPressed: _loadHistoryMore, icon: const Icon(Icons.expand_more, size: 18), label: Text(s.loadMore)),
            ),
          ),
        ),
    ];
  }
}

// ─── Compose card (owns the recipient picker) ─────────────────────────────────
enum _Mode { all, type, entity }

class _ComposeCard extends ConsumerStatefulWidget {
  final _S s;
  final VoidCallback onSent;
  const _ComposeCard({required this.s, required this.onSent});
  @override
  ConsumerState<_ComposeCard> createState() => _ComposeCardState();
}

class _ComposeCardState extends ConsumerState<_ComposeCard> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  _Mode _mode = _Mode.all;
  bool _isAlert = false; // B-060: send as an ALERT (banner) vs a NOTIFICATION (inbox)
  final Set<String> _types = {}; // EntityType names
  final Set<String> _entityIds = {};
  bool _posOnly = false;

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = widget.s;
    if (_titleCtrl.text.trim().isEmpty) return setState(() => _error = s.errTitle);
    if (_bodyCtrl.text.trim().isEmpty) return setState(() => _error = s.errBody);
    if (_mode == _Mode.type && _types.isEmpty) return setState(() => _error = s.errTypes);
    if (_mode == _Mode.entity && _entityIds.isEmpty) return setState(() => _error = s.errEntities);

    setState(() { _sending = true; _error = null; });
    try {
      await NotificationRepository(ref.read(apiClientProvider)).send(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        audienceType: switch (_mode) { _Mode.all => 'ALL', _Mode.type => 'TIER', _Mode.entity => 'ENTITY' },
        tierTypes: _types.toList(),
        entityIds: _entityIds.toList(),
        posOnly: _posOnly,
        type: _isAlert ? 'ALERT' : 'NOTIFICATION',
      );
      if (!mounted) return;
      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _sending = false;
        _mode = _Mode.all;
        _isAlert = false;
        _types.clear();
        _entityIds.clear();
        _posOnly = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.successMsg), behavior: SnackBarBehavior.floating));
      widget.onSent();
    } catch (e) {
      if (mounted) setState(() { _sending = false; _error = friendlyError(e, context); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cs = Theme.of(context).colorScheme;
    return InkCard(
      ruleColor: IntesharColors.saffron,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.composeHeading, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: _titleCtrl, decoration: InputDecoration(labelText: s.fieldTitle), textInputAction: TextInputAction.next),
          const SizedBox(height: 12),
          TextField(controller: _bodyCtrl, decoration: InputDecoration(labelText: s.fieldBody), maxLines: 4, minLines: 3),
          const SizedBox(height: 16),
          Text(s.kindLabel, style: IntesharType.sans(12, color: IntesharColors.inkSoft, w: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(s.kindNotification), icon: const Icon(Icons.notifications_outlined, size: 16)),
              ButtonSegment(value: true, label: Text(s.kindAlert), icon: const Icon(Icons.warning_amber_rounded, size: 16)),
            ],
            selected: {_isAlert},
            onSelectionChanged: (sel) => setState(() => _isAlert = sel.first),
          ),
          const SizedBox(height: 16),
          Text(s.audienceLabel, style: IntesharType.sans(12, color: IntesharColors.inkSoft, w: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: _Mode.all, label: Text(s.modeAll)),
              ButtonSegment(value: _Mode.type, label: Text(s.modeType)),
              ButtonSegment(value: _Mode.entity, label: Text(s.modeEntity)),
            ],
            selected: {_mode},
            onSelectionChanged: (sel) => setState(() => _mode = sel.first),
          ),
          if (_mode == _Mode.type) _typePicker(s, cs),
          if (_mode == _Mode.entity) _entityPicker(s, cs),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _posOnly,
            onChanged: (v) => setState(() => _posOnly = v),
            title: Text(s.posOnly, style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w600)),
            subtitle: Text(s.posOnlyHint, style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: IntesharType.sans(12.5, color: cs.error)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2))
                : const Icon(Icons.send_outlined, size: 18),
            label: Text(s.sendBtn),
          ),
        ],
      ),
    );
  }

  Widget _typePicker(_S s, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (type, _) in _tierOptions)
              FilterChip(
                label: Text(s.tierLabel(type)),
                selected: _types.contains(type),
                onSelected: (v) => setState(() => v ? _types.add(type) : _types.remove(type)),
              ),
          ],
        ),
      );

  // Server-searched multi-select (B-023): the shared box replaces the old
  // download-every-entity checkbox list. Selection is an id set, so rows picked
  // under an earlier search stay selected while the visible page changes.
  Widget _entityPicker(_S s, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_entityIds.isNotEmpty) ...[
            Text(s.selected(_entityIds.length), style: IntesharType.sans(11.5, color: IntesharColors.saffronDeep, w: FontWeight.w700)),
            const SizedBox(height: 6),
          ],
          EntityMultiSearchList(
            repository: EntityRepository(ref.read(apiClientProvider)),
            selectedIds: _entityIds,
            onToggle: (id, sel) =>
                setState(() => sel ? _entityIds.add(id) : _entityIds.remove(id)),
          ),
        ],
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
      if (n.audienceType == 'TIER') {
        final tiers = n.audienceTiers.isNotEmpty ? n.audienceTiers : (n.audienceTier.isNotEmpty ? [n.audienceTier] : const <String>[]);
        return tiers.map(s.tierLabel).join(', ');
      }
      if (n.audienceType == 'ENTITY') {
        final count = n.audienceEntityIds.isNotEmpty ? n.audienceEntityIds.length : 1;
        return count > 1
            ? s.selected(count)
            : (n.audienceEntityName.isNotEmpty ? n.audienceEntityName : n.audienceEntityId);
      }
      return s.toEveryone;
    }

    return InkCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700))),
              if (n.sentAt != null) ...[
                const SizedBox(width: 8),
                Text(DateFormat('MM-dd HH:mm').format(n.sentAt!), style: IntesharType.mono(10, color: IntesharColors.lichen)),
              ],
            ],
          ),
          if (n.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: IntesharType.sans(12.5, color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            StampPill(label: audienceValue(), color: IntesharColors.saffron, icon: Icons.people_outline, fontSize: 10),
            if (n.posOnly) StampPill(label: s.posBadge, color: IntesharColors.sage, icon: Icons.point_of_sale, fontSize: 10),
          ]),
        ],
      ),
    );
  }
}
