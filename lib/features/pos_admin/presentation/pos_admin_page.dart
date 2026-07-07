import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_slot_balance.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// POS-user quota + lifecycle for the signed-in entity (POS-quota model, Docs/POS-QUOTA-PLAN.md).
/// Shows total/used/available slots, onboards POS users (consuming a slot), grants slots to a
/// direct child, and manages each POS user (reset PIN / reset TOTP / revoke).
class PosAdminPage extends ConsumerStatefulWidget {
  const PosAdminPage({super.key});

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
  String get noSlots => p('No available slots — ask your parent to grant more.', 'لا توجد نقاط متاحة — اطلب من الوكيل الأعلى منحك المزيد.');
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
  String get toChild => p('To (direct child)', 'إلى (تابع مباشر)');
  String get done => p('Done', 'تم');
  String get revokeConfirm => p('Revoke this POS user? Their login stops and the slot is returned.',
      'إلغاء هذه النقطة؟ سيتوقف دخولها وتعود النقطة للرصيد.');
}

class _PosAdminPageState extends ConsumerState<PosAdminPage> {
  Entity? _entity;
  PosSlotBalance? _quota;
  List<Entity> _children = const [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  PosAdminRepository get _repo => PosAdminRepository(ref.read(apiClientProvider));
  String? get _myId => (ref.read(authStateProvider).valueOrNull as AuthAuthenticated?)?.entity.id;

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
      final id = _myId ?? '';
      final api = ref.read(apiClientProvider);
      final entity = await EntityRepository(api).read(id);
      final quota = await _repo.quota(entityId: id);
      final all = await EntityRepository(api).readAll();
      if (!mounted) return;
      setState(() {
        _entity = entity;
        _quota = quota;
        _children = all.where((e) => e.parent == id).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  List<EntityUser> get _posUsers => (_entity?.users ?? const []).where((u) => u.isPos).toList();

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
    final s = _S.of(context);
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
            if (_children.isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _grantDialog(s),
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
          if (_posUsers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text(s.empty, style: IntesharType.sans(14, color: cs.onSurfaceVariant))),
            )
          else
            for (final u in _posUsers) _posCard(s, u, loc, cs),
        ],
      ),
    );
  }

  Widget _quotaCard(_S s, PosSlotBalance q) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: IntesharColors.saffron, borderRadius: BorderRadius.circular(IntesharRadii.lg)),
      child: Row(children: [
        _stat(s.available, q.root ? '∞' : '${q.available}'),
        _divider(),
        _stat(s.used, '${q.used}'),
        _divider(),
        _stat(s.total, q.root ? '∞' : '${q.total}'),
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

  Widget _posCard(_S s, EntityUser u, String loc, ColorScheme cs) {
    return InkCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(u.posName.isNotEmpty ? u.posName : u.phone, style: IntesharType.sans(15, color: cs.onSurface, w: FontWeight.w700))),
          StampPill(label: 'POS', color: IntesharColors.sage),
        ]),
        const SizedBox(height: 4),
        Text(u.phone, style: IntesharType.mono(12, color: cs.onSurfaceVariant)),
        if (u.posOwnerName.isNotEmpty) Text(u.posOwnerName, style: IntesharType.sans(12.5, color: cs.onSurface)),
        if (u.posGovernorate.isNotEmpty) Text(governorateLabel(u.posGovernorate, loc), style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(onPressed: _busy ? null : () => _run(() => _repo.resetPin(u.phone), s.done), child: Text(s.resetPin)),
          OutlinedButton(onPressed: _busy ? null : () => _run(() => _repo.resetTotp(u.phone), s.done), child: Text(s.resetTotp)),
          OutlinedButton(
            onPressed: _busy ? null : () => _confirmRevoke(s, u),
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            child: Text(s.revoke),
          ),
        ]),
      ]),
    );
  }

  Future<void> _confirmRevoke(_S s, EntityUser u) async {
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
      await _run(() => _repo.revoke(entityId: _myId ?? '', phone: u.phone), s.done);
    }
  }

  Future<void> _onboardDialog(_S s) async {
    final phone = TextEditingController();
    final pw = TextEditingController();
    final name = TextEditingController();
    final owner = TextEditingController();
    final addr = TextEditingController();
    String? gov;
    final loc = Localizations.localeOf(context).languageCode;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.onboard),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field(phone, s.phone, keyboard: TextInputType.phone, digitsOnly: true),
              _field(pw, s.password, obscure: true),
              _field(name, s.posName),
              _field(owner, s.ownerName),
              DropdownButtonFormField<String>(
                initialValue: gov,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.governorate, isDense: true),
                items: [for (final g in kGovernorates) DropdownMenuItem(value: g.code, child: Text(governorateLabel(g.code, loc)))],
                onChanged: (v) => setD(() => gov = v),
              ),
              _field(addr, s.address),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.create)),
          ],
        ),
      ),
    );
    if (ok == true && phone.text.trim().isNotEmpty && pw.text.isNotEmpty) {
      await _run(
        () => _repo.onboard(
          entityId: _myId ?? '',
          phone: phone.text.trim(),
          password: pw.text,
          posName: name.text.trim(),
          posOwnerName: owner.text.trim(),
          posGovernorate: gov,
          posAddress: addr.text.trim(),
        ),
        s.done,
      );
    }
  }

  Future<void> _grantDialog(_S s) async {
    final countCtrl = TextEditingController(text: '1');
    String? childId = _children.isNotEmpty ? _children.first.id : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.grant),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: childId,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.toChild, isDense: true),
              items: [for (final c in _children) DropdownMenuItem(value: c.id, child: Text(c.meta.name, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setD(() => childId = v),
            ),
            _field(countCtrl, s.count, keyboard: TextInputType.number, digitsOnly: true),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.grant)),
          ],
        ),
      ),
    );
    final n = int.tryParse(countCtrl.text.trim()) ?? 0;
    if (ok == true && childId != null && n > 0) {
      await _run(() => _repo.grantSlots(destId: childId!, count: n), s.done);
    }
  }

  Widget _field(TextEditingController c, String label,
      {bool obscure = false, TextInputType? keyboard, bool digitsOnly = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
