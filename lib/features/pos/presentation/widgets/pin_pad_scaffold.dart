import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// Dark, brand-aware PIN screen matching the POS app mockup (system Excel,
/// image6): a near-black backdrop with the star motif, the account's logo, a
/// prompt, a row of PIN dots, a numeric keypad, and a confirm button. Shared by
/// the POS PIN **setup** and **lock** pages so both look identical.
///
/// The caller owns the entered-digit state; this widget only renders and emits
/// keypad events. The gold accent tracks the agent's brand colour.
class PinPadScaffold extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final int entered;
  final int minLength;
  final int maxLength;
  final String? error;
  final bool loading;
  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onClear;
  final VoidCallback onConfirm;
  final String confirmLabel;

  /// Optional trailing controls under the confirm button (e.g. sign-out).
  final List<Widget> footer;

  const PinPadScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.entered,
    this.minLength = 4,
    this.maxLength = 6,
    this.error,
    this.loading = false,
    required this.onDigit,
    required this.onBackspace,
    this.onClear,
    required this.onConfirm,
    required this.confirmLabel,
    this.footer = const [],
  });

  static const _bg = Color(0xFF16181D);
  static const _panel = Color(0xFF23262E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final logoUrl = auth is AuthAuthenticated ? auth.brand.agentLogoUrl : '';
    final bgUrl = auth is AuthAuthenticated ? auth.brand.agentBackgroundUrl : '';
    // Brand accent (gold by default) drives the dots + confirm.
    final accent = Theme.of(context).colorScheme.primary;
    final canConfirm = entered >= minLength && !loading;
    final dots = entered > minLength ? entered.clamp(minLength, maxLength) : minLength;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Star motif — the brand texture behind the pad.
          Positioned(
            top: -60,
            right: -80,
            child: Opacity(
              opacity: 0.06,
              child: IntesharStar(size: 460, color: Colors.white, tilt: -0.3),
            ),
          ),
          if (bgUrl.trim().isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.08,
                child: Image.network(bgUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _logo(logoUrl),
                      const SizedBox(height: 28),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'CodecPro',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'CodecPro',
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      _dotsRow(dots, accent),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'CodecPro',
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 26),
                      _keypad(accent),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: canConfirm ? onConfirm : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: _onAccent(accent),
                            disabledBackgroundColor: accent.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                          ),
                          child: loading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(confirmLabel, style: const TextStyle(fontFamily: 'CodecPro', fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      ...footer,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logo(String logoUrl) {
    if (logoUrl.trim().isNotEmpty) {
      return Image.network(
        logoUrl,
        height: 92,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => IntesharStar(size: 72, color: Colors.white),
      );
    }
    return IntesharStar(size: 84, color: Colors.white);
  }

  Widget _dotsRow(int count, Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final filled = i < entered;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 9),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? accent : Colors.transparent,
            border: Border.all(color: filled ? accent : Colors.white.withValues(alpha: 0.35), width: 1.6),
          ),
        );
      }),
    );
  }

  Widget _keypad(Color accent) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) _key(child: Text(d, style: _keyTextStyle), onTap: () => onDigit(d))],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _key(child: const Icon(Icons.close, color: Colors.white70, size: 24), onTap: onClear ?? () {}, disabled: onClear == null),
            _key(child: const Text('0', style: _keyTextStyle), onTap: () => onDigit('0')),
            _key(child: const Icon(Icons.backspace_outlined, color: Colors.white70, size: 22), onTap: onBackspace),
          ],
        ),
      ],
    );
  }

  static const _keyTextStyle = TextStyle(fontFamily: 'CodecPro', fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white);

  Widget _key({required Widget child, required VoidCallback onTap, bool disabled = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: disabled ? Colors.transparent : _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: disabled ? null : onTap,
          child: SizedBox(width: 74, height: 60, child: Center(child: child)),
        ),
      ),
    );
  }

  Color _onAccent(Color accent) =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : IntesharColors.ink;
}
