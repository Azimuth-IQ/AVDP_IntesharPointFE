import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';

enum BrandCTAVariant { primary, inverse, outline }

/// The app's primary CTA (B-094: flat, not glossy).
///
/// - **primary**: flat brand fill + a soft brand-tinted shadow. The old vertical
///   gradient and inner "chrome" highlight are gone — that skeuomorphic pill was
///   the most dated element in the UI.
/// - **inverse**: ink-black fill with paper text — used for secondary actions
///   that need weight without competing with the primary.
/// - **outline**: 1.5px ink border on transparent — used for ghost buttons.
class BrandCTAButton extends StatelessWidget {
  final String label;
  final IconData? leading;
  final IconData? trailing;
  final VoidCallback? onPressed;

  /// Optional long-press action. Used to tuck a secondary/hidden affordance
  /// behind the button (e.g. the server-endpoint sheet on the login screen).
  final VoidCallback? onLongPress;
  final bool loading;
  final BrandCTAVariant variant;
  final bool expand;
  final double height;
  final double fontSize;

  const BrandCTAButton({
    super.key,
    required this.label,
    this.onPressed,
    this.onLongPress,
    this.leading,
    this.trailing,
    this.loading = false,
    this.variant = BrandCTAVariant.primary,
    this.expand = true,
    this.height = 56,
    this.fontSize = 15,
  });

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    // Must match _Inner's radius, or the shadow + ink ripple mismatch the fill.
    final radius = BorderRadius.circular(IntesharRadii.md);
    final child = _Inner(
      label: label,
      leading: leading,
      trailing: trailing,
      loading: loading,
      variant: variant,
      fontSize: fontSize,
      height: height,
      // A button with no handler must LOOK unavailable. `loading` keeps the
      // brand fill — the spinner already says "working", and a CTA that greys
      // out mid-submit reads as a failure.
      enabled: onPressed != null,
    );

    final button = Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: _enabled ? onPressed : null,
        onLongPress: (onLongPress != null && !loading) ? onLongPress : null,
        borderRadius: radius,
        splashColor: Colors.black.withValues(alpha: 0.08),
        highlightColor: Colors.black.withValues(alpha: 0.04),
        child: child,
      ),
    );

    final wrapped = variant == BrandCTAVariant.primary
        ? DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              // Brand-tinted glow so a white-label CTA doesn't cast a gold shadow.
              boxShadow: _enabled ? context.tones.ctaShadow : const [],
            ),
            child: button,
          )
        : button;

    if (!expand) return wrapped;
    return SizedBox(width: double.infinity, child: wrapped);
  }
}

class _Inner extends StatelessWidget {
  final String label;
  final IconData? leading;
  final IconData? trailing;
  final bool loading;
  final BrandCTAVariant variant;
  final double fontSize;
  final double height;
  final bool enabled;

  const _Inner({
    required this.label,
    required this.loading,
    required this.variant,
    required this.fontSize,
    required this.height,
    required this.enabled,
    this.leading,
    this.trailing,
  });

  /// Icon/spinner + label, painted in [fg].
  ///
  /// UX-109: the label is `Flexible` + ellipsis because the whole pill is
  /// clipped by a `ClipRRect` — an over-long label (the bulk-sale button reads
  /// "بيع N بطاقة · amount") was silently truncated in release with no debug
  /// stripes to catch it, on the one control that draws and debits for real.
  Widget _row(Color fg) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            SizedBox(
              width: fontSize + 2,
              height: fontSize + 2,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
            const SizedBox(width: 10),
          ] else if (leading != null) ...[
            Icon(leading, size: fontSize + 4, color: fg),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'CodecPro',
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: fg,
                height: 1,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Icon(trailing, size: fontSize + 4, color: fg),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(IntesharRadii.md);
    // B-085: the pill is painted from the session's brand tones, so a white-label
    // agent's CTA (Sell, Sell & reveal, Unlock…) carries THEIR colour, not gold.
    final tones = context.tones;
    final cs = Theme.of(context).colorScheme;

    // UX-146: a disabled CTA used to lose only its shadow — full brand fill,
    // full-contrast label, so the operator kept tapping a dead Sell button and
    // read it as "the app is broken". Dim the fill AND the label.
    if (!enabled) {
      final fg = cs.onSurface.withValues(alpha: 0.38);
      return ClipRRect(
        borderRadius: radius,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.10),
            borderRadius: radius,
            border: Border.all(
              color: cs.onSurface.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: _row(fg),
        ),
      );
    }

    BoxDecoration deco;
    Color fg;
    switch (variant) {
      case BrandCTAVariant.primary:
        deco = BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: tones.ctaGradient,
            stops: const [0.0, 0.55, 1.0],
          ),
          borderRadius: radius,
          border: Border.all(color: tones.brandInk.withValues(alpha: 0.35), width: 1),
        );
        // Label tracks the brand's luminance — white on a dark brand, ink on a light one.
        fg = tones.onBrand;
        break;
      case BrandCTAVariant.inverse:
        deco = BoxDecoration(color: cs.onSurface, borderRadius: radius);
        fg = cs.surface;
        break;
      case BrandCTAVariant.outline:
        deco = BoxDecoration(
          color: Colors.transparent,
          borderRadius: radius,
          border: Border.all(color: cs.onSurface, width: 1.5),
        );
        fg = cs.onSurface;
        break;
    }

    Widget body = Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: deco,
      child: _row(fg),
    );

    // B-094: the inner "chrome" highlight is gone — a flat brand fill reads
    // current; the faux-gloss hairline was the tell that dated the whole app.
    return ClipRRect(borderRadius: radius, child: body);
  }
}
