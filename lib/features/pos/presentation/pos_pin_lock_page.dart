import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/pos/domain/pin_verify_result.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
import 'package:inteshar/features/pos/presentation/pos_brand.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';

/// Full-screen POS PIN lock page — shown whenever a POS session needs to be
/// (re-)authenticated with a PIN.
///
/// **The PIN entry is on screen from the first frame (UX-54).** A cold start
/// used to cost the operator three sequential round trips before the first sale
/// — a spinner, a "does a PIN exist" probe, then the verify — and the 90-second
/// relock re-runs all of it after any phone call. The probe still runs, but in
/// the background: it can only *redirect* to setup, never gate the keypad.
///
/// **Startup probe**: `verifyPin('')` distinguishes the states:
/// - Backend returns 409 (no PIN) → navigate to `/pos/pin-setup`.
/// - Backend returns 403 (wrong PIN, but PIN exists) → nothing to do, the input
///   is already up; a "shop is shut"/"locked out" reason is shown if it came back.
/// - Network error → ignored. The operator types anyway; [_submit] handles both
///   the offline case and the 409 defensively.
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
  String? _error;

  /// Set the moment the operator engages with the pad. Once true, a late probe
  /// result must not steer the screen — the operator's own verify is the
  /// authority, and a stray `context.go` mid-submit is a lost unlock.
  bool _touched = false;

  /// The length that auto-submitted last time this device unlocked. Null until
  /// it is known, in which case only a full 6 digits auto-submits.
  int? _knownPinLength;

  @override
  void initState() {
    super.initState();
    // Both of these run WITHOUT holding up the first frame: the keypad is on
    // screen immediately and the operator can start typing into it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
    readRememberedPinLength().then((v) {
      if (mounted && v != null) setState(() => _knownPinLength = v);
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  /// The digit count that ends entry: the remembered length, else the 6-digit
  /// maximum (which cannot be a partial PIN, so it is always safe to submit).
  int get _autoSubmitAt => _knownPinLength ?? 6;

  /// Background probe with an empty PIN. It may redirect to setup, or surface a
  /// "shop is shut" reason — it may NOT show a spinner, block the pad, or turn a
  /// network blip into a full-screen error: the operator can simply type.
  Future<void> _probe() async {
    if (!mounted) return;
    try {
      final repo = ref.read(posPinRepositoryProvider);
      // Empty string: server returns 403 (pin set, wrong value) or 409 (no pin).
      final result = await repo.verifyPin('');
      // `_pinCtrl.text` covers the wide/TextField layout, where typing doesn't
      // pass through `_onDigit` and so never sets `_touched`.
      if (!mounted || _touched || _loading || _pinCtrl.text.isNotEmpty) return;
      if (result.reason == PinVerifyReason.noPin) {
        context.go('/pos/pin-setup');
        return;
      }
      if (result.isOk) {
        // An empty string was accepted — treat as unlocked (edge case).
        ref.read(posUnlockedProvider.notifier).state = true;
        context.go('/pos/home');
      } else if (result.reason == PinVerifyReason.outsideHours ||
          result.reason == PinVerifyReason.lockedOut) {
        // A closed shop or a lockout is worth saying up front rather than after
        // the operator has typed a PIN that was never the problem.
        setState(() => _error = posPinReasonText(result, _ar));
      }
    } catch (e) {
      // `_pinCtrl.text` covers the wide/TextField layout, where typing doesn't
      // pass through `_onDigit` and so never sets `_touched`.
      if (!mounted || _touched || _loading || _pinCtrl.text.isNotEmpty) return;
      if (ApiException.from(e)?.statusCode == 409) {
        context.go('/pos/pin-setup'); // no PIN set yet
      }
      // Anything else (network / 5xx) is deliberately swallowed: the entry is
      // already up, and `_submit` reports a real failure with the real reason.
    }
  }

  Future<void> _submit() async {
    if (_loading) return;
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = _ar ? 'أدخل الرمز' : 'Enter your PIN');
      return;
    }

    setState(() {
      _loading = true;
      _touched = true;
      _error = null;
    });

    try {
      final repo = ref.read(posPinRepositoryProvider);
      final result = await repo.verifyPin(pin);
      if (!mounted) return;
      if (result.isOk) {
        // Length only, never the PIN — so the next relock ends on the last digit
        // instead of an extra tap.
        rememberPinLength(pin.length);
        ref.read(posUnlockedProvider.notifier).state = true;
        context.go('/pos/home');
      } else if (result.reason == PinVerifyReason.noPin) {
        context.go('/pos/pin-setup');
        return;
      } else {
        // A rejected PIN invalidates the remembered length — if the PIN was
        // changed elsewhere, the pad must stop firing at the old length.
        if (result.reason == PinVerifyReason.wrongPin) {
          forgetRememberedPinLength();
          if (mounted) setState(() => _knownPinLength = null);
        }
        setState(() {
          _error = posPinReasonText(result, _ar);
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

  /// Pad key press. Auto-submits on the last digit so the ordinary unlock is
  /// "type four digits" and nothing else.
  void _onDigit(String d) {
    if (_loading) return;
    if (_pinCtrl.text.length >= 6) return;
    setState(() {
      _touched = true;
      _error = null;
      _pinCtrl.text = _pinCtrl.text + d;
    });
    if (_pinCtrl.text.length >= _autoSubmitAt) _submit();
  }

  void _onBackspace() {
    if (_loading || _pinCtrl.text.isEmpty) return;
    setState(() {
      _touched = true;
      _pinCtrl.text = _pinCtrl.text.substring(0, _pinCtrl.text.length - 1);
    });
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
    // The handheld gets the pad (no OS keyboard covering half a 5" screen, and
    // digits big enough for a thumb); a desktop/web session keeps the field,
    // where a hardware keyboard is the natural input.
    final usePad = !isWide;

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
                      child: _buildContent(cs, usePad),
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
                    child: Center(child: _buildContent(cs, usePad)),
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

  Widget _buildContent(ColorScheme cs, bool usePad) {
    return _LockForm(
      pinCtrl: _pinCtrl,
      obscure: _obscure,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      loading: _loading,
      error: _error,
      cs: cs,
      usePad: usePad,
      onDigit: _onDigit,
      onBackspace: _onBackspace,
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

  /// True on a handheld: show the on-screen numeric pad instead of the field
  /// backed by the OS keyboard (UX-54).
  final bool usePad;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final VoidCallback onSignOut;

  const _LockForm({
    required this.pinCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.loading,
    required this.error,
    required this.cs,
    required this.usePad,
    required this.onDigit,
    required this.onBackspace,
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
              child: Icon(Icons.lock_outline, color: context.tones.onBrand, size: 22),
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

        if (usePad)
          _PinDots(entered: pinCtrl.text.length, obscure: obscure, cs: cs, text: pinCtrl.text)
        else
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

        if (usePad) ...[
          const SizedBox(height: 18),
          _NumericPad(
            enabled: !loading,
            onDigit: onDigit,
            onBackspace: onBackspace,
            onToggleObscure: onToggleObscure,
            obscure: obscure,
            cs: cs,
          ),
        ],

        const SizedBox(height: 24),
        // Still here even with the pad: the PIN length is not known on the first
        // unlock of a device, and a 4- or 5-digit PIN then needs one deliberate tap.
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

// ── PIN entry display + pad (UX-54) ──────────────────────────────────────────

/// The entered digits: dots by default, the actual digits when the operator
/// chooses to reveal them.
class _PinDots extends StatelessWidget {
  final int entered;
  final bool obscure;
  final String text;
  final ColorScheme cs;

  const _PinDots({
    required this.entered,
    required this.obscure,
    required this.text,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: obscure
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 6; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < entered ? context.tones.brandInk : Colors.transparent,
                        border: Border.all(
                            color: i < entered ? context.tones.brandInk : cs.outline,
                            width: 1.5),
                      ),
                    ),
                  ),
              ],
            )
          : Text(
              text,
              style: IntesharType.mono(24, color: cs.onSurface, letterSpacing: 8),
            ),
    );
  }
}

/// A 3×4 numeric pad sized for a thumb on a 5" handheld. No OS keyboard, so
/// nothing slides up over the screen and the digits stay where the operator's
/// muscle memory left them.
class _NumericPad extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onToggleObscure;
  final bool obscure;
  final ColorScheme cs;

  const _NumericPad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onToggleObscure,
    required this.obscure,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Material(
              color: icon == null ? cs.surfaceContainerHighest : Colors.transparent,
              borderRadius: BorderRadius.circular(IntesharRadii.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(IntesharRadii.md),
                onTap: enabled ? (onTap ?? () => onDigit(label)) : null,
                child: SizedBox(
                  height: 54,
                  child: Center(
                    child: icon != null
                        ? Icon(icon, size: 22, color: cs.onSurfaceVariant)
                        : Text(label,
                            style: IntesharType.mono(22,
                                color: cs.onSurface, w: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
        );

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) key(d)]),
        Row(children: [
          key('', onTap: onToggleObscure,
              icon: obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          key('0'),
          key('', onTap: onBackspace, icon: Icons.backspace_outlined),
        ]),
      ],
    );
  }
}
