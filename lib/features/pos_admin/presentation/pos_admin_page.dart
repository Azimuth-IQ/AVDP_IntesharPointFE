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
import 'package:inteshar/features/chat/presentation/supply_request.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_archive.dart';
import 'package:inteshar/features/pos_admin/domain/pos_slot_balance.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_network_view.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_shop_sheet.dart';
import 'package:inteshar/features/pos_admin/presentation/store_pos_view.dart';
import 'package:inteshar/features/reports/data/reports_repository.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/multi_select.dart';
import 'package:inteshar/shared/widgets/password_field.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// POS-user quota + lifecycle for the signed-in entity (POS-quota model, Docs/plans/POS-QUOTA-PLAN.md).
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
  // UX-28: the action that performs that sentence.
  String get requestSlots => p('Request points', 'طلب نقاط');
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
  // UX-73: an empty or zero slot count used to close the dialog and do nothing.
  String get atLeastOne => p('Enter at least 1', 'أدخل 1 على الأقل');
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
  // UX-07: `locationConfirmedAt == null` blocks every sale (pos_home_page), was
  // already on the object this list fetches, and was shown nowhere.
  String get locationPending => p('Location not confirmed', 'الموقع غير مؤكَّد');
  // UX-24: money on the shop card — the roster is VIEW_REPORTS-gated, so this is
  // omitted rather than shown as a confident zero when the feed refuses.
  String get balance => p('Balance', 'الرصيد');
  String get outOfCredit => p('out of credit', 'بلا رصيد');
  // UX-11: bulk activate/deactivate over a roster of shops. An agent with forty
  // shops used to close for the night forty times.
  static const posUnit = BulkUnit(ar: 'نقطة بيع', en: 'points of sale');
  String activateN(int n) => p('Activate $n points of sale?', 'تفعيل $n نقطة بيع؟');
  String deactivateN(int n) => p('Deactivate $n points of sale?', 'إيقاف $n نقطة بيع؟');
  String get activateBody => p(
      'Their operators can sign in and sell again.',
      'سيتمكن مشغّلوها من تسجيل الدخول والبيع مجدداً.');
  String get deactivateBody => p(
      'Their operators stop being able to sign in. Nothing is deleted and it can be undone by activating them again.',
      'لن يتمكن مشغّلوها من تسجيل الدخول. لا يُحذف شيء ويمكن التراجع بتفعيلها مرة أخرى.');
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

  /// UX-24: shopId → available balance, for the money line on each POS card.
  ///
  /// Null means the roster feed refused (it is `VIEW_REPORTS`-gated and plenty of
  /// managers hold `MANAGE_POS` without it) — the line is then HIDDEN. Rendering
  /// a zero for a shop we simply could not read is the failure mode that sends
  /// somebody to top up an account that was already funded.
  Map<String, num>? _balances;
  // B-043: Main/Sub agents may only USE POS points, never grant them on. Only HQ distributes
  // points (to any account), via the network view — so this page carries no recipient picker.
  // The one grant here is HQ drilling into a specific agent (see _grantToTargetDialog).
  bool _loading = true;

  /// UX-83: which controls are working, keyed `'<storeId>:<action>'` for a row
  /// button and `'page:<action>'` for the page-level ones. A single page-wide
  /// bool greyed EVERY row on every card while putting the spinner nowhere — the
  /// only feedback was "everything went grey". Scoped the way
  /// `printer_picker_page` (`_busyId`) and `delete_agent_sheet` (`Set<String>`)
  /// already do it.
  final Set<String> _busy = {};
  Object? _error;

  bool _isBusy(String key) => _busy.contains(key);

  /// Another control on the SAME shop is mid-action — that row waits, the rest
  /// of the list does not.
  bool _rowBusy(String storeId) => _busy.any((k) => k.startsWith('$storeId:'));

  /// Onboarding or granting reloads the whole list, so those do hold the page.
  bool get _pageBusy => _busy.any((k) => k.startsWith('page:'));

  PosAdminRepository get _repo => PosAdminRepository(ref.read(apiClientProvider));
  String? get _myId => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id;
  EntityType? get _signedInType => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.type;

  /// HQ drilling into an agent (from the network view) vs managing the signed-in entity.
  bool get _isDrill => widget.targetEntityId != null;
  String? get _effectiveId => widget.targetEntityId ?? _myId;

  /// HQ on its own screen shows the network oversight, not a self-management body.
  bool get _showNetwork => !_isDrill && _signedInType == EntityType.INTESHAR;

  /// UX-28: whether "ask headquarters for points" is a thing THIS viewer can do.
  ///
  /// Not in drill mode — that viewer *is* headquarters and already has the Grant
  /// button next to this line — and not for a root quota, which is unbounded.
  bool _canAskForSlots(PosSlotBalance q) =>
      !_isDrill && !q.root && _signedInType != EntityType.INTESHAR;

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

  /// UX-11: multi-select over the shop roster. Deactivating for a holiday, or
  /// reactivating after one, was N × (find row → tap → confirm → wait → reload)
  /// on a list that routinely runs to dozens of shops.
  SelectionState _selection = SelectionState.off;
  bool _bulkBusy = false;

  static const _pageSize = 50;

  /// Debounced so typing a name fires one request, not one per keystroke.
  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = v);
      // Silent: a blanking reload would tear down the very TextField being
      // typed into, closing the keyboard on every debounce tick (UX-84).
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// UX-84: [silent] keeps the rows on screen while they refresh.
  ///
  /// `_loading = true` makes `_body` return a full-screen spinner, so a
  /// pull-to-refresh DELETED the list and drew a spinner under the refresh arc —
  /// scroll position lost, and after archiving a shop the one signal that
  /// mattered ("the row is gone") happened behind that flash. Only the first
  /// load (and a search, which genuinely replaces the list) blanks now.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final id = _effectiveId ?? '';
      final quota = await _repo.quota(entityId: id);
      // B-052: each POS is a STORE child entity of the host agent.
      // B-023 P2: paged — a Main Agent with hundreds of shops used to get them
      // all in one response and stall on a list it renders a card at a time.
      final first = await _repo.listPaged(entityId: id, q: _query, size: _pageSize);
      // UX-24: best-effort, and deliberately AFTER the list — a 403 here must
      // cost the money column, never the shops.
      final balances = await _storeBalances(id);
      if (!mounted) return;
      setState(() {
        _stores = first.items;
        _hasMore = first.hasMore;
        _page = 0;
        _quota = quota;
        _balances = balances;
        _loading = false;
        // A shop that was archived (or paged away by a new search) must stop
        // being counted — otherwise the bar says "5 selected" over four rows and
        // the next run posts an id the roster no longer holds.
        _selection = _selection.retain(first.items.map((e) => e.id));
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  /// Every STORE under [rootId] and what it has to spend, or null when the feed
  /// is not available to this caller (UX-24). One paged roster call, not one
  /// balance call per card.
  Future<Map<String, num>?> _storeBalances(String rootId) async {
    if (rootId.isEmpty) return null;
    try {
      final api = ref.read(apiClientProvider);
      final out = <String, num>{};
      var page = 0;
      while (true) {
        final res = await ReportsRepository(api)
            .balancesRoster(rootId: rootId, type: 'STORE', page: page, size: 200);
        for (final r in res.items) {
          out[r.entityId] = r.available;
        }
        if (!res.hasMore || page > 20) break;
        page++;
      }
      return out;
    } catch (_) {
      return null; // hide the column; never invent a zero
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


  /// [key] scopes the progress to the control that was tapped (UX-83).
  Future<void> _run(Future<void> Function() action, String okMsg,
      {required String key}) async {
    setState(() => _busy.add(key));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(okMsg)));
      // UX-84: silent, so archiving/deactivating a shop shows the row CHANGE
      // rather than hiding it behind a full-screen spinner flash.
      await _load(silent: true);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
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
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 28),
        children: [
          if (q != null) _quotaCard(s, q),
          const SizedBox(height: IntesharSpacing.md),
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
            onSelectionChanged: _bulkBusy
                ? null
                : (v) => setState(() {
                      _showArchive = v.first;
                      // The archive is a different roster with different actions;
                      // carrying a selection across would leave shops ticked that
                      // the bar's actions cannot touch.
                      _selection = SelectionState.off;
                    }),
          ),
          const SizedBox(height: IntesharSpacing.md),
          if (_showArchive) ...[
            // Restoring a shop moves it back into the Active segment and spends
            // one of the host's POS points, so both the list and the quota
            // behind this view are stale until we reload.
            PosArchiveView(
                entityId: _effectiveId, onChanged: () => _load(silent: true)),
          ] else ...[
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (_pageBusy || (q != null && q.available <= 0))
                    ? null
                    : () => _onboardDialog(s),
                icon: _isBusy('page:onboard')
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.point_of_sale_outlined, size: 18),
                label: Text(s.onboard),
              ),
            ),
            // Only HQ drilling into an agent may grant points (B-043).
            if (_isDrill) ...[
              const SizedBox(width: IntesharSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pageBusy ? null : () => _grantToTargetDialog(s),
                  icon: _isBusy('page:grant')
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.card_giftcard, size: 18),
                  label: Text(s.grant),
                ),
              ),
            ],
          ]),
          if (q != null && q.available <= 0) ...[
            const SizedBox(height: IntesharSpacing.sm),
            // UX-28: this line told the manager to "ask headquarters" and then
            // left them to work out where. Asking is the ONLY way POS points
            // arrive (B-043: HQ distributes them, a parent agent cannot), so
            // the sentence now carries the action that performs it — a chat
            // message, prefilled, in the HQ thread.
            Row(children: [
              Expanded(
                child: Text(s.noSlots,
                    style: IntesharType.sans(12, color: cs.error)),
              ),
              if (_canAskForSlots(q)) ...[
                const SizedBox(width: IntesharSpacing.sm),
                TextButton.icon(
                  onPressed: () => showSupplyRequest(
                    context,
                    ref,
                    kind: SupplyRequestKind.posPoints,
                    current: q.available,
                  ),
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: Text(s.requestSlots),
                ),
              ],
            ]),
          ],
          const SizedBox(height: IntesharSpacing.lg),
          // B-129: find one shop without scrolling a paged list.
          Row(children: [
            Expanded(
              child: TextField(
                enabled: !_bulkBusy,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: s.searchPos,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          // UX-150: a bare x inside a search box.
                          tooltip:
                              MaterialLocalizations.of(context).deleteButtonTooltip,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchDebounce?.cancel();
                            setState(() => _query = '');
                            _load(silent: true);
                          },
                        ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            // UX-11: the same switch, in the same place, as the Batches tab.
            SelectionModeButton(
              state: _selection,
              enabled: !_bulkBusy && !_pageBusy,
              onChanged: (v) => setState(() => _selection = v),
            ),
          ]),
          if (_selection.active) ...[
            const SizedBox(height: IntesharSpacing.sm),
            SelectionBar(
              state: _selection,
              visibleIds: [for (final st in _stores) st.id],
              onChanged: (v) => setState(() => _selection = v),
              onBusyChanged: (b) => setState(() => _bulkBusy = b),
              onCompleted: () => _load(silent: true),
              unit: _S.posUnit,
              actions: _bulkActions(s),
            ),
          ],
          const SizedBox(height: IntesharSpacing.md),
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
              padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.md),
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

  /// UX-11: what a selection of shops can be told to do, in bulk.
  ///
  /// Deliberately only the two reversible lifecycle levers. Archiving is left
  /// off: it starts a countdown to permanent deletion and the server wants an
  /// authenticator code per shop, so a "batch archive" would either weaken that
  /// gate or ask for forty codes. The PIN/password/2FA resets are left off for a
  /// different reason — each one produces a secret that has to be handed to one
  /// named operator, so doing forty at once produces forty secrets nobody
  /// collected.
  List<BulkAction> _bulkActions(_S s) => [
        BulkAction(
          label: s.activate,
          icon: Icons.check_circle_outline,
          title: s.activateN,
          body: (_) => s.activateBody,
          run: (id) => _repo.setActive(id, true),
        ),
        BulkAction(
          label: s.deactivate,
          icon: Icons.block,
          // Reversible — one tap of Activate puts it back — so it stops short of
          // the type-the-count gate. It still stops shops trading, so it is
          // rendered last, in danger tone, behind a divider.
          severity: BulkSeverity.danger,
          title: s.deactivateN,
          body: (_) => s.deactivateBody,
          run: (id) => _repo.setActive(id, false),
        ),
      ];

  Widget _quotaCard(_S s, PosSlotBalance q) => BrandKpiStrip(stats: [
        (s.available, q.root ? '∞' : Formatters.money(q.available)),
        (s.used, Formatters.money(q.used)),
        (s.total, q.root ? '∞' : Formatters.money(q.total)),
      ]);



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
    for (final u in store.liveUsers) {
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
    // UX-07: a hard gate on selling (`pos_home_page` refuses every sale until it
    // is set) that was already on the object this list fetches and was rendered
    // nowhere — so the single most common "the shop can't sell" cause was
    // invisible to the only people who get the phone call.
    final locationPending = store.profile?.locationConfirmedAt == null;
    // UX-24: the roster is VIEW_REPORTS-gated. Null = we could not read it, and
    // a missing line is honest where a confident "0 د.ع" would be a lie that
    // sends a manager to top up a shop that is already funded.
    final balance = _balances?[store.id];
    final selecting = _selection.active;
    final selected = _selection.contains(store.id);
    return InkCard(
      density: CardDensity.dense,
      ruleColor: selected ? context.tones.brand : null,
      // UX-07: the whole card opens the shop's diagnostics. The row buttons keep
      // their own taps — they sit in a Wrap below and swallow theirs first.
      // UX-11: in selection mode the card ticks instead, so a roster is swept
      // with one tap per row rather than a menu per row.
      onTap: selecting
          ? () => setState(() => _selection = _selection.toggle(store.id))
          : () => showPosShopSheet(context, ref, store: store),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (selecting) ...[
            SelectionCheckbox(
              selected: selected,
              semanticLabel: name,
              onChanged: _bulkBusy
                  ? null
                  : (_) => setState(
                      () => _selection = _selection.toggle(store.id)),
            ),
            const SizedBox(width: IntesharSpacing.xs),
          ],
          Expanded(child: Text(name, style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w700))),
          // UX-144: `cs.outline` is a hairline BORDER token — as pill text on
          // white it is 1.22:1, so "موقوف" was invisible and the only real signal
          // was the absence of green. Readable neutral + an icon, so the state is
          // never carried by colour alone.
          StampPill(
            label: active ? 'POS' : s.disabled,
            color: active ? context.status.success : cs.onSurfaceVariant,
            icon: active ? Icons.check_circle_outline : Icons.block,
          ),
        ]),
        if (locationPending) ...[
          const SizedBox(height: 6),
          StampPill(
            label: s.locationPending,
            color: cs.error,
            icon: Icons.location_off_outlined,
          ),
        ],
        const SizedBox(height: IntesharSpacing.xs),
        Text(phone, style: IntesharType.mono(12, color: cs.onSurfaceVariant)),
        if (owner.isNotEmpty) Text(owner, style: IntesharType.sans(12, color: cs.onSurface)),
        if (gov.isNotEmpty) Text(governorateLabel(gov, loc), style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
        // UX-24: three surfaces listed an agent's shops and none showed money, so
        // "which of my shops is out of credit?" could not be asked anywhere.
        if (balance != null)
          Padding(
            padding: const EdgeInsets.only(top: IntesharSpacing.xs),
            child: Row(children: [
              Text('${s.balance}: ',
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
              Text(Formatters.iqd(balance.round()),
                  style: IntesharType.mono(12,
                      color: balance <= 0 ? context.status.danger : cs.onSurface,
                      w: FontWeight.w700)),
              if (balance <= 0) ...[
                const SizedBox(width: 6),
                Text(s.outOfCredit,
                    style: IntesharType.sans(12,
                        color: context.status.danger, w: FontWeight.w700)),
              ],
            ]),
          ),
        // B-130: greying four buttons with no explanation is what made this read
        // as broken. Say the shop has no POS operator, which is the actual state.
        if (phone.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: IntesharSpacing.xs),
            child: Text(
              loc == 'ar'
                  ? 'لا يوجد مستخدم نقطة بيع لهذا المتجر — إجراءات المستخدم غير متاحة'
                  : 'This shop has no POS user — operator actions are unavailable',
              style: IntesharType.sans(12, color: cs.error, w: IntesharWeight.semibold),
            ),
          ),
        const SizedBox(height: IntesharSpacing.sm2),
        // UX-83: each control carries its OWN progress and only this shop's row
        // waits — acting on one shop no longer greys out the whole list.
        Wrap(spacing: IntesharSpacing.sm, runSpacing: IntesharSpacing.sm, children: [
          _rowButton(store.id, 'edit', s.edit, () => _editDialog(s, store)),
          _rowButton(store.id, 'pin', s.resetPin,
              phone.isEmpty ? null : () => _resetPin(s, store.id, name, phone)),
          _rowButton(store.id, 'password', s.resetPassword,
              phone.isEmpty ? null : () => _resetPassword(s, store.id, name, phone)),
          _rowButton(store.id, 'totp', s.resetTotp,
              phone.isEmpty ? null : () => _resetTotp(s, store.id, name, phone)),
          _rowButton(store.id, 'active', active ? s.deactivate : s.activate,
              () => _toggleActive(s, store.id, active)),
          _rowButton(store.id, 'archive', s.revoke,
              phone.isEmpty ? null : () => _confirmArchive(s, store, phone),
              style: OutlinedButton.styleFrom(foregroundColor: cs.error)),
        ]),
      ]),
    );
  }

  /// One control on a POS card. Shows a spinner in place of its own label while
  /// it works, and disables only the controls of the SAME shop meanwhile (UX-83).
  Widget _rowButton(String storeId, String action, String label, VoidCallback? onPressed,
      {ButtonStyle? style}) {
    final key = '$storeId:$action';
    final busy = _isBusy(key);
    return OutlinedButton(
      style: style,
      onPressed: (onPressed == null || _pageBusy || _bulkBusy || _rowBusy(storeId))
          ? null
          : onPressed,
      child: busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label),
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
    await _run(() => _repo.setActive(storeId, !active), s.done, key: '$storeId:active');
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
        s.done,
        key: '${store.id}:archive');
  }

  /// Reset the POS PIN and reveal the fresh manager-visible PIN once (B-047).
  Future<void> _resetTotp(_S s, String storeId, String name, String phone) async {
    if (!await confirmResetTotp(context, posName: name)) return;
    await _run(() => _repo.resetTotp(phone), s.done, key: '$storeId:totp');
  }

  Future<void> _resetPin(_S s, String storeId, String name, String phone) async {
    if (!await confirmResetPin(context, posName: name)) return;
    if (!mounted) return;
    final key = '$storeId:pin';
    setState(() => _busy.add(key));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pin = await _repo.resetPin(phone);
      await _load(silent: true);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.pinResetTitle),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.pinResetBody, style: IntesharType.sans(14, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: IntesharSpacing.lg),
            SelectableText(
              pin,
              style: IntesharType.codec(size: 40, w: FontWeight.w900, letterSpacing: 8),
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
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  /// Change a POS user's login password (B-047).
  Future<void> _resetPassword(_S s, String storeId, String name, String phone) async {
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
      await _run(() => _repo.resetPassword(phone, ctrl.text.trim()), s.passwordResetDone,
          key: '$storeId:password');
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
                const SizedBox(height: IntesharSpacing.sm),
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
                const SizedBox(height: IntesharSpacing.xs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    linkError ??
                        (hint == null
                            ? s.locationHintNone
                            : '${s.locationFound}: ${hint!.latitude.toStringAsFixed(5)}, ${hint!.longitude.toStringAsFixed(5)}'),
                    style: IntesharType.sans(
                      12,
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
      setState(() => _busy.add('page:onboard'));
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
        await _load(silent: true);
      } catch (e) {
        if (!mounted) return;
        if (isDuplicatePhone(e)) {
          await _showAlreadyExistsDialog(s, phone.text.trim(), serverReason(e));
        } else {
          messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
        }
      } finally {
        if (mounted) setState(() => _busy.remove('page:onboard'));
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
          const SizedBox(height: IntesharSpacing.sm),
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
        key: '${store.id}:edit',
      );
    }
  }

  /// Drill mode: HQ grants slots straight to the target agent (no recipient picker).
  ///
  /// UX-73: this field had NO validator and no `Form`, and the result was gated on
  /// `n > 0` after the dialog closed — so clearing the box or typing 0 dismissed
  /// the dialog and granted nothing, silently. POS slots are the scarce thing
  /// agents chase HQ for, so that silence reads as "HQ says they granted them, we
  /// see nothing". Validated like every other dialog on this page.
  Future<void> _grantToTargetDialog(_S s) async {
    final countCtrl = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.grant} — ${widget.targetName ?? ''}'.trim()),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: _field(countCtrl, s.count,
              keyboard: TextInputType.number,
              digitsOnly: true,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return s.required;
                final n = int.tryParse(t);
                if (n == null || n < 1) return s.atLeastOne;
                return null;
              }),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
            },
            child: Text(s.grant),
          ),
        ],
      ),
    );
    final n = int.tryParse(countCtrl.text.trim()) ?? 0;
    if (ok == true && n > 0) {
      await _run(() => _repo.grantSlots(destId: _effectiveId ?? '', count: n), s.done,
          key: 'page:grant');
    }
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false,
      TextInputType? keyboard,
      bool digitsOnly = false,
      String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IntesharSpacing.xs),
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
