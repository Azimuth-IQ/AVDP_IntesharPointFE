import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/password_field.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

enum _TotpStep { credentials, enroll, code, changePassword }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _remember = false; // G17: pre-fill the phone next time
  bool _loading = false;
  String? _error;
  _TotpStep _totpStep = _TotpStep.credentials;
  String _otpauthUri = '';
  String _secret = '';
  final _totpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // G17: restore a remembered phone so a daily operator doesn't retype it.
    sessionStorage.getRememberedPhone().then((phone) {
      if (!mounted || phone == null || phone.isEmpty) return;
      setState(() {
        _phoneCtrl.text = phone;
        _remember = true;
      });
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _totpCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _resetToCredentials() {
    setState(() {
      _totpStep = _TotpStep.credentials;
      _totpCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      // Clear any in-progress enrollment data so a stale QR/secret can't linger
      // when the next sign-in (e.g. a different account) is attempted.
      _otpauthUri = '';
      _secret = '';
      _error = null;
    });
  }

  Future<void> _changePassword() async {
    final newPass = _newPassCtrl.text;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    if (newPass.isEmpty) {
      setState(
        () => _error = ar ? 'أدخل كلمة مرور جديدة' : 'Enter a new password',
      );
      return;
    }
    if (newPass != _confirmPassCtrl.text) {
      setState(
        () => _error = ar
            ? 'كلمتا المرور غير متطابقتين'
            : 'Passwords do not match',
      );
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final outcome = await ref
        .read(authStateProvider.notifier)
        .changePassword(
          _phoneCtrl.text.trim(),
          _passCtrl.text, // the password they just signed in with
          newPass,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (outcome is LoginPasswordChanged) {
      // B-011: no session was created — send the user back to sign in with the
      // new password so the second factor (TOTP/SMS OTP) is enforced by /login.
      _passCtrl.clear();
      _resetToCredentials();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ar
                ? 'تم تغيير كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.'
                : 'Password changed. Sign in with your new password.',
          ),
        ),
      );
    } else if (outcome is LoginFailed) {
      setState(() => _error = _friendlyLoginError(outcome.statusCode));
    }
  }

  /// A friendly, localized login error keyed by HTTP status — never the raw backend/
  /// exception string. 401 (wrong password) is the common case.
  String _friendlyLoginError(int? statusCode) {
    final l = AppLocalizations.of(context)!;
    return switch (statusCode) {
      401 => l.errWrongCredentials,
      403 => l.errAccessDenied,
      int s when s >= 500 => l.errServer,
      _ => l.errGeneric,
    };
  }

  Future<void> _signIn() async {
    if (_totpStep == _TotpStep.credentials &&
        !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final code = _totpStep == _TotpStep.credentials
        ? null
        : _totpCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final outcome = await ref
        .read(authStateProvider.notifier)
        .login(phone, _passCtrl.text, totp: code);
    // G17: persist (or forget) the phone once the password step is accepted —
    // i.e. any outcome other than a hard failure means the credentials were valid.
    if (outcome is! LoginFailed) {
      await sessionStorage.setRememberedPhone(_remember ? phone : '');
    }
    if (!mounted) return;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    setState(() {
      _loading = false;
      switch (outcome) {
        case LoginDone():
          break; // the authState listener navigates home
        case LoginEnroll(:final otpauthUri, :final secret, :final message):
          _totpStep = _TotpStep.enroll;
          _otpauthUri = otpauthUri;
          _secret = secret;
          _error = message;
        case LoginNeedsCode(:final message):
          _totpStep = _TotpStep.code;
          _error = message;
        case LoginNeedsPasswordChange():
          _totpStep = _TotpStep.changePassword;
          _error = null;
        case LoginPasswordChanged():
          // Only produced by the change-password flow, never by login(); handled
          // in _changePassword. No-op here to keep the switch exhaustive.
          break;
        case LoginFailed(:final statusCode):
          // On the 2FA step the password was already accepted, so a 4xx means the
          // 6-digit code was wrong — say so, don't recycle "wrong credentials".
          final onCode =
              _totpStep == _TotpStep.code || _totpStep == _TotpStep.enroll;
          _error = (onCode && (statusCode == null || statusCode < 500))
              ? (ar ? 'رمز التحقق غير صحيح' : 'Incorrect verification code')
              : _friendlyLoginError(statusCode);
      }
    });
  }

  Future<void> _showUrlSheet() async {
    final current = await sessionStorage.getBaseUrl();
    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final lCtx = AppLocalizations.of(ctx)!;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SectionLabel(lCtx.loginServerEndpoint),
              Text(
                lCtx.loginServerUrl,
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: lCtx.loginBaseUrlLabel,
                  hintText: 'http://192.168.1.x:8080',
                ),
              ),
              const SizedBox(height: 16),
              BrandCTAButton(
                label: lCtx.loginSaveEndpoint,
                variant: BrandCTAVariant.inverse,
                onPressed: () async {
                  // Validate before saving — a typo silently pointed the app at a
                  // dead backend with no feedback (B-080).
                  final url = ctrl.text.trim();
                  final uri = Uri.tryParse(url);
                  final valid =
                      url.isNotEmpty &&
                      uri != null &&
                      (uri.isScheme('http') || uri.isScheme('https')) &&
                      uri.host.isNotEmpty;
                  if (!valid) {
                    final ar = Localizations.localeOf(ctx).languageCode == 'ar';
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          ar
                              ? 'أدخل رابطاً صحيحاً يبدأ بـ ‎http(s)://'
                              : 'Enter a valid http(s):// URL',
                        ),
                      ),
                    );
                    return;
                  }
                  await sessionStorage.setBaseUrl(url);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (_, next) {
      if (next.hasValue && next.value is AuthAuthenticated) {
        context.go((next.value as AuthAuthenticated).homeRoute);
      }
    });

    final l = AppLocalizations.of(context)!;
    final authState = ref.watch(authStateProvider);
    final isAuthenticated = authState.valueOrNull is AuthAuthenticated;

    final isWide = context.isWide;

    final Widget formCard = _totpStep == _TotpStep.changePassword
        ? _ChangePasswordForm(
            newPassCtrl: _newPassCtrl,
            confirmPassCtrl: _confirmPassCtrl,
            loading: _loading,
            error: _error,
            onSubmit: _changePassword,
          )
        : _totpStep != _TotpStep.credentials
        ? _TotpChallenge(
            enroll: _totpStep == _TotpStep.enroll,
            otpauthUri: _otpauthUri,
            secret: _secret,
            codeCtrl: _totpCtrl,
            loading: _loading,
            error: _error,
            onVerify: _signIn,
            onBack: _resetToCredentials,
          )
        : _LoginForm(
            formKey: _formKey,
            phoneCtrl: _phoneCtrl,
            passCtrl: _passCtrl,
            obscure: _obscure,
            onToggleObscure: () => setState(() => _obscure = !_obscure),
            remember: _remember,
            onToggleRemember: (v) => setState(() => _remember = v),
            loading: _loading,
            error: _error,
            isAuthenticated: isAuthenticated,
            l: l,
            onSignIn: _signIn,
            onShowUrlSheet: _showUrlSheet,
          );

    // Intercept the system/browser back button while on enroll or code step so
    // that pressing device-back resets to the credentials view (clearing any
    // stale QR/secret/code state) rather than popping the login route.
    return PopScope<Object?>(
      canPop: _totpStep == _TotpStep.credentials,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _totpStep != _TotpStep.credentials) {
          _resetToCredentials();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: isWide
              ? Row(
                  children: [
                    Expanded(child: _BrandPanel()),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(32),
                            child: formCard,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    GestureDetector(
                      onLongPress: () => context.push('/diagnostics'),
                      behavior: HitTestBehavior.opaque,
                      child: const _MobileBrandHeader(),
                    ),
                    // B-094: centre the card in the space that's left instead of
                    // top-aligning it. `Center` inside a scroll view does nothing
                    // vertically (unbounded height), which is why a third of the
                    // phone screen sat empty; the minHeight makes it centre when
                    // there's room and still scroll when the keyboard is up.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: c.maxHeight - 48,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 460,
                                ),
                                child: formCard,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Two-factor step shown after a correct password: a QR + manual key on first
/// enrollment (bind an authenticator app), or just a code field on every login after.
class _TotpChallenge extends StatelessWidget {
  final bool enroll;
  final String otpauthUri;
  final String secret;
  final TextEditingController codeCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onVerify;
  final VoidCallback onBack;
  const _TotpChallenge({
    required this.enroll,
    required this.otpauthUri,
    required this.secret,
    required this.codeCtrl,
    required this.loading,
    required this.error,
    required this.onVerify,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  enroll
                      ? (ar ? 'إعداد المصادقة الثنائية' : 'Set up two-factor')
                      : (ar
                            ? 'المصادقة الثنائية'
                            : 'Two-factor authentication'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            enroll
                ? (ar
                      ? 'امسح الرمز بتطبيق مصادقة (مثل Google Authenticator)، ثم أدخل الرمز المكوّن من 6 أرقام لتأكيد الربط.'
                      : 'Scan the QR with an authenticator app (e.g. Google Authenticator), then enter the 6-digit code to finish setup.')
                : (ar
                      ? 'أدخل الرمز المكوّن من 6 أرقام من تطبيق المصادقة.'
                      : 'Enter the 6-digit code from your authenticator app.'),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          if (enroll) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(data: otpauthUri, size: 184),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              ar ? 'أو أدخل المفتاح يدوياً:' : 'Or enter this key manually:',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            SelectableText(
              secret,
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                letterSpacing: 1.5,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              ar
                  ? 'إذا كان الرمز السابق لا يعمل، احذف المدخل القديم من تطبيق المصادقة ثم امسح هذا الرمز من جديد.'
                  : 'If a previously scanned code no longer works, delete that old entry from your authenticator app and scan this QR again.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            // Half-enrolled hint: if the user already added the entry in a
            // previous session that was abandoned, the server reuses the same
            // secret — they don't need to rescan, just enter the current code.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.tips_and_updates_outlined,
                    size: 14,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ar
                          ? 'هل أضفت إنتشار إلى تطبيق المصادقة مسبقاً؟ فقط أدخل الرمز المكوّن من 6 أرقام أدناه — لا حاجة لإعادة المسح.'
                          : 'Already added Inteshar to your authenticator? Just enter the current 6-digit code below — no need to rescan.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 10,
              fontFamily: 'JetBrainsMono',
            ),
            decoration: InputDecoration(
              labelText: ar ? 'رمز التحقق' : 'Verification code',
              counterText: '',
            ),
            onSubmitted: (_) => onVerify(),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onVerify,
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      enroll
                          ? (ar ? 'تأكيد وربط' : 'Confirm & bind')
                          : (ar ? 'تحقق' : 'Verify'),
                    ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: loading ? null : onBack,
              child: Text(ar ? 'رجوع' : 'Back'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forced password-change step (auth Phase 4) — shown after a correct password when
/// the account is flagged/expired for rotation. The old password is the one just
/// entered; on success the user is signed straight in.
class _ChangePasswordForm extends StatelessWidget {
  final TextEditingController newPassCtrl;
  final TextEditingController confirmPassCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;
  const _ChangePasswordForm({
    required this.newPassCtrl,
    required this.confirmPassCtrl,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return InkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.lock_reset, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ar ? 'تغيير كلمة المرور' : 'Change your password',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ar
                ? 'يجب تعيين كلمة مرور جديدة قبل المتابعة.'
                : 'You must set a new password before continuing.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          // B-080: say this BEFORE they submit. Changing the password mints no
          // token by design (B-011 — a token here would skip the second factor),
          // so the user lands back on sign-in. Without the warning that reads as
          // "it failed" and people retype the old password.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ar
                      ? 'بعد الحفظ سيُطلب منك تسجيل الدخول مرة أخرى بكلمة المرور الجديدة.'
                      : "After saving you'll be asked to sign in again with the new password.",
                  style: IntesharType.sans(12, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: newPassCtrl,
            label: ar ? 'كلمة المرور الجديدة' : 'New password',
          ),
          const SizedBox(height: 12),
          PasswordField(
            controller: confirmPassCtrl,
            label: ar ? 'تأكيد كلمة المرور' : 'Confirm password',
            onSubmitted: (_) => onSubmit(),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: loading ? null : onSubmit,
              child: loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(ar ? 'حفظ وتسجيل الدخول' : 'Save & sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

/// B-094: the sign-in brand panel is now WHITE-dominant. It used to be a full-bleed
/// gold band, which is why the whole app read as gold no matter what we re-themed.
/// Gold survives as a precise accent — the star and a short rule — over paper.
class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tones = context.tones;
    return GestureDetector(
      onLongPress: () => context.push('/diagnostics'),
      behavior: HitTestBehavior.opaque,
      child: ColoredBox(
        color: cs.surface,
        // B-094: centre a fixed-width brand block in this half rather than letting
        // it hug the outer edge — with the form centred in the other half, edge-
        // aligning here opened a dead channel down the middle of the page.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IntesharStar(size: 44, color: tones.brand),
                  const SizedBox(height: 32),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'Inteshar',
                      style: TextStyle(
                        fontFamily: 'CodecPro',
                        color: cs.onSurface,
                        fontSize: 76,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -2.6,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // The one deliberate flash of brand colour on the panel.
                  Container(width: 56, height: 3, color: tones.brand),
                  const SizedBox(height: 20),
                  Text(
                    l.loginBrandTagline,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      color: cs.onSurfaceVariant,
                      fontSize: 16.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// B-094: the mobile sign-in header — white, compact, typographic. Replaces the
/// gold band that dominated the first screen every operator sees.
class _MobileBrandHeader extends StatelessWidget {
  const _MobileBrandHeader();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tones = context.tones;
    return ColoredBox(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IntesharStar(size: 30, color: tones.brand),
                const SizedBox(width: 12),
                Text(
                  'Inteshar',
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    color: cs.onSurface,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l.loginBrandTaglineShort,
              style: TextStyle(
                fontFamily: 'CodecPro',
                fontSize: 14,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginForm extends ConsumerWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool remember;
  final ValueChanged<bool> onToggleRemember;
  final bool loading;
  final String? error;
  final bool isAuthenticated;
  final AppLocalizations l;
  final VoidCallback onSignIn;
  final VoidCallback onShowUrlSheet;

  const _LoginForm({
    required this.formKey,
    required this.phoneCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.remember,
    required this.onToggleRemember,
    required this.loading,
    required this.error,
    required this.isAuthenticated,
    required this.l,
    required this.onSignIn,
    required this.onShowUrlSheet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A9: ar/en language toggle at the top of the login card.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () =>
                  ref.read(localeControllerProvider.notifier).toggle(),
              icon: const Icon(Icons.language, size: 18),
              label: Text(ar ? 'English' : 'العربية'),
            ),
          ),
          Text(
            l.loginWelcomeBack,
            style: IntesharType.display(
              34,
              color: cs.onSurface,
              w: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.loginSubtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: IntesharType.mono(
              14,
              color: cs.onSurface,
              letterSpacing: 0.6,
            ),
            decoration: InputDecoration(
              labelText: l.loginPhone,
              hintText: '07701234567',
              prefixIcon: const Icon(Icons.phone_outlined, size: 18),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? l.loginFieldRequired : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: passCtrl,
            obscureText: obscure,
            style: IntesharType.mono(
              14,
              color: cs.onSurface,
              letterSpacing: 1.2,
            ),
            decoration: InputDecoration(
              labelText: l.loginPassword,
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            validator: (v) =>
                v == null || v.isEmpty ? l.loginFieldRequired : null,
          ),
          // G17: remember-me pre-fills the phone on the next launch.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: InkWell(
              onTap: () => onToggleRemember(!remember),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: remember,
                        onChanged: (v) => onToggleRemember(v ?? false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      ar ? 'تذكّر رقم الهاتف' : 'Remember my phone',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            _Banner(
              tone: cs.error,
              icon: Icons.error_outline,
              title: l.loginAuthDeclined,
              body: error!,
            ),
          ],
          const SizedBox(height: 24),
          // The server-endpoint sheet is intentionally hidden behind a long-press
          // on the sign-in button (no visible field) — testers/admins can still
          // reach it to point the app at a different backend.
          BrandCTAButton(
            label: l.loginSignIn,
            trailing: Icons.arrow_forward,
            loading: loading,
            onPressed: loading ? null : onSignIn,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              onShowUrlSheet();
            },
          ),
          // A8: forgot password → notifies the account's supervisor (the agent).
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: () => _forgotPassword(context, ref, ar),
              child: Text(ar ? 'نسيت كلمة المرور؟' : 'Forgot password?'),
            ),
          ),
        ],
      ),
    );
  }

  /// A8: ask the backend to notify the supervisor. Public + rate-limited; the
  /// response is deliberately the same whether or not the phone exists.
  Future<void> _forgotPassword(
    BuildContext context,
    WidgetRef ref,
    bool ar,
  ) async {
    final ctrl = TextEditingController(text: phoneCtrl.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ar ? 'إعادة تعيين كلمة المرور' : 'Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ar
                  ? 'أدخل رقم هاتفك وسيصل طلب إلى وكيلك لإعادة تعيين كلمة المرور.'
                  : 'Enter your phone and a reset request will be sent to your agent.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: ar ? 'رقم الهاتف' : 'Phone',
                hintText: '07701234567',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ar ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ar ? 'إرسال' : 'Send'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            Endpoints.authForgotPassword,
            data: {'phone': ctrl.text.trim()},
          );
    } catch (_) {
      // Same generic outcome regardless — never reveal whether the phone exists.
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ar
              ? 'إذا كان الحساب موجوداً، فقد تم إشعار وكيلك.'
              : 'If the account exists, your agent was notified.',
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color tone;
  final IconData icon;
  final String title;
  final String body;
  const _Banner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  color: tone,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 12.5,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
