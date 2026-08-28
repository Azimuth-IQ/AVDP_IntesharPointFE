import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
import 'package:inteshar/features/pos/presentation/pos_brand.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';

/// Full-screen POS PIN setup page. Used for:
/// - First-time setup (no existing PIN): [requireCurrent] = false (default).
/// - Change-PIN flow: [requireCurrent] = true shows a "current PIN" field.
///
/// On success the session is unlocked ([posUnlockedProvider] = true) and the
/// router navigates to `/pos/home`.
class PosPinSetupPage extends ConsumerStatefulWidget {
  /// When true an extra "current PIN" field is shown at the top. Pass this
  /// flag when the operator deliberately navigates to change their PIN.
  final bool requireCurrent;

  const PosPinSetupPage({super.key, this.requireCurrent = false});

  @override
  ConsumerState<PosPinSetupPage> createState() => _PosPinSetupPageState();
}

class _PosPinSetupPageState extends ConsumerState<PosPinSetupPage> {
  final _currentCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscurePin = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (pin.length < 4) {
      setState(() => _error = _ar ? 'يجب أن يكون الرمز 4 أرقام على الأقل' : 'PIN must be at least 4 digits');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = _ar ? 'الرمزان غير متطابقان' : 'PINs do not match');
      return;
    }
    if (widget.requireCurrent && _currentCtrl.text.trim().isEmpty) {
      setState(() => _error = _ar ? 'أدخل الرمز الحالي' : 'Enter your current PIN');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(posPinRepositoryProvider);
      await repo.setPin(
        pin,
        currentPin: widget.requireCurrent ? _currentCtrl.text.trim() : null,
      );
      if (!mounted) return;
      // UX-54: the lock screen's keypad auto-submits on the last digit, and the
      // server never tells it how many digits that is. Record the LENGTH (never
      // the PIN) here so a PIN changed in-app doesn't leave the pad firing at
      // the old length.
      rememberPinLength(pin.length);
      // Unlock the session and go to POS home
      ref.read(posUnlockedProvider.notifier).state = true;
      context.go('/pos/home');
    } catch (e) {
      if (!mounted) return;
      final apiErr = ApiException.from(e);
      setState(() {
        _error = apiErr?.message ?? (_ar ? 'حدث خطأ' : 'An error occurred');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width > 700;

    final form = _PinSetupForm(
      requireCurrent: widget.requireCurrent,
      currentCtrl: _currentCtrl,
      pinCtrl: _pinCtrl,
      confirmCtrl: _confirmCtrl,
      obscureCurrent: _obscureCurrent,
      obscurePin: _obscurePin,
      obscureConfirm: _obscureConfirm,
      onToggleCurrent: () => setState(() => _obscureCurrent = !_obscureCurrent),
      onTogglePin: () => setState(() => _obscurePin = !_obscurePin),
      onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
      loading: _loading,
      error: _error,
      cs: cs,
      onSubmit: _submit,
    );

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: isWide
            ? Row(
                children: [
                  const Expanded(child: PosBrandHero(wide: true)),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: form,
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
                        child: Center(child: form),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}


// ── Setup form ───────────────────────────────────────────────────────────────

class _PinSetupForm extends StatelessWidget {
  final bool requireCurrent;
  final TextEditingController currentCtrl;
  final TextEditingController pinCtrl;
  final TextEditingController confirmCtrl;
  final bool obscureCurrent;
  final bool obscurePin;
  final bool obscureConfirm;
  final VoidCallback onToggleCurrent;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleConfirm;
  final bool loading;
  final String? error;
  final ColorScheme cs;
  final VoidCallback onSubmit;

  const _PinSetupForm({
    required this.requireCurrent,
    required this.currentCtrl,
    required this.pinCtrl,
    required this.confirmCtrl,
    required this.obscureCurrent,
    required this.obscurePin,
    required this.obscureConfirm,
    required this.onToggleCurrent,
    required this.onTogglePin,
    required this.onToggleConfirm,
    required this.loading,
    required this.error,
    required this.cs,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              // UX-135: `circular(22)` was only ever "half of 44".
              decoration: BoxDecoration(
                color: context.tones.brand,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline, color: context.tones.onBrand, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ar
                        ? (requireCurrent ? 'تغيير رمز نقطة البيع' : 'إعداد رمز نقطة البيع')
                        : (requireCurrent ? 'Change POS PIN' : 'Set POS PIN'),
                    // UX-127: was an off-scale 22; wraps rather than clipping in
                    // a 460dp-capped column, so `display` (24) is safe.
                    style: IntesharType.display(IntesharScale.display,
                        color: cs.onSurface, w: IntesharWeight.black),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ar
                        ? 'رمز مكوّن من 4–6 أرقام يحمي جلسة البيع'
                        : '4–6 digit code that protects your POS session',
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

        if (requireCurrent) ...[
          TextField(
            controller: currentCtrl,
            obscureText: obscureCurrent,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            style: IntesharType.mono(18, color: cs.onSurface, letterSpacing: 8),
            decoration: InputDecoration(
              labelText: ar ? 'الرمز الحالي' : 'Current PIN',
              counterText: '',
              prefixIcon: const Icon(Icons.lock_clock_outlined, size: 18),
              suffixIcon: IconButton(
                // UX-150: an icon-only control that toggles whether a secret is
                // on screen has to say which way it will go.
                tooltip: obscureCurrent
                    ? (ar ? 'إظهار الرمز' : 'Show PIN')
                    : (ar ? 'إخفاء الرمز' : 'Hide PIN'),
                icon: Icon(
                  obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 18,
                ),
                onPressed: onToggleCurrent,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],

        TextField(
          controller: pinCtrl,
          obscureText: obscurePin,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          style: IntesharType.mono(18, color: cs.onSurface, letterSpacing: 8),
          decoration: InputDecoration(
            labelText: ar ? 'الرمز الجديد' : 'New PIN',
            counterText: '',
            prefixIcon: const Icon(Icons.pin_outlined, size: 18),
            suffixIcon: IconButton(
              tooltip: obscurePin
                  ? (ar ? 'إظهار الرمز' : 'Show PIN')
                  : (ar ? 'إخفاء الرمز' : 'Hide PIN'),
              icon: Icon(
                obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18,
              ),
              onPressed: onTogglePin,
            ),
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: confirmCtrl,
          obscureText: obscureConfirm,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          style: IntesharType.mono(18, color: cs.onSurface, letterSpacing: 8),
          decoration: InputDecoration(
            labelText: ar ? 'تأكيد الرمز' : 'Confirm PIN',
            counterText: '',
            prefixIcon: const Icon(Icons.pin_outlined, size: 18),
            suffixIcon: IconButton(
              tooltip: obscureConfirm
                  ? (ar ? 'إظهار الرمز' : 'Show PIN')
                  : (ar ? 'إخفاء الرمز' : 'Hide PIN'),
              icon: Icon(
                obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18,
              ),
              onPressed: onToggleConfirm,
            ),
          ),
          onSubmitted: (_) => onSubmit(),
        ),

        if (error != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(message: error!, cs: cs),
        ],

        const SizedBox(height: 24),
        BrandCTAButton(
          label: loading
              ? (ar ? 'جارٍ الحفظ...' : 'Saving…')
              : (ar
                  ? (requireCurrent ? 'تغيير الرمز' : 'تعيين الرمز')
                  : (requireCurrent ? 'Change PIN' : 'Set PIN')),
          trailing: loading ? null : Icons.arrow_forward,
          loading: loading,
          onPressed: loading ? null : onSubmit,
        ),

        const SizedBox(height: 16),
        Center(
          child: Text(
            ar
                ? 'يُستخدم هذا الرمز لقفل جلسة نقطة البيع'
                : 'This PIN gates entry to each POS session',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'CodecPro',
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final ColorScheme cs;
  const _ErrorBanner({required this.message, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      // UX-135: `all(14)` is on no scale — the token doc names it as the app's
      // single most common off-scale padding.
      padding: const EdgeInsets.all(IntesharSpacing.lg),
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
              message,
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
    );
  }
}
