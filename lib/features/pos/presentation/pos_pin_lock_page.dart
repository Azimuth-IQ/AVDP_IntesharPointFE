import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
import 'package:inteshar/features/pos/presentation/pos_brand.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';

/// Full-screen POS PIN lock page — shown whenever a POS session needs to be
/// (re-)authenticated with a PIN.
///
/// **Startup probe**: on init this page calls `verifyPin('')` to determine
/// whether a PIN has been set at all:
/// - Backend returns 409 (no PIN) → immediately navigate to `/pos/pin-setup`.
/// - Backend returns 403 (wrong PIN, but PIN exists) → stay and show the input.
/// - Network error → surface the error with a retry action.
///
/// **Sign-out**: the sign-out button calls `AuthController.logout()` and clears
/// the in-memory unlock flag before navigating to `/login`, ensuring re-entry
/// is always gated.
class PosPinLockPage extends ConsumerStatefulWidget {
  const PosPinLockPage({super.key});

  @override
  ConsumerState<PosPinLockPage> createState() => _PosPinLockPageState();
}

class _PosPinLockPageState extends ConsumerState<PosPinLockPage> {
  final _pinCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _probing = true; // true while running the startup pin-exists probe
  String? _error;
  String? _probeError; // non-null when the probe itself fails (network error)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  /// Probes the server with an empty PIN to determine whether a PIN is set.
  ///
  /// A 409 response means no PIN has been configured → navigate to setup.
  /// A 403 (or false return) means a PIN exists → show the entry UI.
  /// Any other exception is a real network/server error → show retry UI.
  Future<void> _probe() async {
    if (!mounted) return;
    setState(() {
      _probing = true;
      _probeError = null;
    });
    try {
      final repo = ref.read(posPinRepositoryProvider);
      // Empty string: server returns 403 (pin set, wrong value) or 409 (no pin).
      // verifyPin('') returns false for 403 and rethrows for 409.
      final result = await repo.verifyPin('');
      if (!mounted) return;
      if (result) {
        // An empty string was accepted — treat as unlocked (edge case).
        ref.read(posUnlockedProvider.notifier).state = true;
        context.go('/pos/home');
      } else {
        // 403: PIN exists, wrong probe value — show the lock screen.
        setState(() => _probing = false);
      }
    } catch (e) {
      if (!mounted) return;
      final apiErr = ApiException.from(e);
      if (apiErr?.statusCode == 409) {
        // No PIN set yet → go to setup.
        context.go('/pos/pin-setup');
        return;
      }
      // Real error (network/5xx): surface a retry prompt.
      setState(() {
        _probing = false;
        _probeError = apiErr?.message ?? (_ar ? 'تعذّر الاتصال بالخادم' : 'Could not reach server');
      });
    }
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = _ar ? 'أدخل الرمز' : 'Enter your PIN');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(posPinRepositoryProvider);
      final ok = await repo.verifyPin(pin);
      if (!mounted) return;
      if (ok) {
        ref.read(posUnlockedProvider.notifier).state = true;
        context.go('/pos/home');
      } else {
        setState(() {
          _error = _ar ? 'رمز غير صحيح' : 'Incorrect PIN';
          _loading = false;
          _pinCtrl.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      final apiErr = ApiException.from(e);
      if (apiErr?.statusCode == 409) {
        // No PIN set → redirect to setup (should have been caught by probe,
        // but handle defensively in case the backend state changed).
        context.go('/pos/pin-setup');
        return;
      }
      setState(() {
        _error = apiErr?.message ?? (_ar ? 'حدث خطأ' : 'An error occurred');
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    // Reset the unlock flag before logout so re-entry re-requires the PIN.
    ref.read(posUnlockedProvider.notifier).state = false;
    await ref.read(authStateProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width > 700;

    final body = isWide
        ? Row(
            children: [
              const Expanded(child: PosBrandHero(wide: true)),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: _buildContent(cs),
                    ),
                  ),
                ),
              ),
            ],
          )
        : Column(
            children: [
              const PosBrandHero(wide: false),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Center(child: _buildContent(cs)),
                  ),
                ),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(child: body),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    if (_probing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 40),
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            _ar ? 'جارٍ التحقق...' : 'Checking…',
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 14,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (_probeError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Icon(Icons.wifi_off_outlined, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            _probeError!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 14,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          BrandCTAButton(
            label: _ar ? 'إعادة المحاولة' : 'Retry',
            leading: Icons.refresh,
            onPressed: _probe,
          ),
          const SizedBox(height: 12),
          BrandCTAButton(
            label: _ar ? 'تسجيل الخروج' : 'Sign out',
            variant: BrandCTAVariant.outline,
            leading: Icons.logout_outlined,
            onPressed: _signOut,
          ),
        ],
      );
    }

    return _LockForm(
      pinCtrl: _pinCtrl,
      obscure: _obscure,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      loading: _loading,
      error: _error,
      cs: cs,
      onSubmit: _submit,
      onSignOut: _signOut,
    );
  }
}


// ── Lock form ────────────────────────────────────────────────────────────────

class _LockForm extends StatelessWidget {
  final TextEditingController pinCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool loading;
  final String? error;
  final ColorScheme cs;
  final VoidCallback onSubmit;
  final VoidCallback onSignOut;

  const _LockForm({
    required this.pinCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.loading,
    required this.error,
    required this.cs,
    required this.onSubmit,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lock icon header
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.tones.brand,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.lock_outline, color: IntesharColors.ink, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ar ? 'أدخل رمز نقطة البيع' : 'Enter POS PIN',
                    style: IntesharType.display(22, color: cs.onSurface, w: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ar ? 'أدخل رمزك للمتابعة' : 'Enter your PIN to continue',
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        TextField(
          controller: pinCtrl,
          obscureText: obscure,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          autofocus: true,
          style: IntesharType.mono(22, color: cs.onSurface, letterSpacing: 12),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: ar ? 'رمز نقطة البيع' : 'POS PIN',
            counterText: '',
            prefixIcon: const Icon(Icons.pin_outlined, size: 18),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18,
              ),
              onPressed: onToggleObscure,
            ),
          ),
          onSubmitted: (_) => onSubmit(),
        ),

        if (error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(IntesharRadii.md),
              border: Border.all(color: cs.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: cs.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(
                      fontFamily: 'CodecPro',
                      fontSize: 13,
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        BrandCTAButton(
          label: loading
              ? (ar ? 'جارٍ التحقق...' : 'Verifying…')
              : (ar ? 'فتح الجلسة' : 'Unlock Session'),
          trailing: loading ? null : Icons.arrow_forward,
          loading: loading,
          onPressed: loading ? null : onSubmit,
        ),

        const SizedBox(height: 16),
        BrandCTAButton(
          label: ar ? 'تسجيل الخروج' : 'Sign out',
          variant: BrandCTAVariant.outline,
          leading: Icons.logout_outlined,
          onPressed: onSignOut,
        ),
      ],
    );
  }
}
