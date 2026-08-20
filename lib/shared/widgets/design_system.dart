import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// "Inteshar Sunburst" — retail-brand primitives. Cards float on soft drop
/// shadows, status reads as friendly chips (not rubber stamps), titles are
/// chunky sans (not editorial italic serif), brand identity is the angular
/// flying-star mark (not a publisher monogram).

// ─── Hairline ───────────────────────────────────────────────────────────────

class Hairline extends StatelessWidget {
  final Axis axis;
  final double indent;
  final double endIndent;
  final Color? color;
  const Hairline({
    super.key,
    this.axis = Axis.horizontal,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    if (axis == Axis.horizontal) {
      return Padding(
        padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
        child: Container(height: 1, color: c),
      );
    }
    return Padding(
      padding: EdgeInsetsDirectional.only(top: indent, bottom: endIndent),
      child: Container(width: 1, color: c),
    );
  }
}

// ─── Section label ─────────────────────────────────────────────────────────

/// Bold title-case label with an optional yellow dot marker. Replaces the
/// editorial overline+rule pattern.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// When true (default), paint a 6px yellow dot before the label.
  final bool dot;
  const SectionLabel(
    this.text, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(0, 0, 0, 12),
    this.dot = true,
    @Deprecated('Editorial rule is removed; parameter ignored.')
    bool withRule = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (dot)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: context.tones.brand,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'CodecPro',
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
                height: 1.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ─── InkCard (now a soft shadow tile) ──────────────────────────────────────

/// White surface tile with a soft drop shadow. Optionally paints a yellow
/// accent ridge along the start edge (`ruleColor`) — this preserves the
/// existing API but reads as a brand mark, not an editorial print rule.
class InkCard extends StatelessWidget {
  final Widget child;
  final Color? ruleColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? background;
  final bool dense;
  final bool elevated;

  const InkCard({
    super.key,
    required this.child,
    this.ruleColor,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.background,
    this.dense = false,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.circular(IntesharRadii.lg);
    final bg = background ?? cs.surfaceContainer;

    final content = ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          if (ruleColor != null)
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: ruleColor),
            ),
          Padding(
            padding: ruleColor != null
                ? padding.add(const EdgeInsetsDirectional.only(start: 4))
                : padding,
            child: child,
          ),
        ],
      ),
    );

    final tile = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        boxShadow: elevated ? IntesharShadows.elev1 : const [],
      ),
      child: content,
    );

    if (onTap == null && onLongPress == null) return tile;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: radius,
        splashColor: context.tones.brand.withValues(alpha: 0.10),
        highlightColor: context.tones.brand.withValues(alpha: 0.05),
        child: tile,
      ),
    );
  }
}

// ─── Status chip (was StampPill) ───────────────────────────────────────────

/// Friendly rounded status chip. Filled with the color at low alpha, label
/// at full alpha. Replaces the rubber-stamp uppercase pattern.
class StampPill extends StatelessWidget {
  /// Smallest legible size for bold Arabic on a tinted pill — a status read at
  /// arm's length on a POS handheld in daylight. Callers asking for less get
  /// this (UX-142).
  static const double minFontSize = 12;

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;
  final double fontSize;
  const StampPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = true,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = fontSize < minFontSize ? minFontSize : fontSize;
    // UX-142: the label used to BE the tint colour on that same colour at 14%,
    // i.e. ~2–3:1 — the most repeated status signal in the product, and the
    // first thing to vanish in daylight. Darken the tone against the tint the
    // pill actually paints; blending toward black keeps the semantic hue, so
    // "available" is still green, just readable.
    final background = filled
        ? Color.alphaBlend(color.withValues(alpha: 0.14), cs.surface)
        : cs.surface;
    final foreground = contrastAdjusted(color, background);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 8 : 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: filled
            ? null
            : Border.all(color: foreground.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size + 2, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'CodecPro',
              color: foreground,
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FigureBlock (now a stat tile) ─────────────────────────────────────────

/// Stacked label / big numeral / caption stat tile. Replaces the editorial
/// horizontal-rule + Fraunces-numeral pattern.
class FigureBlock extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final Color? accent;
  final bool monoValue;
  const FigureBlock({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.accent,
    this.monoValue = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accentColor = accent ?? context.tones.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'CodecPro',
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: monoValue
              ? IntesharType.mono(28, color: cs.onSurface, w: FontWeight.w700)
              : IntesharType.display(
                  34,
                  color: cs.onSurface,
                  w: FontWeight.w900,
                ),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

// ─── Brand rule ────────────────────────────────────────────────────────────

/// The 38×3 brand underline that marks a page/section title (UX-131).
///
/// It lives in [PageHeader], but had been re-typed by hand at two more sites
/// (`system_activity_page`, `notifications_inbox_page`) — the kind of duplicate
/// that quietly stops tracking a white-label brand the day someone edits one
/// copy. Use this anywhere the mark is needed outside a [PageHeader].
class BrandRule extends StatelessWidget {
  final double width;
  final double height;
  final Color? color;

  const BrandRule({super.key, this.width = 38, this.height = 3, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? context.tones.brand,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ─── Page header ───────────────────────────────────────────────────────────

/// Friendly page header: bold sans title + muted subtitle + optional yellow
/// underline accent. Replaces the editorial eyebrow+rule+italic-subtitle pattern.
class PageHeader extends StatelessWidget {
  /// Kept for API compatibility — repurposed as the muted overline label
  /// shown above the title.
  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool showEyebrow;
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 12),
    this.showEyebrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showEyebrow) ...[
            Text(
              eyebrow,
              style: TextStyle(
                fontFamily: 'CodecPro',
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 6),
          ],
          // UX-115: `trailing` is a non-flex Row child, so it was handed
          // UNBOUNDED width — a Wrap never wrapped, a button pair claimed its
          // full ~260dp, and the 32px title was left wrapping inside ~88dp.
          // Cap the trailing so it folds, and let the title scale down instead
          // of stacking (same idiom as the POS masthead).
          LayoutBuilder(
            builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: IntesharType.display(
                        32,
                        color: cs.onSurface,
                        w: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.55,
                    ),
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          const BrandRule(),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Brand lockup ──────────────────────────────────────────────────────────

/// IntesharStar + "Inteshar" wordmark stacked or inline.
class IntesharLockup extends StatelessWidget {
  final String title;
  final String tagline;
  final bool compact;

  /// When `true`, render the lockup on a yellow surface (ink-on-yellow).
  /// When `false`, render on a paper surface (ink-on-paper).
  final bool onBrandSurface;

  /// Hide the tagline line — useful in tight slots like a phone app bar.
  final bool showTagline;
  const IntesharLockup({
    super.key,
    required this.title,
    required this.tagline,
    this.compact = false,
    this.onBrandSurface = false,
    this.showTagline = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = onBrandSurface ? IntesharColors.ink : cs.onSurface;
    final fgSoft = onBrandSurface
        ? IntesharColors.ink.withValues(alpha: 0.65)
        : cs.onSurfaceVariant;
    // FittedBox(scaleDown) shrinks the whole lockup — including the fixed-size
    // star — to fit tight slots (e.g. a phone app-bar title) instead of
    // overflowing. A Flexible can't help here because the star is a fixed size,
    // and a flex child under FittedBox's unbounded width would throw.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntesharStar(size: compact ? 28 : 36, color: fg),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'CodecPro',
                  fontSize: compact ? 18 : 22,
                  fontWeight: FontWeight.w900,
                  color: fg,
                  letterSpacing: -0.4,
                  height: 1.0,
                ),
              ),
              if (showTagline) ...[
                const SizedBox(height: 4),
                Text(
                  tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'CodecPro',
                    fontSize: compact ? 10.5 : 11.5,
                    color: fgSoft,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Selectable mono text helper ───────────────────────────────────────────

/// SelectableText preconfigured with JetBrainsMono — used for ids, serials,
/// pins, MACs, JWTs.
SelectableText monoText(
  String value, {
  double size = 13,
  Color? color,
  FontWeight w = FontWeight.w500,
  double letterSpacing = 0.4,
}) {
  return SelectableText(
    value,
    style: IntesharType.mono(
      size,
      color: color,
      w: w,
      letterSpacing: letterSpacing,
    ),
  );
}

// ─── Soft tap helpers ──────────────────────────────────────────────────────

/// Provides a haptic + scale press feedback on tiles used as primary action
/// buttons (POS tiles, quick actions, etc.).
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
