import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/shared/widgets/map_location_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_slot_balance.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_network_view.dart';
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
  String get revoke => p('Revoke', 'إلغاء الوصول');
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
  String get noMatches => p('No matching agents', 'لا يوجد وكلاء مطابقون');
  String get mainAgents => p('Main agents', 'الوكلاء الرئيسيون');
  String get subAgents => p('Sub agents', 'الوكلاء الفرعيون');
  String get done => p('Done', 'تم');
  String get change => p('Change', 'تغيير');
  String get pickOnMap => p('Pick on map', 'تحديد على الخريطة');
  String get locationHintNone =>
      p('Location (optional hint)', 'الموقع (اختياري — مبدئي)');
  String get revokeConfirm => p('Revoke this POS user? Their login stops and the slot is returned.',
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
}

class _PosAdminPageState extends ConsumerState<PosAdminPage> {
  List<Entity> _stores = const [];
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

  @override
  void initState() {
    super.initState();
    if (!_showNetwork) _load();
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
      final stores = await _repo.list(entityId: id);
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _quota = quota;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
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
    if (_showNetwork) return const PosNetworkView();
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
          if (_stores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text(s.empty, style: IntesharType.sans(14, color: cs.onSurfaceVariant))),
            )
          else
            for (final st in _stores) _posCard(s, st, loc, cs),
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
  EntityUser? _operator(Entity store) {
    for (final u in store.users) {
      if (u.isPos) return u;
    }
    return store.users.isNotEmpty ? store.users.first : null;
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
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _busy ? null : () => _editDialog(s, store), child: Text(s.edit)),
          OutlinedButton(onPressed: (_busy || phone.isEmpty) ? null : () => _resetPin(s, name, phone), child: Text(s.resetPin)),
          OutlinedButton(onPressed: (_busy || phone.isEmpty) ? null : () => _resetPassword(s, name, phone), child: Text(s.resetPassword)),
          OutlinedButton(onPressed: (_busy || phone.isEmpty) ? null : () => _run(() => _repo.resetTotp(phone), s.done), child: Text(s.resetTotp)),
          OutlinedButton(
            onPressed: _busy ? null : () => _toggleActive(s, store.id, active),
            child: Text(active ? s.deactivate : s.activate),
          ),
          OutlinedButton(
            onPressed: (_busy || phone.isEmpty) ? null : () => _confirmRevoke(s, phone),
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

  Future<void> _confirmRevoke(_S s, String phone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(s.revokeConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.revoke)),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _repo.revoke(entityId: _effectiveId ?? '', phone: phone), s.done);
    }
  }

  /// Reset the POS PIN and reveal the fresh manager-visible PIN once (B-047).
  Future<void> _resetPin(_S s, String name, String phone) async {
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
                Row(children: [
                  Expanded(
                    child: Text(
                      hint == null
                          ? s.locationHintNone
                          : '${hint!.latitude.toStringAsFixed(5)}, ${hint!.longitude.toStringAsFixed(5)}',
                      style: IntesharType.sans(12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(hint == null ? s.pickOnMap : s.change),
                    onPressed: () async {
                      final picked = await pickLocationOnMap(ctx, initial: hint);
                      if (picked != null) setD(() => hint = picked);
                    },
                  ),
                ]),
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
      await _run(
        () => _repo.onboard(
          entityId: _effectiveId ?? '',
          phone: phone.text.trim(),
          password: pw.text,
          posName: name.text.trim(),
          posOwnerName: owner.text.trim(),
          posGovernorate: gov,
          posAddress: addr.text.trim(),
          posLatitude: hint?.latitude,
          posLongitude: hint?.longitude,
        ),
        s.done,
      );
    }
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
