import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
import 'package:inteshar/features/pos/presentation/widgets/pin_pad_scaffold.dart';

/// Full-screen POS PIN lock — a dark, brand-aware keypad (system Excel mockup,
/// image6) shown whenever a POS session needs (re-)authenticating with a PIN.
///
/// **Startup probe**: on init this page calls `verifyPin('')`:
/// - 409 (no PIN) → navigate to `/pos/pin-setup`.
/// - 403 (wrong PIN, but a PIN exists) → stay and show the keypad.
/// - Network error → surface a retry action.
class PosPinLockPage extends ConsumerStatefulWidget {
  const PosPinLockPage({super.key});

  @override
  ConsumerState<PosPinLockPage> createState() => _PosPinLockPageState();
}

class _PosPinLockPageState extends ConsumerState<PosPinLockPage> {
  String _pin = '';
  bool _loading = false;
  bool _probing = true;
  String? _error;
  String? _probeError;

  static const _maxLen = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  Future<void> _probe() async {
    if (!mounted) return;
    setState(() {
      _probing = true;
      _probeError = null;
    });
    try {
      final repo = ref.read(posPinRepositoryProvider);
      final result = await repo.verifyPin('');
      if (!mounted) return;
      if (result) {
        ref.read(posUnlockedProvider.notifier).state = true;
        context.go('/pos/home');
      } else {
        setState(() => _probing = false);
      }
    } catch (e) {
      if (!mounted) return;
      final apiErr = ApiException.from(e);
      if (apiErr?.statusCode == 409) {
        context.go('/pos/pin-setup');
        return;
      }
      setState(() {
        _probing = false;
        _probeError = apiErr?.message ?? (_ar ? 'تعذّر الاتصال بالخادم' : 'Could not reach server');
      });
    }
  }

  void _onDigit(String d) {
    if (_pin.length >= _maxLen) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final pin = _pin.trim();
    if (pin.length < 4) {
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
          _pin = '';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final apiErr = ApiException.from(e);
      if (apiErr?.statusCode == 409) {
        context.go('/pos/pin-setup');
        return;
      }
      setState(() {
        _error = apiErr?.message ?? (_ar ? 'حدث خطأ' : 'An error occurred');
        _loading = false;
        _pin = '';
      });
    }
  }

  Future<void> _signOut() async {
    ref.read(posUnlockedProvider.notifier).state = false;
    await ref.read(authStateProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_probing) {
      return const Scaffold(
        backgroundColor: Color(0xFF16181D),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_probeError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF16181D),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_outlined, size: 48, color: Colors.white54),
                  const SizedBox(height: 16),
                  Text(_probeError!, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'CodecPro', color: Colors.white70, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  FilledButton.icon(onPressed: _probe, icon: const Icon(Icons.refresh), label: Text(_ar ? 'إعادة المحاولة' : 'Retry')),
                  TextButton(onPressed: _signOut, child: Text(_ar ? 'تسجيل الخروج' : 'Sign out', style: const TextStyle(color: Colors.white70))),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PinPadScaffold(
      title: _ar ? 'أدخل رمز نقطة البيع' : 'Enter your POS PIN',
      subtitle: _ar ? 'أدخل رمزك لفتح الجلسة' : 'Enter your PIN to unlock the session',
      entered: _pin.length,
      error: _error,
      loading: _loading,
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      onClear: _pin.isEmpty ? null : () => setState(() => _pin = ''),
      onConfirm: _submit,
      confirmLabel: _ar ? 'فتح الجلسة' : 'Unlock',
      footer: [
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout_outlined, size: 18, color: Colors.white60),
          label: Text(_ar ? 'تسجيل الخروج' : 'Sign out', style: const TextStyle(fontFamily: 'CodecPro', color: Colors.white60, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
