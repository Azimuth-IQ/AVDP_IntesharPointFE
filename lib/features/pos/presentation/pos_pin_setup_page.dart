import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/features/pos/application/pos_pin_controller.dart';
import 'package:inteshar/features/pos/presentation/widgets/pin_pad_scaffold.dart';

/// Full-screen POS PIN setup — a dark, brand-aware keypad (system Excel mockup,
/// image6). Used for first-time setup (enter → confirm) and, when
/// [requireCurrent] is true, the change-PIN flow (current → new → confirm).
///
/// On success the session is unlocked ([posUnlockedProvider] = true) and the
/// router navigates to `/pos/home`.
class PosPinSetupPage extends ConsumerStatefulWidget {
  final bool requireCurrent;

  const PosPinSetupPage({super.key, this.requireCurrent = false});

  @override
  ConsumerState<PosPinSetupPage> createState() => _PosPinSetupPageState();
}

enum _Step { current, newPin, confirmPin }

class _PosPinSetupPageState extends ConsumerState<PosPinSetupPage> {
  late _Step _step = widget.requireCurrent ? _Step.current : _Step.newPin;
  String _current = '';
  String _new = '';
  String _confirm = '';
  bool _loading = false;
  String? _error;

  static const _maxLen = 6;

  bool get _ar => Localizations.localeOf(context).languageCode == 'ar';

  String get _buffer => switch (_step) {
        _Step.current => _current,
        _Step.newPin => _new,
        _Step.confirmPin => _confirm,
      };

  set _buffer(String v) => setState(() {
        switch (_step) {
          case _Step.current:
            _current = v;
          case _Step.newPin:
            _new = v;
          case _Step.confirmPin:
            _confirm = v;
        }
      });

  void _onDigit(String d) {
    if (_buffer.length >= _maxLen) return;
    _error = null;
    _buffer = _buffer + d;
  }

  void _onBackspace() {
    if (_buffer.isEmpty) return;
    _buffer = _buffer.substring(0, _buffer.length - 1);
  }

  Future<void> _onConfirm() async {
    if (_buffer.length < 4) {
      setState(() => _error = _ar ? 'الرمز 4 أرقام على الأقل' : 'PIN must be at least 4 digits');
      return;
    }
    switch (_step) {
      case _Step.current:
        setState(() => _step = _Step.newPin);
      case _Step.newPin:
        setState(() => _step = _Step.confirmPin);
      case _Step.confirmPin:
        if (_confirm != _new) {
          setState(() {
            _error = _ar ? 'الرمزان غير متطابقان' : 'PINs do not match';
            _confirm = '';
            _step = _Step.newPin;
            _new = '';
          });
          return;
        }
        await _save();
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(posPinRepositoryProvider);
      await repo.setPin(_new, currentPin: widget.requireCurrent ? _current : null);
      if (!mounted) return;
      ref.read(posUnlockedProvider.notifier).state = true;
      context.go('/pos/home');
    } catch (e) {
      if (!mounted) return;
      final apiErr = ApiException.from(e);
      setState(() {
        _error = apiErr?.message ?? (_ar ? 'حدث خطأ' : 'An error occurred');
        _loading = false;
        // On a rejected current-PIN, restart at the current step.
        if (widget.requireCurrent) {
          _step = _Step.current;
          _current = '';
          _new = '';
          _confirm = '';
        }
      });
    }
  }

  String get _title => switch (_step) {
        _Step.current => _ar ? 'أدخل رمزك الحالي' : 'Enter your current PIN',
        _Step.newPin => _ar ? 'قم بتعيين رمز نقطة البيع' : 'Set your POS PIN',
        _Step.confirmPin => _ar ? 'أعد إدخال الرمز للتأكيد' : 'Re-enter the PIN to confirm',
      };

  @override
  Widget build(BuildContext context) {
    return PinPadScaffold(
      title: _title,
      subtitle: _ar ? 'رمز مكوّن من 4 إلى 6 أرقام' : 'A 4–6 digit code',
      entered: _buffer.length,
      error: _error,
      loading: _loading,
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      onClear: _buffer.isEmpty ? null : () => _buffer = '',
      onConfirm: _onConfirm,
      confirmLabel: _step == _Step.confirmPin
          ? (_ar ? 'تأكيد' : 'Confirm')
          : (_ar ? 'التالي' : 'Next'),
    );
  }
}
