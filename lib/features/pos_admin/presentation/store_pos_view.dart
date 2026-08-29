import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/features/pos_admin/presentation/confirm_operator_reset.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/pos_admin/data/pos_admin_repository.dart';
import 'package:inteshar/features/pos_admin/domain/pos_roles.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/password_field.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// What the نقطة البيع section means for a STORE-tier owner.
///
/// Every other tier gets [PosAdminPage]'s agent body: a slot quota, an "Onboard
/// POS" button and the list of shops it hosts. For a STORE that body is a lie
/// end to end — a store IS a point of sale:
///
///  * `/pos-users/list/page` returns the host's STORE **children**, and nothing
///    can create a store under a store (`onboard` rejects a non-agent host;
///    the hierarchy tree offers no child type for STORE), so the list is
///    structurally always empty.
///  * the quota therefore reads 0/0/0 and the page nagged the shop owner to
///    "ask headquarters to grant more" points they could never spend.
///  * and if HQ ever did grant some, the button would enable and the onboard
///    request would 400 after a six-field form.
///
/// So the store gets the honest version of the same section: the shop's own POS
/// identity, plus the counter-credential actions that are genuinely authorised
/// for it (the backend scopes `reset-pin` / `reset-password` / `reset-totp` to
/// self-or-descendant, and a store's own operator is "self").
class StorePosView extends ConsumerStatefulWidget {
  const StorePosView({super.key});

  @override
  ConsumerState<StorePosView> createState() => _StorePosViewState();
}

class _S {
  final bool ar;
  const _S(this.ar);
  factory _S.of(BuildContext c) => _S(Localizations.localeOf(c).languageCode == 'ar');
  String p(String en, String a) => ar ? a : en;
  String get eyebrow => p('POS point', 'نقطة البيع');
  String get title => p('My POS', 'نقطة البيع');
  String get subtitle =>
      p('This account is the point of sale', 'هذا الحساب هو نقطة البيع');
  String get noteTitle => p('This shop IS the POS point', 'هذا المتجر هو نقطة البيع');
  String get noteBody => p(
      'POS points are opened for you by your agent — a shop does not add points of its own. What you manage here is the counter login of this shop.',
      'نقاط البيع يفتحها لك وكيلك — المتجر لا يضيف نقاط بيع خاصة به. ما تديره هنا هو حساب الكاشير الخاص بهذا المتجر.');
  String get counter => p('Counter login', 'حساب الكاشير');
  String get noCounter => p('No counter login on this shop', 'لا يوجد حساب كاشير لهذا المتجر');
  String get noCounterBody => p(
      'Ask your agent to set up the point-of-sale login for this shop.',
      'اطلب من وكيلك إنشاء حساب نقطة البيع لهذا المتجر.');
  String get legacyCounter => p(
      'This login is not registered as a point-of-sale user, so its PIN and 2FA cannot be reset from here. Ask your agent.',
      'هذا الحساب غير مسجّل كمستخدم نقطة بيع، لذلك لا يمكن إعادة تعيين رمزه أو تحققه من هنا. راجع وكيلك.');
  String get owner => p('Owner', 'المالك');
  String get governorate => p('Governorate', 'المحافظة');
  String get address => p('Address', 'العنوان');
  String get disabled => p('Disabled', 'موقوف');
  String get resetPin => p('Reset PIN', 'إعادة تعيين الرمز');
  String get resetPassword => p('Reset password', 'تغيير كلمة المرور');
  String get resetTotp => p('Reset 2FA', 'إعادة تعيين المصادقة');
  String get resetTotpConfirm => p(
      'Reset two-factor for the counter? The operator must re-enrol on their next sign-in.',
      'إعادة تعيين المصادقة الثنائية للكاشير؟ سيحتاج المشغّل إلى إعادة التسجيل عند الدخول القادم.');
  String get newPassword => p('New password', 'كلمة المرور الجديدة');
  String get passwordTooShort => p('At least 6 characters', '6 أحرف على الأقل');
  String get passwordResetDone => p('Password changed', 'تم تغيير كلمة المرور');
  String get pinResetTitle => p('New POS PIN', 'رمز نقطة البيع الجديد');
  String get pinResetBody => p('Give this PIN to the operator — it will not be shown again.',
      'سلّم هذا الرمز للمشغّل — لن يُعرض مرة أخرى.');
  String get cancel => p('Cancel', 'إلغاء');
  String get save => p('Save', 'حفظ');
  String get close => p('Close', 'إغلاق');
  String get done => p('Done', 'تم');
}

class _StorePosViewState extends ConsumerState<StorePosView> {
  /// UX-83: WHICH action is running ('pin' | 'password' | 'totp'), not just
  /// "something is". A page-wide bool greyed all three buttons and put the
  /// spinner on none of them, so the only feedback was everything going grey.
  String? _busy;

  PosAdminRepository get _repo => PosAdminRepository(ref.read(apiClientProvider));

  Future<void> _run(Future<void> Function() action, String okMsg, {required String key}) async {
    setState(() => _busy = key);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// A counter action that shows its own progress in place of its label.
  Widget _actionButton(String key, String label, VoidCallback onPressed) => OutlinedButton(
        onPressed: _busy == null ? onPressed : null,
        child: _busy == key
            ? const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final auth = ref.watch(authStateProvider).valueOrNull;
    final store = (auth is AuthAuthenticated) ? auth.entity : null;
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context).languageCode;
    final counter = store == null ? null : counterUserOf(store);

    return MaxWidthBox(
      maxWidth: 760,
      child: Column(
        children: [
          // Section title, not the shop name — the identity card below carries
          // that, and every other tier's POS screen is titled the same way.
          PageHeader(eyebrow: s.eyebrow, title: s.title, subtitle: s.subtitle),
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 28),
              children: [
                _note(s, cs),
                const SizedBox(height: 16),
                if (store != null) _identityCard(s, store, loc, cs),
                const SizedBox(height: 16),
                _counterCard(s, counter, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Says plainly why there is no "add a POS point" button here.
  Widget _note(_S s, ColorScheme cs) => Container(
        padding: const EdgeInsets.all(IntesharSpacing.lg),
        decoration: BoxDecoration(
          color: context.tones.brand.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(IntesharRadii.md),
          border: Border.all(color: context.tones.brand.withValues(alpha: 0.4)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.point_of_sale_outlined, size: 20, color: context.tones.brandInk),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.noteTitle, style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(s.noteBody, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
      );

  /// The shop's own POS identity — the row an agent sees about this shop, seen
  /// from the inside. Read-only: name/owner/governorate/address are set when the
  /// point is opened, and changing them is the agent's call, not the shop's.
  Widget _identityCard(_S s, Entity store, String loc, ColorScheme cs) {
    final owner = store.profile?.ownerName ?? '';
    final address = store.profile?.address ?? '';
    final gov = store.meta.governorates.isNotEmpty ? store.meta.governorates.first : '';
    return InkCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              store.meta.name.isNotEmpty ? store.meta.name : store.id,
              style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w800),
            ),
          ),
          // UX-144: `cs.outline` is a hairline BORDER token — 1.22:1 as text on
          // white, so "موقوف" was effectively invisible and the state was carried
          // by the absence of green alone. Readable neutral + an icon.
          StampPill(
            label: store.active ? 'POS' : s.disabled,
            color: store.active ? context.status.success : cs.onSurfaceVariant,
            icon: store.active ? Icons.check_circle_outline : Icons.block,
          ),
        ]),
        if (owner.isNotEmpty) _row(s.owner, owner, cs),
        if (gov.isNotEmpty) _row(s.governorate, governorateLabel(gov, loc), cs),
        if (address.isNotEmpty) _row(s.address, address, cs),
      ]),
    );
  }

  Widget _row(String label, String value, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 104,
            child: Text(label, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: IntesharType.sans(14, color: cs.onSurface))),
        ]),
      );

  /// The counter login + the credential actions the shop owner may actually run.
  /// Deliberately absent: revoke and deactivate (both would lock this very shop
  /// out of the system) and edit/onboard/grant, which the server refuses for a
  /// STORE anyway.
  Widget _counterCard(_S s, EntityUser? counter, ColorScheme cs) {
    if (counter == null) {
      return InkCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.noCounter, style: IntesharType.sans(14, color: cs.onSurface, w: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(s.noCounterBody, style: IntesharType.sans(12, color: cs.onSurfaceVariant)),
        ]),
      );
    }
    // Pre-isPos shops: the endpoints require the flag, so offering the buttons
    // would only produce a 403. Say why instead.
    final canManage = counter.isPos;
    return InkCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.counter, style: IntesharType.overline(color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text(counter.phone, style: IntesharType.mono(14, color: cs.onSurface)),
        const SizedBox(height: 12),
        if (!canManage)
          Text(s.legacyCounter, style: IntesharType.sans(12, color: cs.onSurfaceVariant))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            _actionButton('pin', s.resetPin, () => _resetPin(s, counter.phone)),
            _actionButton(
                'password', s.resetPassword, () => _resetPassword(s, counter.phone)),
            _actionButton('totp', s.resetTotp, () => _resetTotp(s, counter.phone)),
          ]),
      ]),
    );
  }

  /// Reset the counter PIN and reveal the fresh value ONCE (B-047 rule).
  Future<void> _resetPin(_S s, String phone) async {
    if (!await confirmResetPin(context)) return;
    if (!mounted) return;
    setState(() => _busy = 'pin');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pin = await _repo.resetPin(phone);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.pinResetTitle),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.pinResetBody,
                style: IntesharType.sans(14, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            SelectableText(
              pin,
              style: IntesharType.codec(size: 40, w: FontWeight.w900, letterSpacing: 8),
            ),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.close))],
        ),
      );
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _resetPassword(_S s, String phone) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.resetPassword),
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
          key: 'password');
    }
  }

  /// Confirmed: it forces the counter to re-enrol mid-shift.
  Future<void> _resetTotp(_S s, String phone) async {
    if (!await confirmResetTotp(context)) return;
    await _run(() => _repo.resetTotp(phone), s.done, key: 'totp');
  }
}
