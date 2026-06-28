import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/auth/application/seed_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/brand_band.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

enum _TotpStep { credentials, enroll, code, changePassword }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController(text: '07705371953');
  final _passCtrl = TextEditingController(text: 'root');
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  bool _showMongoHint = false;
  _TotpStep _totpStep = _TotpStep.credentials;
  String _otpauthUri = '';
  String _secret = '';
  final _totpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

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
      setState(() => _error = ar ? 'أدخل كلمة مرور جديدة' : 'Enter a new password');
      return;
    }
    if (newPass != _confirmPassCtrl.text) {
      setState(() => _error = ar ? 'كلمتا المرور غير متطابقتين' : 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final outcome = await ref.read(authStateProvider.notifier).changePassword(
          _phoneCtrl.text.trim(),
          _passCtrl.text, // the password they just signed in with
          newPass,
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (outcome is LoginFailed) {
        _error = outcome.message
            .replaceFirst('ApiException', '')
            .replaceAll('(', '')
            .replaceAll(')', '')
            .trim();
      }
      // LoginDone → the authState listener navigates home.
    });
  }

  Future<void> _signIn() async {
    if (_totpStep == _TotpStep.credentials && !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _showMongoHint = false;
    });
    final code = _totpStep == _TotpStep.credentials ? null : _totpCtrl.text.trim();
    final outcome = await ref
        .read(authStateProvider.notifier)
        .login(_phoneCtrl.text.trim(), _passCtrl.text, totp: code);
    if (!mounted) return;
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
        case LoginFailed(:final message):
          final clean = message
              .replaceFirst('ApiException', '')
              .replaceAll('(', '')
              .replaceAll(')', '')
              .trim();
          _error = clean;
          _showMongoHint = message.contains('401') ||
              message.contains('no user') ||
              message.contains('Could not find');
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
              Text(lCtx.loginServerUrl, style: Theme.of(ctx).textTheme.bodyMedium),
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
                  await sessionStorage.setBaseUrl(ctrl.text.trim());
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
            loading: _loading,
            error: _error,
            showMongoHint: _showMongoHint,
            isAuthenticated: isAuthenticated,
            l: l,
            onSignIn: _signIn,
            onShowUrlSheet: _showUrlSheet,
            onSeed: () => ref.read(seedControllerProvider.notifier).seed(context),
          );

    return Scaffold(
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
                    onLongPress: () => context.go('/diagnostics'),
                    behavior: HitTestBehavior.opaque,
                    child: const _MobileBrandHeader(),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Center(child: formCard),
                      ),
                    ),
                  ),
                ],
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
                      : (ar ? 'المصادقة الثنائية' : 'Two-factor authentication'),
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
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: otpauthUri, size: 184),
              ),
            ),
            const SizedBox(height: 12),
            Text(ar ? 'أو أدخل المفتاح يدوياً:' : 'Or enter this key manually:',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            SelectableText(secret,
                style: const TextStyle(fontFamily: 'JetBrainsMono', letterSpacing: 1.5, fontSize: 13)),
            const SizedBox(height: 10),
            Text(
              ar
                  ? 'إذا كان الرمز السابق لا يعمل، احذف المدخل القديم من تطبيق المصادقة ثم امسح هذا الرمز من جديد.'
                  : 'If a previously scanned code no longer works, delete that old entry from your authenticator app and scan this QR again.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 10, fontFamily: 'JetBrainsMono'),
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
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(enroll ? (ar ? 'تأكيد وربط' : 'Confirm & bind') : (ar ? 'تحقق' : 'Verify')),
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
          Row(children: [
            Icon(Icons.lock_reset, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ar ? 'تغيير كلمة المرور' : 'Change your password',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            ar
                ? 'يجب تعيين كلمة مرور جديدة قبل المتابعة.'
                : 'You must set a new password before continuing.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: newPassCtrl,
            obscureText: true,
            decoration: InputDecoration(labelText: ar ? 'كلمة المرور الجديدة' : 'New password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirmPassCtrl,
            obscureText: true,
            decoration: InputDecoration(labelText: ar ? 'تأكيد كلمة المرور' : 'Confirm password'),
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
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(ar ? 'حفظ وتسجيل الدخول' : 'Save & sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return GestureDetector(
      onLongPress: () => context.go('/diagnostics'),
      behavior: HitTestBehavior.opaque,
      child: BrandBand(
        padding: const EdgeInsets.fromLTRB(56, 56, 56, 56),
        sparkleSize: 360,
        sparkleAlignment: const Alignment(1.3, 1.4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntesharStar(size: 72, color: IntesharColors.ink),
            const SizedBox(height: 28),
            // Scale the wordmark down on narrow split-screens so the 96px
            // display never overflows the half-width brand panel.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Inteshar',
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      color: IntesharColors.ink,
                      fontSize: 96,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -3.5,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'Platform.',
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      color: IntesharColors.ink,
                      fontSize: 96,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -3.5,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                l.loginBrandTagline,
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  color: IntesharColors.ink.withValues(alpha: 0.78),
                  fontSize: 17,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileBrandHeader extends StatelessWidget {
  const _MobileBrandHeader();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return BrandBand(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
      sparkleSize: 200,
      sparkleAlignment: const Alignment(1.4, 1.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          IntesharStar(size: 48, color: IntesharColors.ink),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: const Text(
              'Inteshar Platform.',
              style: TextStyle(
                fontFamily: 'CodecPro',
                color: IntesharColors.ink,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.4,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.loginBrandTaglineShort,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 14.5,
              color: IntesharColors.ink.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController phoneCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool loading;
  final String? error;
  final bool showMongoHint;
  final bool isAuthenticated;
  final AppLocalizations l;
  final VoidCallback onSignIn;
  final VoidCallback onShowUrlSheet;
  final VoidCallback onSeed;

  const _LoginForm({
    required this.formKey,
    required this.phoneCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.loading,
    required this.error,
    required this.showMongoHint,
    required this.isAuthenticated,
    required this.l,
    required this.onSignIn,
    required this.onShowUrlSheet,
    required this.onSeed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.loginWelcomeBack,
            style: IntesharType.display(34, color: cs.onSurface, w: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            l.loginSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: IntesharType.mono(14, color: cs.onSurface, letterSpacing: 0.6),
            decoration: InputDecoration(
              labelText: l.loginPhone,
              hintText: '07701234567',
              prefixIcon: const Icon(Icons.phone_outlined, size: 18),
            ),
            validator: (v) => v == null || v.isEmpty ? l.loginFieldRequired : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: passCtrl,
            obscureText: obscure,
            style: IntesharType.mono(14, color: cs.onSurface, letterSpacing: 1.2),
            decoration: InputDecoration(
              labelText: l.loginPassword,
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                onPressed: onToggleObscure,
              ),
            ),
            validator: (v) => v == null || v.isEmpty ? l.loginFieldRequired : null,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onShowUrlSheet,
              icon: const Icon(Icons.dns_outlined, size: 14),
              label: Text(l.loginServerUrl),
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
          if (showMongoHint) ...[
            const SizedBox(height: 10),
            _Banner(
              tone: IntesharColors.saffronDeep,
              icon: Icons.info_outline,
              title: l.loginNoUsersTitle,
              body: '${l.loginNoUsers}\n\n${l.loginNoUsersDefault}',
            ),
          ],
          const SizedBox(height: 24),
          BrandCTAButton(
            label: l.loginSignIn,
            trailing: Icons.arrow_forward,
            loading: loading,
            onPressed: loading ? null : onSignIn,
          ),
          if (isAuthenticated) ...[
            const SizedBox(height: 12),
            BrandCTAButton(
              label: l.loginSeedDemo,
              leading: Icons.play_arrow,
              variant: BrandCTAVariant.outline,
              onPressed: onSeed,
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color tone;
  final IconData icon;
  final String title;
  final String body;
  const _Banner({required this.tone, required this.icon, required this.title, required this.body});

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
