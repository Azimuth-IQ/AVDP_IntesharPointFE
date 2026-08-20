import 'dart:async';

import 'package:flutter/material.dart';
import 'package:inteshar/features/pos_admin/presentation/confirm_operator_reset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/geo/maps_link.dart';
import 'package:latlong2/latlong.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_archive.dart';
import 'package:inteshar/features/pos_admin/domain/pos_slot_balance.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_network_view.dart';
import 'package:inteshar/features/pos_admin/presentation/store_pos_view.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/password_field.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// POS-user quota + lifecycle for the signed-in entity (POS-quota model, Docs/POS-QUOTA-PLAN.md).
/// Shows total/used/available slots, onboards POS users (consuming a slot), grants slots to a
/// recipient agent (HQ → any main/sub agent; other tiers → a direct child), and manages each POS
/// user (reset PIN / reset TOTP / revoke).
class PosAdminPage extends ConsumerStatefulWidget {
  /// When set (HQ drilling into an agent from the network view), the page manages THAT
  /// agent's POS points instead of the signed-in entity's. Null = the signed-in entity.
  final String? targetEntityId;
  final String? targetName;
  const PosAdminPage({super.key, this.targetEntityId, this.targetName});

  @override
  ConsumerState<PosAdminPage> createState() => _PosAdminPageState();
}

class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) => _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String a) => ar ? a : en;
  String get eyebrow => p('POS points', 'نقاط البيع');
  String get title => p('POS users', 'مستخدمو نقاط البيع');
  String get subtitle => p('Onboard and manage your points of sale', 'إضافة وإدارة نقاط البيع الخاصة بك');
  String get total => p('Total', 'الكلي');
  String get used => p('Used', 'المستخدم');
  String get available => p('Available', 'المتاح');
  String get onboard => p('Onboard POS', 'إضافة نقطة بيع');
  String get grant => p('Grant slots', 'منح نقاط');
  String get empty => p('No POS users yet.', 'لا توجد نقاط بيع بعد.');
  // B-068: only HQ distributes POS points (B-043) — a Main/Sub Agent's own parent
  // cannot grant them, so point the request at headquarters, not "your parent".
  String get noSlots => p('No available POS points — ask headquarters to grant more.', 'لا توجد نقاط بيع متاحة — اطلب من الإدارة (المقر) منحك المزيد.');
  String get resetPin => p('Reset PIN', 'إعادة تعيين الرمز');
  String get resetTotp => p('Reset 2FA', 'إعادة تعيين المصادقة');
  String get revoke => p('Archive', 'أرشفة');
  String get tabActive => p('Active', 'العاملة');
  String get tabArchived => p('Archived', 'الأرشيف');
  String get phone => p('Phone (login)', 'الهاتف (الدخول)');
  String get password => p('Password', 'كلمة المرور');
  String get posName => p('POS name', 'اسم نقطة البيع');
  String get ownerName => p('Owner full name', 'اسم المالك الثلاثي');
  String get governorate => p('Governorate', 'المحافظة');
  String get address => p('Address / nearest landmark', 'العنوان / أقرب نقطة دالة');
  String get cancel => p('Cancel', 'إلغاء');
  String get create => p('Onboard', 'إضافة');
  String get count => p('Number of slots', 'عدد النقاط');
  String get search => p('Search by name…', 'بحث بالاسم…');
  // B-129: POS list search (server-side, name or operator phone).
  String get searchPos => p('Search shop name or phone…', 'ابحث باسم المتجر أو الهاتف…');
  String get noPosMatches =>
      p('No points of sale match that search.', 'لا توجد نقاط بيع مطابقة لهذا البحث.');
  String get noMatches => p('No matching agents', 'لا يوجد وكلاء مطابقون');
  String get mainAgents => p('Main agents', 'الوكلاء الرئيسيون');
  String get subAgents => p('Sub agents', 'الوكلاء الفرعيون');
  String get done => p('Done', 'تم');
  String get loadMore => p('Load more', 'تحميل المزيد');
  String get change => p('Change', 'تغيير');
  String get pickOnMap => p('Pick on map', 'تحديد على الخريطة');
  // B-131: a pasted map link replaces pinning on a map.
  String get locationLink => p('Location link (optional)', 'رابط الموقع (اختياري)');
  String get locationFound => p('Location', 'الموقع');
  String get linkUnreadable => p(
      'No location found in that link — paste a Google/Apple Maps link, or type "lat, lng".',
      'لم يتم العثور على موقع في هذا الرابط — الصق رابط خرائط جوجل/آبل، أو اكتب "خط العرض، خط الطول".');
  String get linkShortened => p(
      'Short links cannot be read — open it once, then paste the full link from the address bar.',
      'لا يمكن قراءة الروابط المختصرة — افتحه مرة ثم الصق الرابط الكامل من شريط العنوان.');
  String get locationHintNone =>
      p('Location (optional hint)', 'الموقع (اختياري — مبدئي)');
  String get revokeConfirm => p('Archive this POS point? It stops trading and the slot is returned.',
      'إلغاء هذه النقطة؟ سيتوقف دخولها وتعود النقطة للرصيد.');
  String get required => p('Required', 'مطلوب');
  String get invalidPhone => p('Invalid phone (e.g. 07XXXXXXXXX)', 'رقم غير صحيح (مثال 07XXXXXXXXX)');
  String get edit => p('Edit', 'تعديل');
  String get editPos => p('Edit POS', 'تعديل نقطة البيع');
  String get save => p('Save', 'حفظ');
  String get pinResetTitle => p('New POS PIN', 'رمز نقطة البيع الجديد');
  String get pinResetBody => p('Give this PIN to the operator — it will not be shown again.',
      'سلّم هذا الرمز للمشغّل — لن يُعرض مرة أخرى.');
  String get resetPassword => p('Reset password', 'تغيير كلمة المرور');
  String get newPassword => p('New password', 'كلمة المرور الجديدة');
  String get passwordTooShort => p('At least 6 characters', '6 أحرف على الأقل');
  String get passwordResetDone => p('Password changed', 'تم تغيير كلمة المرور');
  String get close => p('Close', 'إغلاق');
  String get activate => p('Activate', 'تفعيل');
  String get deactivate => p('Deactivate', 'إيقاف');
  String get disabled => p('Disabled', 'موقوف');
  // B-132: a duplicate phone gets a modal, not a snackbar.
  String get alreadyExistsTitle =>
      p('This customer already exists', 'هذا الزبون موجود بالفعل');
  String get alreadyExistsBody => p(
      'A POS user is already registered with this phone number. Use a different number, or find the existing point in the list.',
      'يوجد مستخدم نقطة بيع مسجل بهذا الرقم. استخدم رقماً آخر، أو ابحث عن النقطة الموجودة في القائمة.');
}

class _PosAdminPageState extends ConsumerState<PosAdminPage> {
  /// Mirrors the server's pos.archive.retention-days default. Only used for the
  /// wording of the archive prompt — every countdown and the purge rule itself
  /// come from the server, so a drift here cannot let a delete happen early.
  static const int _archiveRetentionDays = 30;

  /// Whether the archive is showing instead of the trading shops.
  bool _showArchive = false;
  List<Entity> _stores = const [];
  int _page = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  PosSlotBalance? _quota;
  // B-043: Main/Sub agents may only USE POS points, never grant them on. Only HQ distributes
  // points (to any account), via the network view — so this page carries no recipient picker.
  // The one grant here is HQ drilling into a specific agent (see _grantToTargetDialog).
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  PosAdminRepository get _repo => PosAdminRepository(ref.read(apiClientProvider));
  String? get _myId => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id;
  EntityType? get _signedInType => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.type;

  /// HQ drilling into an agent (from the network view) vs managing the signed-in entity.
  bool get _isDrill => widget.targetEntityId != null;
  String? get _effectiveId => widget.targetEntityId ?? _myId;

  /// HQ on its own screen shows the network oversight, not a self-management body.
  bool get _showNetwork => !_isDrill && _signedInType == EntityType.INTESHAR;

  /// A STORE *is* a POS point: it can never host one (the server only onboards
  /// under an agent), so this body — quota, onboard, list of hosted shops —
  /// would be an empty list under a permanent 0/0/0 quota. It gets the shop's
  /// own POS view instead. Drill mode is unaffected: HQ only drills into agents.
  bool get _showStoreSelf => !_isDrill && _signedInType == EntityType.STORE;

  /// Guards the one-shot initial fetch. It cannot live in `initState`: which
  /// body this screen is depends on the signed-in tier, and on a cold mount the
  /// auth state can still be resolving on the first frame — so HQ and stores
  /// would fire the agent feeds (with an empty entityId) before swapping.
  bool _started = false;

  /// B-129: server-side POS search (name or operator phone), debounced so a
  /// manager typing a name does not fire a request per keystroke.
  String _query = '';
  Timer? _searchDebounce;

  static const _pageSize = 50;

  /// Debounced so typing a name fires one request, not one per keystroke.
  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = v);
      _load();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = _effectiveId ?? '';
      final quota = await _repo.quota(entityId: id);
      // B-052: each POS is a STORE child entity of the host agent.
      // B-023 P2: paged — a Main Agent with hundreds of shops used to get them
      // all in one response and stall on a list it renders a card at a time.
      final first = await _repo.listPaged(entityId: id, q: _query, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _stores = first.items;
        _hasMore = first.hasMore;
        _page = 0;
        _quota = quota;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = await _repo.listPaged(
          entityId: _effectiveId ?? '', q: _query, page: _page + 1, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _stores = [..._stores, ...next.items];
        _hasMore = next.hasMore;
        _page += 1;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }


  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(okMsg)));
      await _load();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch (not read) the session: the tier picks the body, so a still-resolving
    // auth state must rebuild here rather than fall through to the agent body.
    if (ref.watch(authStateProvider).isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_showNetwork) return const PosNetworkView();
    if (_showStoreSelf) return const StorePosView();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final s = _S.of(context);
    // Drill mode is a pushed route — give it its own Scaffold + back button.
    if (_isDrill) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.targetName ?? s.title)),
        body: MaxWidthBox(
          maxWidth: 760,
          child: Column(children: [Expanded(child: _body(s))]),
        ),
      );
    }
    return MaxWidthBox(
      maxWidth: 760,
      child: Column(
        children: [
          PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle),
          Expanded(child: _body(s)),
        ],
      ),
    );
  }

  Widget _body(_S s) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorState(error: _error!, onRetry: _load);
    final cs = Theme.of(context).colorScheme;
    final q = _quota;
    final loc = Localizations.localeOf(context).languageCode;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 28),
        children: [
          if (q != null) _quotaCard(s, q),
          const SizedBox(height: 12),
          // C-12: the archive is a view of the SAME screen, not a separate
          // destination — an operator who just archived a shop looks for it here.
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.storefront_outlined, size: 16),
                  label: Text(s.tabActive)),
              ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: Text(s.tabArchived)),
            ],
            selected: {_showArchive},
            onSelectionChanged: (v) => setState(() => _showArchive = v.first),
          ),
          const SizedBox(height: 12),
          if (_showArchive) ...[
            // Restoring a shop moves it back into the Active segment and spends
            // one of the host's POS points, so both the list and the quota
            // behind this view are stale until we reload.
            PosArchiveView(entityId: _effectiveId, onChanged: _load),
          ] else ...[
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (_busy || (q != null && q.available <= 0)) ? null : () => _onboardDialog(s),
                icon: const Icon(Icons.point_of_sale, size: 18),
                label: Text(s.onboard),
              ),
            ),
            // Only HQ drilling into an agent may grant points (B-043).
            if (_isDrill) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _grantToTargetDialog(s),
                  icon: const Icon(Icons.card_giftcard, size: 18),
                  label: Text(s.grant),
                ),
              ),
            ],
          ]),
          if (q != null && q.available <= 0) ...[
            const SizedBox(height: 8),
            Text(s.noSlots, style: IntesharType.sans(12, color: cs.error)),
          ],
          const SizedBox(height: 16),
          // B-129: find one shop without scrolling a paged list.
          TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: s.searchPos,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        setState(() => _query = '');
                        _load();
                      },
                    ),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),
          if (_stores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _query.isEmpty ? s.empty : s.noPosMatches,
                  textAlign: TextAlign.center,
                  style: IntesharType.sans(14, color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            for (final st in _stores) _posCard(s, st, loc, cs),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton(onPressed: _loadMore, child: Text(s.loadMore)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quotaCard(_S s, PosSlotBalance q) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: context.tones.brand, borderRadius: BorderRadius.circular(IntesharRadii.lg)),
      child: Row(children: [
        _stat(s.available, q.root ? '∞' : Formatters.money(q.available)),
        _divider(),
        _stat(s.used, Formatters.money(q.used)),
        _divider(),
        _stat(s.total, q.root ? '∞' : Formatters.money(q.total)),
      ]),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: IntesharType.overline(color: IntesharColors.ink.withValues(alpha: 0.7))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontFamily: 'CodecPro', fontSize: 24, fontWeight: FontWeight.w900, color: IntesharColors.ink, height: 1)),
        ]),
      );

  Widget _divider() => Container(width: 1, height: 34, color: IntesharColors.ink.withValues(alpha: 0.18));

  /// The shop's single POS operator (isPos) — falls back to the first user.
  /// The shop's POS operator, or null when it has none.
  ///
  /// B-130: this used to fall back to `users.first` when no user carried
  /// `isPos`. The server refuses every operator action for such a user —
  /// revoke returns 400 "No POS user with that phone on this entity", and the
  /// PIN/password/TOTP resets resolve no user at all. So the card showed a
  /// phone, enabled four buttons, and the server declined all of them: exactly
  /// the reported "الغاء الوصول غير فعال".
  ///
  /// Strict now, so the UI only offers what the server will accept.
  EntityUser? _operator(Entity store) {
    for (final u in store.users) {
      if (u.isPos) return u;
    }
    return null;
  }

  Widget _posCard(_S s, Entity store, String loc, ColorScheme cs) {
    final op = _operator(store);
    final phone = op?.phone ?? '';
    final name = store.meta.name.isNotEmpty ? store.meta.name : phone;
    final owner = store.profile?.ownerName ?? '';
    final gov = store.meta.governorates.isNotEmpty ? store.meta.governorates.first : '';
    final active = store.active;
    return InkCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
          StampPill(
            label: active ? 'POS' : s.disabled,
            color: active ? IntesharColors.sage : cs.outline,
          ),
        ]),
        const SizedBox(height: 4),
        Text(phone, style: IntesharType.mono(12, color: cs.onSurfaceVariant)),
        if (owner.isNotEmpty) Text(owner, style: IntesharType.sans(12.5, color: cs.onSurface)),
        if (gov.isNotEmpty) Text(governorateLabel(gov, loc), style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
        // B-130: greying four buttons with no explanation is what made this read
        // as broken. Say the shop has no POS operator, which is the actual state.
        if (phone.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              loc == 'ar'
                  ? 'لا يوجد مستخدم نقطة بيع لهذا المتجر — إجراءات المستخدم غير متاحة'
                  : 'This shop has no POS user — operator actions are unavailable',
              style: IntesharType.sans(11.5, color: cs.error, w: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _busy ? null : () => _editDialog(s, store), child: Text(s.edit)),
          OutlinedButton(onPressed: (_busy || phone.isEmpty) ? null : () => _resetPin(s, name, phone), child: Text(s.resetPin)),
          OutlinedButton(onPressed: (_busy || phone.isEmpty) ? null : () => _resetPassword(s, name, phone), child: Text(s.resetPassword)),
          OutlinedButton(onPressed: (_busy || phone.isEmpty) ? null : () => _resetTotp(s, name, phone), child: Text(s.resetTotp)),
          OutlinedButton(
            onPressed: _busy ? null : () => _toggleActive(s, store.id, active),
            child: Text(active ? s.deactivate : s.activate),
          ),
          OutlinedButton(
            onPressed: (_busy || phone.isEmpty) ? null : () => _confirmArchive(s, store, phone),
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            child: Text(s.revoke),
          ),
        ]),
      ]),
    );
  }

  /// Deactivating a shop stops its operator logging in, so confirm it (B-080).
  /// Re-activating is harmless and fires immediately.
  Future<void> _toggleActive(_S s, String storeId, bool active) async {
    if (active) {
      final ar = Localizations.localeOf(context).languageCode == 'ar';
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          content: Text(ar
              ? 'إيقاف هذا المتجر سيمنع مشغّله من تسجيل الدخول. متابعة؟'
              : 'Deactivating this shop stops its operator from signing in. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.deactivate)),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(() => _repo.setActive(storeId, !active), s.done);
  }

  /// C-12: removing a shop ARCHIVES it. The dialog puts the data download in
  /// front of the operator first, because archiving starts a countdown to
  /// permanent deletion and this is the moment that matters.
  Future<void> _confirmArchive(_S s, Entity store, String phone) async {
    final code = await showArchivePosDialog(
      context,
      ref,
      storeId: store.id,
      storeName: store.meta.name,
      retentionDays: _archiveRetentionDays,
    );
    if (code == null) return;
    await _run(
        () => _repo.revoke(
            entityId: _effectiveId ?? '', phone: phone, totp: code),
        s.done);
  }

  /// Reset the POS PIN and reveal the fresh manager-visible PIN once (B-047).
  Future<void> _resetTotp(_S s, String name, String phone) async {
    if (!await confirmResetTotp(context, posName: name)) return;
    await _run(() => _repo.resetTotp(phone), s.done);
  }

  Future<void> _resetPin(_S s, String name, String phone) async {
    if (!await confirmResetPin(context, posName: name)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pin = await _repo.resetPin(phone);
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.pinResetTitle),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.pinResetBody, style: IntesharType.sans(13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            SelectableText(
              pin,
              style: const TextStyle(fontFamily: 'CodecPro', fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 8),
            ),
          ]),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.close)),
          ],
        ),
      );
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Change a POS user's login password (B-047).
  Future<void> _resetPassword(_S s, String name, String phone) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.resetPassword} — $name'),
        content: Form(
          key: formKey,
          child: PasswordField(
            controller: ctrl,
            label: s.newPassword,
            autofocus: true,
            validator: (v) => (v == null || v.trim().length < 6) ? s.passwordTooShort : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _repo.resetPassword(phone, ctrl.text.trim()), s.passwordResetDone);
    }
  }

  Future<void> _onboardDialog(_S s) async {
    final phone = TextEditingController();
    final pw = TextEditingController();
    final name = TextEditingController();
    final owner = TextEditingController();
    final addr = TextEditingController();
    String? gov;
    // B-080: optional location HINT. The shop still confirms its own location on
    // its map gate before it can sell — this just pre-centres that map, so the
    // operator isn't dropped in the middle of the country.
    LatLng? hint;
    final mapLink = TextEditingController();
    String? linkError;
    final formKey = GlobalKey<FormState>();
    final loc = Localizations.localeOf(context).languageCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.onboard),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // B-044: every field is mandatory — nothing optional.
                _field(phone, s.phone,
                    keyboard: TextInputType.phone,
                    digitsOnly: true,
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return s.required;
                      if (!RegExp(r'^07\d{9}$').hasMatch(t)) return s.invalidPhone;
                      return null;
                    }),
                // Min-6 to match the reset-password rule for the same credential (B-080).
                _field(pw, s.password, obscure: true,
                    validator: (v) => (v == null || v.trim().length < 6) ? s.passwordTooShort : null),
                _field(name, s.posName, validator: _req(s)),
                _field(owner, s.ownerName, validator: _req(s)),
                DropdownButtonFormField<String>(
                  initialValue: gov,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.governorate, isDense: true),
                  items: [for (final g in kGovernorates) DropdownMenuItem(value: g.code, child: Text(governorateLabel(g.code, loc)))],
                  validator: (v) => (v == null || v.isEmpty) ? s.required : null,
                  onChanged: (v) => setD(() => gov = v),
                ),
                _field(addr, s.address, validator: _req(s)),
                const SizedBox(height: 8),
                // B-131: paste the shared map link instead of pinning on a map.
                // Pinning is awkward on a phone and impossible unless you are
                // standing in the shop; in practice the location arrives as a
                // WhatsApp link. This is only the optional hint — the on-site
                // confirmation that gates selling (B-054) is untouched, and a
                // pasted link deliberately cannot satisfy it.
                TextFormField(
                  controller: mapLink,
                  decoration: InputDecoration(
                    labelText: s.locationLink,
                    hintText: 'https://maps.google.com/...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.link, size: 18),
                  ),
                  onChanged: (v) {
                    final parsed = parseLatLngFromMapsLink(v);
                    setD(() {
                      hint = parsed == null
                          ? null
                          : LatLng(parsed.latitude, parsed.longitude);
                      linkError = v.trim().isEmpty || parsed != null
                          ? null
                          : (isShortenedMapLink(v) ? s.linkShortened : s.linkUnreadable);
                    });
                  },
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    linkError ??
                        (hint == null
                            ? s.locationHintNone
                            : '${s.locationFound}: ${hint!.latitude.toStringAsFixed(5)}, ${hint!.longitude.toStringAsFixed(5)}'),
                    style: IntesharType.sans(
                      11.5,
                      color: linkError != null
                          ? Theme.of(ctx).colorScheme.error
                          : Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
              },
              child: Text(s.create),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      // B-132: a duplicate phone is the one outcome that needs to STOP the
      // operator. The server answers 409 "Phone is already in use"; a snackbar
      // for that is missable, and the operator re-types the same number
      // believing the save simply failed. Everything else keeps the snackbar.
      if (!mounted) return; // the confirm dialog above is an async gap
      setState(() => _busy = true);
      final messenger = ScaffoldMessenger.of(context);
      try {
        await _repo.onboard(
          entityId: _effectiveId ?? '',
          phone: phone.text.trim(),
          password: pw.text,
          posName: name.text.trim(),
          posOwnerName: owner.text.trim(),
          posGovernorate: gov,
          posAddress: addr.text.trim(),
          posLatitude: hint?.latitude,
          posLongitude: hint?.longitude,
        );
        if (mounted) messenger.showSnackBar(SnackBar(content: Text(s.done)));
        await _load();
      } catch (e) {
        if (!mounted) return;
        if (isDuplicatePhone(e)) {
          await _showAlreadyExistsDialog(s, phone.text.trim(), serverReason(e));
        } else {
          messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  /// A modal the operator has to acknowledge — the point of B-132 is that this
  /// outcome cannot be missed the way a snackbar can.
  Future<void> _showAlreadyExistsDialog(_S s, String phone, String? reason) async {
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.person_off_outlined, color: cs.error),
        title: Text(s.alreadyExistsTitle),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          // C-06: prefer what the SERVER says. A phone is unique platform-wide, so
          // the clashing shop is often under another agent and therefore missing
          // from this operator's list — telling them to search it is what made
          // this look broken. The server names the holder when the caller may see
          // it, and says "another agent" when they may not.
          Text(reason?.trim().isNotEmpty == true ? reason!.trim() : s.alreadyExistsBody,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(phone, style: IntesharType.mono(14, color: cs.onSurface)),
        ]),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  /// Edit an existing POS profile (B-045, unified B-052: fields live on the STORE
  /// entity). Phone + credentials are unchanged (use the reset actions for those).
  Future<void> _editDialog(_S s, Entity store) async {
    final op = _operator(store);
    final phone = op?.phone ?? '';
    final name = TextEditingController(text: store.meta.name);
    final owner = TextEditingController(text: store.profile?.ownerName ?? '');
    final addr = TextEditingController(text: store.profile?.address ?? '');
    String? gov = store.meta.governorates.isNotEmpty ? store.meta.governorates.first : null;
    final formKey = GlobalKey<FormState>();
    final loc = Localizations.localeOf(context).languageCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${s.editPos} — $phone'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _field(name, s.posName, validator: _req(s)),
                _field(owner, s.ownerName, validator: _req(s)),
                DropdownButtonFormField<String>(
                  initialValue: gov,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: s.governorate, isDense: true),
                  items: [for (final g in kGovernorates) DropdownMenuItem(value: g.code, child: Text(governorateLabel(g.code, loc)))],
                  validator: (v) => (v == null || v.isEmpty) ? s.required : null,
                  onChanged: (v) => setD(() => gov = v),
                ),
                _field(addr, s.address, validator: _req(s)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(
        () => _repo.update(
          phone: phone,
          posName: name.text.trim(),
          posOwnerName: owner.text.trim(),
          posGovernorate: gov ?? '',
          posAddress: addr.text.trim(),
        ),
        s.done,
      );
    }
  }

  /// Drill mode: HQ grants slots straight to the target agent (no recipient picker).
  Future<void> _grantToTargetDialog(_S s) async {
    final countCtrl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.grant} — ${widget.targetName ?? ''}'.trim()),
        content: _field(countCtrl, s.count, keyboard: TextInputType.number, digitsOnly: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.grant)),
        ],
      ),
    );
    final n = int.tryParse(countCtrl.text.trim()) ?? 0;
    if (ok == true && n > 0) {
      await _run(() => _repo.grantSlots(destId: _effectiveId ?? '', count: n), s.done);
    }
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false,
      TextInputType? keyboard,
      bool digitsOnly = false,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: obscure
          ? PasswordField(controller: c, label: label, isDense: true, validator: validator)
          : TextFormField(
              controller: c,
              keyboardType: keyboard,
              inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
              validator: validator,
              decoration: InputDecoration(labelText: label, isDense: true),
            ),
    );
  }

  /// Non-empty validator for the required POS fields (B-044 — every field mandatory).
  String? Function(String?) _req(_S s) =>
      (v) => (v == null || v.trim().isEmpty) ? s.required : null;
}
