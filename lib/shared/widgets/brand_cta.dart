import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';

enum BrandCTAVariant { primary, inverse, outline }

/// Glossy pill CTA matching the brand image's primary button.
///
/// - **primary**: vertical yellow gradient with inner top highlight + warm
///   yellow drop shadow + ink-black ExtraBold label.
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
    final radius = BorderRadius.circular(height / 2);
    final child = _Inner(
      label: label,
      leading: leading,
      trailing: trailing,
      loading: loading,
      variant: variant,
      fontSize: fontSize,
      height: height,
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

  const _Inner({
    required this.label,
    required this.loading,
    required this.variant,
    required this.fontSize,
    required this.height,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    // B-085: the pill is painted from the session's brand tones, so a white-label
    // agent's CTA (Sell, Sell & reveal, Unlock…) carries THEIR colour, not gold.
    final tones = context.tones;
    final cs = Theme.of(context).colorScheme;

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

    final row = Row(
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
        Text(
          label,
          style: TextStyle(
            fontFamily: 'CodecPro',
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: fg,
            height: 1,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          Icon(trailing, size: fontSize + 4, color: fg),
        ],
      ],
    );

    Widget body = Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: deco,
      child: row,
    );

    // Primary variant: paint a 1px top inner highlight inside the pill so it
    // catches light like a chromed candy button.
    if (variant == BrandCTAVariant.primary) {
      body = Stack(
        children: [
          body,
          Positioned(
            left: 14,
            right: 14,
            top: 1,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                color: tones.ctaHighlight.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      );
    }
    return ClipRRect(borderRadius: radius, child: body);
  }
}
