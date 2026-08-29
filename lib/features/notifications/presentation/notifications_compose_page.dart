import 'package:flutter/material.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/notifications/data/notification_repository.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';
import 'package:inteshar/shared/widgets/app_snackbar.dart';
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
  /// UX-88: "Notification sent!" confirmed nothing — not the kind that went out
  /// (an ALERT is a persistent banner, a notification is an inbox row) and not
  /// who received it. A broadcast to everyone and a note to one shop produced
  /// the SAME six characters. These name both, from the audience the sender
  /// just chose, so the toast can be checked against the intent.
  String sentAlertTo(String audience) =>
      p('Alert sent to $audience', 'أُرسل التنبيه إلى $audience');
  String sentNoticeTo(String audience) =>
      p('Notification sent to $audience', 'أُرسل الإشعار إلى $audience');
  String get audAllPos => p('all POS operators', 'كل مستخدمي نقاط البيع');
  String get audEveryone => p('everyone', 'الجميع');
  String audAccounts(int n) => accountsPhrase(n);

  /// UX-88 — the toast the server's tally makes possible.
  ///
  /// `POST /api/notifications` now answers with how many accounts and logins the
  /// send actually reached, so the confirmation carries the audience SIZE and not
  /// only its name. Shaped like the withdraw toast the app already gets right
  /// ("Withdrew 60 of 100 — 40 left"): what happened, then the numbers.
  ///
  /// Three cases, in the order they are decided:
  ///  * nothing was reached — the send succeeded but no live account can open it,
  ///    which is the one outcome a sender must not read as success;
  ///  * the audience phrase already IS this number (an "n accounts" send that
  ///    reached all n) — repeating it would say the same thing twice;
  ///  * otherwise, append the reach.
  ///
  /// [audienceAccounts] is how many accounts the sender picked, when the audience
  /// was picked BY account; null for a tier or everyone broadcast.
  String sentSummary({
    required bool alert,
    required String audience,
    required int accounts,
    required int recipients,
    required bool posOnly,
    int? audienceAccounts,
  }) {
    final head = alert ? sentAlertTo(audience) : sentNoticeTo(audience);
    if (accounts <= 0) {
      return p('$head — but no account can receive it yet',
          '$head — لكن لا يوجد حساب يمكنه استلامه');
    }
    if (!posOnly && audienceAccounts == accounts) return head;
    final reach = posOnly ? posUsersPhrase(recipients) : accountsPhrase(accounts);
    return p('$head — reached $reach', '$head — وصل إلى $reach');
  }

  /// Arabic counts a noun three different ways depending on the number, so a
  /// single "$n حسابات" template reads wrong for most values ("2 حسابات",
  /// "12 حسابات"). Dual for 2, broken plural for 3–10, accusative singular from
  /// 11 up.
  String accountsPhrase(int n) => p(
      n == 1 ? '1 account' : '$n accounts',
      switch (n) {
        1 => 'حساب واحد',
        2 => 'حسابين',
        <= 10 => '$n حسابات',
        _ => '$n حساباً',
      });

  String posUsersPhrase(int n) => p(
      n == 1 ? '1 POS operator' : '$n POS operators',
      switch (n) {
        1 => 'مستخدم نقطة بيع واحد',
        2 => 'مستخدمَين لنقاط البيع',
        <= 10 => '$n مستخدمين لنقاط البيع',
        _ => '$n مستخدماً لنقاط البيع',
      });
  /// "POS operators in [the named tiers]" — posOnly narrows a tier/entity audience too,
  /// and a confirmation that omits the narrowing overstates the reach.
  String posWithin(String audience) =>
      p('POS operators in $audience', 'مستخدمو نقاط البيع في $audience');
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

/// Test seam for the UX-88 send confirmation. The toast is the only report a
/// sender ever gets about how far a broadcast went, and its wording is decided by
/// arithmetic (zero reach / redundant reach / plain reach) plus Arabic number
/// agreement — none of which a widget test would surface. Assert the strings.
NotificationStrings notificationStringsFor(bool ar) => _S(ar);

typedef NotificationStrings = _S;

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
          const SliverToBoxAdapter(child: SizedBox(height: IntesharSpacing.xxl)),
        ],
      ),
    );
  }

  List<Widget> _historySliver(_S s) {
    if (_historyLoading) {
      return [const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(IntesharSpacing.xxl), child: Center(child: CircularProgressIndicator())))];
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
          separatorBuilder: (_, _) => const SizedBox(height: IntesharSpacing.sm2),
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

  /// UX-88: ONE description of the audience, used by both the pre-send confirm
  /// and the post-send toast — so the sentence the sender agreed to is the
  /// sentence they get back. It also now NAMES the tiers instead of saying "the
  /// selected tiers", and carries the posOnly narrowing into every mode (it
  /// applies to tier and entity audiences too, not just "Everyone").
  String _audienceLabel(_S s) {
    final base = switch (_mode) {
      _Mode.all => s.audEveryone,
      _Mode.type => (_types.toList()..sort()).map(s.tierLabel).join('، '),
      _Mode.entity => s.audAccounts(_entityIds.length),
    };
    if (!_posOnly) return base;
    return _mode == _Mode.all ? s.audAllPos : s.posWithin(base);
  }

  /// Confirm a send before it fires — a broadcast (especially an ALERT to
  /// Everyone) pushes an irreversible, persistent banner to many users on one tap.
  Future<bool> _confirmSend() async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final kind = _isAlert ? (ar ? 'تنبيه' : 'an alert') : (ar ? 'إشعار' : 'a notification');
    final audience = _audienceLabel(widget.s);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'تأكيد الإرسال' : 'Confirm send'),
        content: Text(ar
            ? 'إرسال $kind إلى $audience؟'
            : 'Send $kind to $audience?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ar ? 'إرسال' : 'Send')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _send() async {
    final s = widget.s;
    if (_titleCtrl.text.trim().isEmpty) return setState(() => _error = s.errTitle);
    if (_bodyCtrl.text.trim().isEmpty) return setState(() => _error = s.errBody);
    if (_mode == _Mode.type && _types.isEmpty) return setState(() => _error = s.errTypes);
    if (_mode == _Mode.entity && _entityIds.isEmpty) return setState(() => _error = s.errEntities);

    if (!await _confirmSend()) return;

    // Captured BEFORE the form is reset — the toast describes the send that just
    // happened, and `_send` clears the audience on success.
    final audience = _audienceLabel(s);
    final wasAlert = _isAlert;
    final wasPosOnly = _posOnly;
    // Only meaningful when the audience was picked BY account; a tier or
    // everyone broadcast has no picked count to compare the reach against.
    final pickedAccounts = _mode == _Mode.entity ? _entityIds.length : null;

    setState(() { _sending = true; _error = null; });
    try {
      final reach = await NotificationRepository(ref.read(apiClientProvider)).send(
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
      // UX-88: names the kind, the audience AND how far it reached. A backend
      // that predates the tally reports none (`hasTally == false`) — say less
      // rather than announce a zero the server never claimed.
      showOk(
        context,
        reach.hasTally
            ? s.sentSummary(
                alert: wasAlert,
                audience: audience,
                accounts: reach.accounts ?? 0,
                recipients: reach.recipients ?? 0,
                posOnly: wasPosOnly,
                audienceAccounts: pickedAccounts,
              )
            : (wasAlert ? s.sentAlertTo(audience) : s.sentNoticeTo(audience)),
      );
      widget.onSent();
    } catch (e) {
      if (mounted) setState(() { _sending = false; _error = friendlyError(e, context); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return InkCard(
      ruleColor: context.tones.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.composeHeading, style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: _titleCtrl, decoration: InputDecoration(labelText: s.fieldTitle), textInputAction: TextInputAction.next),
          const SizedBox(height: IntesharSpacing.md),
          TextField(controller: _bodyCtrl, decoration: InputDecoration(labelText: s.fieldBody), maxLines: 4, minLines: 3),
          const SizedBox(height: IntesharSpacing.lg),
          Text(s.kindLabel, style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: IntesharWeight.semibold)),
          const SizedBox(height: IntesharSpacing.sm),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(s.kindNotification), icon: const Icon(Icons.notifications_outlined, size: 16)),
              ButtonSegment(value: true, label: Text(s.kindAlert), icon: const Icon(Icons.warning_amber_rounded, size: 16)),
            ],
            selected: {_isAlert},
            onSelectionChanged: (sel) => setState(() => _isAlert = sel.first),
          ),
          const SizedBox(height: IntesharSpacing.lg),
          Text(s.audienceLabel, style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: IntesharWeight.semibold)),
          const SizedBox(height: IntesharSpacing.sm),
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
          const SizedBox(height: IntesharSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _posOnly,
            onChanged: (v) => setState(() => _posOnly = v),
            title: Text(s.posOnly, style: IntesharType.sans(14, color: cs.onSurface, w: IntesharWeight.semibold)),
            subtitle: Text(s.posOnlyHint, style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: IntesharType.sans(12, color: cs.error)),
          ],
          const SizedBox(height: IntesharSpacing.md),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2))
                : Icon(_isAlert ? Icons.warning_amber_rounded : Icons.send_outlined, size: 18),
            // Label names the kind so it's obvious an ALERT (not a plain notice) is about to fire.
            label: Text(_isAlert
                ? (ar ? 'إرسال تنبيه' : 'Send alert')
                : (ar ? 'إرسال إشعار' : 'Send notification')),
          ),
        ],
      ),
    );
  }

  Widget _typePicker(_S s, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: IntesharSpacing.md),
        child: Wrap(
          spacing: IntesharSpacing.sm,
          runSpacing: IntesharSpacing.sm,
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
      padding: const EdgeInsets.only(top: IntesharSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_entityIds.isNotEmpty) ...[
            Text(s.selected(_entityIds.length), style: IntesharType.sans(12, color: context.tones.brandInk, w: FontWeight.w700)),
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
      density: CardDensity.dense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700))),
              if (n.sentAt != null) ...[
                const SizedBox(width: IntesharSpacing.sm),
                Text(DateFormat('MM-dd HH:mm').format(n.sentAt!), style: IntesharType.mono(11, color: IntesharColors.lichen)),
              ],
            ],
          ),
          if (n.body.isNotEmpty) ...[
            const SizedBox(height: IntesharSpacing.xs),
            Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: IntesharSpacing.sm),
          Wrap(spacing: IntesharSpacing.sm, runSpacing: 6, children: [
            StampPill(label: audienceValue(), color: context.tones.brand, icon: Icons.people_outline),
            if (n.posOnly) StampPill(label: s.posBadge, color: context.status.success, icon: Icons.point_of_sale),
          ]),
        ],
      ),
    );
  }
}
