import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/auth/data/auth_repository.dart';
import 'package:inteshar/features/pos/presentation/pos_brand.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/language_switcher_row.dart';
import 'package:inteshar/shared/widgets/password_field.dart';

/// الحساب (سستم A92): the shop profile — trade name, owner triple name, address,
/// nearest landmark, governorate and login phone, all READ-ONLY for the operator
/// (only the location confirm, password change and logout are theirs). Printer
/// setup stays here too.
class PosAccountPanel extends ConsumerWidget {
  final VoidCallback onOpenPrinter;
  final Future<void> Function() onSignOut;
  const PosAccountPanel({super.key, required this.onOpenPrinter, required this.onSignOut});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final loc = Localizations.localeOf(context).languageCode;
    final auth = ref.watch(authStateProvider).valueOrNull;
    final entity = auth is AuthAuthenticated ? auth.entity : null;
    final profile = entity?.profile;
    final shop = entity?.meta.name ?? '';
    final phone = entity?.liveUsers.firstOrNull?.phone ?? '';
    final gov = (entity?.meta.governorates.isNotEmpty ?? false)
        ? governorateLabel(entity!.meta.governorates.first, loc)
        : '';
    final confirmed = profile?.locationConfirmedAt != null;

    Widget row(IconData icon, String label, String value) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
              Text(value, style: IntesharType.sans(13.5, color: cs.onSurface, w: FontWeight.w600)),
            ]),
          ),
        ]),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Center(child: PosBrandMark(size: 64)),
              const SizedBox(height: 16),
              Text(shop.isEmpty ? l.posHome : shop,
                  textAlign: TextAlign.center,
                  style: IntesharType.display(22, color: cs.onSurface, w: FontWeight.w900)),
              const SizedBox(height: 20),
              // A92: profile details are set by the agent/HQ — read-only here.
              InkCard(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  row(Icons.badge_outlined, ar ? 'اسم المالك' : 'Owner', profile?.ownerName ?? ''),
                  row(Icons.phone_outlined, ar ? 'هاتف الدخول' : 'Login phone', phone),
                  row(Icons.location_city_outlined, ar ? 'المحافظة' : 'Governorate', gov),
                  row(Icons.home_outlined, ar ? 'العنوان' : 'Address', profile?.address ?? ''),
                  row(Icons.place_outlined, ar ? 'أقرب نقطة دالة' : 'Nearest landmark',
                      profile?.nearestLandmark ?? ''),
                  row(
                    confirmed ? Icons.where_to_vote_outlined : Icons.location_off_outlined,
                    ar ? 'الموقع' : 'Location',
                    confirmed
                        ? (ar ? 'مؤكد ✓' : 'Confirmed ✓')
                        : (ar ? 'غير مؤكد — مطلوب قبل البيع' : 'Not confirmed — required before selling'),
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              // B-096: the POS shell never imports the agent scaffold, so until now
              // an operator had NO way to change the language and was stuck on the
              // default. This panel is where they'd look for it.
              const InkCard(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: LanguageSwitcherRow(),
              ),
              const SizedBox(height: 20),
              BrandCTAButton(
                label: ar ? 'تغيير كلمة المرور' : 'Change password',
                leading: Icons.lock_outline,
                variant: BrandCTAVariant.outline,
                onPressed: () => _changePasswordDialog(context, ref, phone),
              ),
              const SizedBox(height: 12),
              BrandCTAButton(
                label: ar ? 'إعداد الطابعة' : 'Printer setup',
                leading: Icons.print_outlined,
                variant: BrandCTAVariant.outline,
                onPressed: onOpenPrinter,
              ),
              const SizedBox(height: 12),
              BrandCTAButton(
                label: l.signOut,
                leading: Icons.logout_outlined,
                variant: BrandCTAVariant.outline,
                onPressed: () => onSignOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A92: change the login password (old + new). On success the session is ended
  /// — change-password mints no token by design (B-011), so the operator signs
  /// back in with the new password.
  Future<void> _changePasswordDialog(BuildContext context, WidgetRef ref, String phone) async {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'تغيير كلمة المرور' : 'Change password'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            PasswordField(
              controller: oldCtrl,
              label: ar ? 'كلمة المرور الحالية' : 'Current password',
              autofocus: true,
              validator: (v) =>
                  (v == null || v.isEmpty) ? (ar ? 'مطلوب' : 'Required') : null,
            ),
            const SizedBox(height: 10),
            PasswordField(
              controller: newCtrl,
              label: ar ? 'كلمة المرور الجديدة' : 'New password',
              validator: (v) => (v == null || v.trim().length < 6)
                  ? (ar ? '٦ أحرف على الأقل' : 'At least 6 characters')
                  : null,
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ar ? 'إلغاء' : 'Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) Navigator.pop(ctx, true);
            },
            child: Text(ar ? 'حفظ' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AuthRepository(ref.read(apiClientProvider))
          .changePassword(phone, oldCtrl.text, newCtrl.text.trim());
      messenger.showSnackBar(SnackBar(
          content: Text(ar
              ? 'تم تغيير كلمة المرور — سجّل الدخول من جديد'
              : 'Password changed — sign in again')));
      await onSignOut();
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, context))));
      }
    }
  }
}
