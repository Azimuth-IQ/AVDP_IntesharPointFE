import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/shared/widgets/brand_star.dart';

/// "Inteshar Sunburst" — retail-brand primitives. Cards float on soft drop
/// shadows, status reads as friendly chips (not rubber stamps), titles are
/// chunky sans (not editorial italic serif), brand identity is the angular
/// flying-star mark (not a publisher monogram).
///
/// ## Icon style (UX-139)
///
/// **Outlined is the default.** A UI icon — in a button, a row, a chip, a list
/// tile — is `Icons.x_outlined`.
///
/// Filled is reserved for three cases, and they are the only ones:
/// * the **selected** half of a navigation pair (`_NavItem(icon, selectedIcon)`),
///   where the weight change IS the selection signal;
/// * a **brand mark** rendered large (see `pos_brand.dart` at 40–64px), where an
///   outline reads as a diagram rather than a logo;
/// * a **glyph under ~12px** (a `StampPill` badge), where the outline's interior
///   collapses and the shape stops being legible.
///
/// The drift this replaced was not aesthetic: `printer_picker_page` used
/// `Icons.print_disabled_outlined : Icons.print` inside a single ternary, so one
/// control changed weight as well as meaning when a printer went unreachable.
///
/// ## Where a page's actions go (UX-17)
///
/// **One rule: a page's actions live in the page header, rendered by
/// [PageActions], and nowhere else.**
///
/// Today the same job is done in four places — the catalog floats a FAB, agents
/// and companies use header buttons, batch-add puts its action inline in the
/// content, and pricing pins Save to the bottom edge while its Export and Upload
/// sit in the header. That last one is the tell: it is a single toolbar split
/// across two opposite edges of one screen. An operator who has learned where
/// "the button" is on one screen has learned nothing about the next.
///
/// The header wins for reasons, not taste:
/// * it is the only slot that exists on **every** screen already — [PageHeader]
///   is on all ~24 routed pages, so adopting the rule removes code rather than
///   adding chrome;
/// * it is the only slot that survives **RTL**: it anchors to the end edge, the
///   same edge the eye lands on first in Arabic, and it moves automatically;
/// * a **FAB** cannot be that slot. It floats over the content it acts on, it
///   collides with the phone bottom bar and the POS on-screen keyboard, and it
///   can hold exactly one action — so the moment a screen grows a second one
///   (export, upload, refresh) the FAB has to be abandoned anyway;
/// * a **bottom-pinned Save** cannot be it either: it is invisible above the
///   fold on desktop, and it competes with the bottom nav on a phone.
///
/// Three exceptions, and only these:
/// 1. an action that belongs to a **row** belongs in that row (delete this
///    agent, reveal this voucher) — it is not the page's action;
/// 2. a **sheet or dialog's** confirm belongs in that sheet's own footer
///    (`SheetFrame`), because it commits the sheet, not the page;
/// 3. the **POS sell CTA** keeps its full-width pinned pill. It is the entire
///    purpose of that screen, it is used one-handed on a handheld, and thumb
///    reach beats consistency on exactly one screen.
///
/// [PageActions] handles the narrow case so no screen has to invent its own:
/// secondary actions collapse into an overflow menu, and below that the primary
/// becomes icon-only with its label as the tooltip — the title never gets
/// squeezed by a button pair again (see UX-115 on [PageHeader]).

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
    this.padding = const EdgeInsets.fromLTRB(0, 0, 0, IntesharSpacing.md),
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
              padding: const EdgeInsetsDirectional.only(end: IntesharSpacing.sm2),
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
              style: IntesharText.bodyLg(
                color: cs.onSurface,
                w: IntesharWeight.heavy,
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

/// How much air an [InkCard] puts around its content (UX-135).
///
/// 55 of 61 `InkCard` sites overrode `padding` across **17 distinct values** —
/// `all(14)`, `all(12)`, `all(10)`, `all(24)`, `symmetric(14, 12)`… Adjacent
/// cards differing by 2px do not read as a deliberate hierarchy; they read as
/// nobody having decided. Three named densities is the decision.
enum CardDensity {
  /// 12 — list rows, chips-in-a-card, anything repeated many times per screen.
  dense(IntesharSpacing.md),

  /// 16 — the default. Ordinary content cards.
  normal(IntesharSpacing.lg),

  /// 24 — hero/summary cards that own their region of the page.
  roomy(IntesharSpacing.xl);

  const CardDensity(this.value);
  final double value;

  EdgeInsets get padding => EdgeInsets.all(value);
}

/// **The** card in this app. White surface tile with a soft drop shadow.
/// Optionally paints a yellow accent ridge along the start edge (`ruleColor`) —
/// this preserves the existing API but reads as a brand mark, not an editorial
/// print rule.
///
/// UX-126: there used to be a second, hand-rolled recipe — `cs.surface` (which
/// *is* the page background) plus a hairline — at five sites, including the
/// balance hero on the landing screen for three of the four roles, inches away
/// from real `InkCard`s. Two definitions of "a card" on one viewport is the most
/// legible form of drift there is. The white fill wins (it is the ~60-site
/// majority and the one `cardTheme` paints); [bordered] carries the hairline for
/// the callers that wanted the extra definition.
///
/// UX-121 — **hover**. A tappable card had no pointer feedback whatsoever. The
/// `InkWell` below does carry `splashColor`/`highlightColor`, but its ink paints
/// on the `Material` *underneath* its child, and that child is an opaque tile —
/// so every ripple and hover overlay was drawn and then covered up. On the HQ
/// console, which is a full-time mouse workload, nothing on a card said it could
/// be clicked until you clicked it. The feedback therefore has to live in the
/// tile's own decoration, which is what [_InkCardState] does.
class InkCard extends StatefulWidget {
  final Widget child;
  final Color? ruleColor;

  /// Free-form padding **escape hatch**. Prefer [density]; this stays because 55
  /// existing call sites pass it, and a card that genuinely needs asymmetric
  /// insets (a tile whose trailing edge holds a full-bleed action) has nowhere
  /// else to say so. When null, [density] decides.
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? background;

  /// Legacy alias for `density: CardDensity.dense`.
  ///
  /// It was declared, defaulted to `false`, and **never read by `build`** — a
  /// dead knob that silently did nothing for anyone who set it. It is wired up
  /// now; [density] is the way to say this going forward.
  final bool dense;

  /// How much padding the card carries when [padding] is not given.
  final CardDensity density;
  final bool elevated;

  /// Adds the 1px `outlineVariant` hairline around the tile (UX-126). The fill
  /// stays `surfaceContainer` — a card is never the page colour.
  ///
  /// UX-153: this is now a FLOOR, not a switch. Modes where a drop shadow cannot
  /// carry an edge (dark, high contrast) turn the hairline on for every card via
  /// `SurfaceTreatment`, so passing `false` never means "no edge" — it means "no
  /// edge beyond what the theme needs".
  final bool bordered;

  const InkCard({
    super.key,
    required this.child,
    this.ruleColor,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.background,
    this.dense = false,
    this.density = CardDensity.normal,
    this.elevated = true,
    this.bordered = false,
  });

  @override
  State<InkCard> createState() => _InkCardState();
}

class _InkCardState extends State<InkCard> {
  bool _hovered = false;

  /// Long enough to read as a response, short enough that dragging the pointer
  /// across a roster does not leave a trail of tiles still animating.
  static const _hoverFade = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tones = context.tones;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(IntesharRadii.lg);
    final insets = widget.padding ??
        (widget.dense ? CardDensity.dense : widget.density).padding;
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final hovered = interactive && _hovered;

    final content = ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          if (widget.ruleColor != null)
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: widget.ruleColor),
            ),
          Padding(
            padding: widget.ruleColor != null
                ? insets.add(const EdgeInsetsDirectional.only(start: 4))
                : insets,
            child: widget.child,
          ),
        ],
      ),
    );

    // UX-153: how a card is separated from the page is a THEME decision now —
    // a 5%-black shadow needs a light page and ambient contrast, and neither
    // dark mode nor daylight provides them. In the stock light theme this is
    // byte-identical to the previous `IntesharShadows.elev1` + no border.
    final surfaces = context.surfaces;
    final base = widget.background ?? cs.surfaceContainer;
    // UX-121: the hover signal is a brand WASH over the fill, not a lift, so it
    // still lands in the two modes where `surfaces.shadow` is empty by design
    // (dark, high contrast) and a raised shadow would say nothing at all. The
    // lift is layered on top wherever shadows are in play.
    final tile = AnimatedContainer(
      duration: _hoverFade,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: hovered
            ? Color.alphaBlend(tones.brand.withValues(alpha: 0.06), base)
            : base,
        borderRadius: radius,
        // Only the border's COLOUR reacts. Growing a border on hover would
        // inset the child by a pixel and make the whole card's content twitch.
        border: (widget.bordered || surfaces.hairline)
            ? Border.all(
                color: hovered
                    ? tones.brandOnSurface.withValues(alpha: 0.45)
                    : cs.outlineVariant)
            : null,
        boxShadow: widget.elevated
            ? (hovered ? surfaces.shadowRaised : surfaces.shadow)
            : const [],
      ),
      child: content,
    );

    if (!interactive) return tile;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: radius,
        // `onHover` reuses the MouseRegion InkWell already builds, and only ever
        // fires for a real pointer — a finger never triggers it.
        onHover: (h) {
          if (h != _hovered) setState(() => _hovered = h);
        },
        splashColor: tones.brand.withValues(alpha: 0.10),
        highlightColor: tones.brand.withValues(alpha: 0.05),
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
  static const double minFontSize = IntesharScale.body;

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
    this.fontSize = IntesharScale.body,
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
        horizontal: icon != null ? IntesharSpacing.sm : IntesharSpacing.sm2,
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
            const SizedBox(width: IntesharSpacing.xs),
          ],
          Text(
            label,
            style: IntesharType.sans(
              size,
              color: foreground,
              w: IntesharWeight.bold,
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

/// How large a [FigureBlock]'s hero numeral is drawn.
///
/// The app had 13 hand-built stat tiles across dashboard, system activity,
/// pos_admin, pos_network, pos_sales, reports, batch_add and inventory, with
/// hero numerals at **ten** sizes — 17/18/19/20/22/24/26/30/32/34 — including
/// two tiles that differed only by `fontSize 24 vs 22` and `divider 34 vs 30`.
/// Those are the same tile. Pick a size here instead of inventing one.
enum FigureSize {
  /// [IntesharScale.title] — a figure inside a dense row or a narrow column.
  small(IntesharScale.title),

  /// [IntesharScale.display] — the default KPI tile.
  medium(IntesharScale.display),

  /// [IntesharScale.displayLg] — the one hero figure on a page (a balance).
  large(IntesharScale.displayLg);

  const FigureSize(this.value);
  final double value;
}

/// **The** stat tile: stacked label / hero numeral / caption note.
///
/// UX-130: this existed with **zero** call sites while thirteen local
/// re-implementations of it lived in features. It is the canonical one — a new
/// stat tile uses this, and the thirteen should migrate to it rather than a
/// fourteenth variation being written.
///
/// [monoValue] switches the numeral to JetBrains Mono, which is right whenever
/// figures are stacked in a column and must align on the digit — a balance
/// ledger, a serial count — and wrong for a single standalone KPI, where the
/// proportional brand face reads better.
/// The brand-filled KPI strip: two or more figures in a row on a brand slab.
///
/// Distinct from [FigureBlock] on purpose, and not a variant of it. FigureBlock
/// is a figure on PAPER — its label is `onSurfaceVariant` and its value
/// `onSurface`. This one sits on `tones.brand`, so every foreground is the
/// MEASURED `onBrand`; passing paper colours here is how a dark white-label
/// brand (navy, maroon) ends up with near-black text on a near-black slab.
///
/// It exists because `pos_admin_page` and `pos_network_view` had built it twice,
/// identically, down to the 18/16 padding and the `alpha: 0.18` divider —
/// differing only in a numeral at 24 vs 22 and a divider at 34 vs 30, which is
/// drift rather than intent. Standardised on [IntesharScale.display].
class BrandKpiStrip extends StatelessWidget {
  /// Label/value pairs, laid out left to right with a hairline between each.
  final List<(String label, String value)> stats;

  const BrandKpiStrip({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      if (i > 0) {
        children.add(Container(
          width: 1,
          height: 34,
          color: tones.onBrand.withValues(alpha: 0.18),
        ));
      }
      final (label, value) = stats[i];
      children.add(Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IntesharType.overline(
                  color: tones.onBrand.withValues(alpha: 0.7))),
          const SizedBox(height: 2),
          // FittedBox so an unbounded figure (a money total, or the root's "∞")
          // shrinks rather than overflowing a fixed-width column.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                maxLines: 1,
                style: IntesharText.display(color: tones.onBrand)
                    .copyWith(height: 1)),
          ),
        ]),
      ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: tones.brand,
        borderRadius: BorderRadius.circular(IntesharRadii.lg),
      ),
      child: Row(children: children),
    );
  }
}

class FigureBlock extends StatelessWidget {
  final String label;
  final String value;
  final String? note;

  /// Colour of the 6px dot before the label. Defaults to `tones.brand`.
  final Color? accent;

  /// Colour of the figure itself. Defaults to `onSurface` — set it only when the
  /// NUMBER carries a status the reader must not miss (a non-zero "not printed"
  /// count in danger, say). Distinct from [accent], which decorates; this one
  /// means something.
  final Color? valueColor;
  final bool monoValue;

  /// Hero-numeral size. Defaults to [FigureSize.medium].
  final FigureSize size;

  /// Hide the 6px accent dot before the label — for tiles laid out in a grid
  /// where a dot per cell is noise.
  final bool showDot;

  const FigureBlock({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.accent,
    this.valueColor,
    this.monoValue = false,
    this.size = FigureSize.medium,
    this.showDot = true,
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
            if (showDot) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: IntesharSpacing.sm),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: IntesharText.body(
                  color: cs.onSurfaceVariant,
                  w: IntesharWeight.semibold,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
        IntesharSpacing.gapSm,
        // FittedBox so a long figure (a balance in dinars runs to 10+ digits)
        // shrinks instead of overflowing the tile it was sized for.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            maxLines: 1,
            style: monoValue
                ? IntesharType.mono(size.value,
                    color: valueColor ?? cs.onSurface, w: IntesharWeight.bold)
                : IntesharType.display(size.value,
                    color: valueColor ?? cs.onSurface, w: IntesharWeight.black),
          ),
        ),
        if (note != null) ...[
          IntesharSpacing.gapXs,
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

// ─── Page actions (UX-17) ──────────────────────────────────────────────────

/// One action a page offers. See the "Where a page's actions go" rule at the
/// top of this file.
@immutable
class PageAction {
  final String label;
  final IconData icon;

  /// `null` disables the control. A disabled action still renders — an action
  /// that disappears when it is unavailable teaches the operator it was never
  /// there (UX-146 made the same argument for the POS CTA).
  final VoidCallback? onPressed;

  /// Swaps the icon for a spinner and blocks the tap. The label stays, so the
  /// button does not change width mid-submit.
  final bool busy;

  /// Paints the action in `status.danger`. For destructive page-level actions
  /// only — a row's delete belongs in the row (exception 1 of the rule).
  final bool danger;

  const PageAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.busy = false,
    this.danger = false,
  });

  bool get enabled => onPressed != null && !busy;
}

/// **The** action cluster for a page — one primary, any number of secondaries,
/// always in [PageHeader]'s trailing slot.
///
/// Degrades by available width rather than by screen size, because the slot it
/// lives in is capped at 55% of the header (UX-115):
///
/// | width      | rendering |
/// |------------|-----------|
/// | ≥ [_wide]  | secondaries as outlined buttons, then the primary filled |
/// | ≥ [_icons] | secondaries collapse into a `⋮` menu, primary keeps its label |
/// | below      | primary becomes icon-only, label moves to its tooltip |
///
/// The primary is **last** so it sits against the end edge — the edge the eye
/// reaches first in Arabic, and the same place on every screen.
class PageActions extends StatelessWidget {
  final PageAction? primary;
  final List<PageAction> secondary;

  const PageActions({
    super.key,
    this.primary,
    this.secondary = const <PageAction>[],
  });

  /// Below this the secondaries fold into an overflow menu.
  static const double _wide = 340;

  /// Below this the primary drops its label too.
  static const double _icons = 168;

  Widget _spinner(Color color) => SizedBox(
        width: IntesharScale.title,
        height: IntesharScale.title,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        // An unbounded slot (a bare Row) counts as wide — nothing is squeezing.
        final width = c.maxWidth.isFinite ? c.maxWidth : double.maxFinite;
        final inline = width >= _wide;
        final labelled = width >= _icons;
        final children = <Widget>[];

        if (inline) {
          for (final a in secondary) {
            children.add(_secondaryButton(context, a));
            children.add(const SizedBox(width: IntesharSpacing.sm));
          }
        } else if (secondary.isNotEmpty) {
          children.add(_overflow(context));
          children.add(const SizedBox(width: IntesharSpacing.sm));
        }

        final p = primary;
        if (p != null) {
          final fg = p.danger ? cs.onError : cs.onPrimary;
          final bg = p.danger ? context.status.danger : cs.primary;
          children.add(
            labelled
                ? FilledButton.icon(
                    onPressed: p.enabled ? p.onPressed : null,
                    style: FilledButton.styleFrom(
                        backgroundColor: bg, foregroundColor: fg),
                    icon: p.busy ? _spinner(fg) : Icon(p.icon, size: 18),
                    label: Text(p.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  )
                : Tooltip(
                    message: p.label,
                    child: IconButton.filled(
                      onPressed: p.enabled ? p.onPressed : null,
                      style: IconButton.styleFrom(
                          backgroundColor: bg, foregroundColor: fg),
                      icon: p.busy ? _spinner(fg) : Icon(p.icon),
                    ),
                  ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: children,
        );
      },
    );
  }

  Widget _secondaryButton(BuildContext context, PageAction a) {
    final fg = a.danger
        ? context.status.danger
        : Theme.of(context).colorScheme.onSurface;
    return OutlinedButton.icon(
      onPressed: a.enabled ? a.onPressed : null,
      style: OutlinedButton.styleFrom(foregroundColor: fg),
      icon: a.busy ? _spinner(fg) : Icon(a.icon, size: 18),
      label: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _overflow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      position: PopupMenuPosition.under,
      // The menu is the page's own actions, so name it as such for a screen
      // reader instead of leaving a bare "show menu".
      tooltip: Localizations.localeOf(context).languageCode == 'ar'
          ? 'إجراءات الصفحة'
          : 'Page actions',
      icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
      onSelected: (i) => secondary[i].onPressed?.call(),
      itemBuilder: (_) => [
        for (var i = 0; i < secondary.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: secondary[i].enabled,
            child: Row(
              children: [
                Icon(secondary[i].icon, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: IntesharSpacing.md),
                Flexible(
                  child: Text(secondary[i].label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Page header ───────────────────────────────────────────────────────────

/// Friendly page header: muted section overline + bold sans title + muted
/// subtitle + brand underline accent.
///
/// UX-98: [showEyebrow] used to default to `false` with **no call site setting
/// it**, while [eyebrow] stayed a *required* parameter — so all ~24 routed
/// screens computed and translated a bilingual section label that was then
/// thrown away. On a phone, once the "More" sheet closes there is no breadcrumb
/// widget anywhere in the app, so nothing told the operator which section they
/// were standing in. It is on by default now; a caller with a genuinely
/// section-less page can still pass `showEyebrow: false`.
class PageHeader extends StatelessWidget {
  /// Muted overline above the title, naming the SECTION this page belongs to
  /// (ideally matching the desktop sidebar's group header — "Oversight",
  /// "Inventory & Stock", "Network", "Catalog", "Administration", "Operations",
  /// "Points of Sale"). Rendered upper-case; Arabic is unaffected by casing.
  ///
  /// Redundant values are dropped rather than stacked — see [_eyebrowIsRedundant].
  final String eyebrow;
  final String title;
  final String? subtitle;

  /// Free-form trailing slot. Prefer [actions] — see the UX-17 rule at the top
  /// of this file. This stays for the trailing widgets that are genuinely not
  /// actions (a live status chip, a period selector).
  final Widget? trailing;

  /// **The** slot for this page's actions (UX-17). Renders at the end edge, and
  /// degrades to an overflow menu / icon-only primary as the header narrows, so
  /// a button pair can never squeeze the title again.
  final PageActions? actions;
  final EdgeInsetsGeometry padding;
  final bool showEyebrow;
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(
      IntesharSpacing.lg,
      IntesharSpacing.lg,
      IntesharSpacing.lg,
      IntesharSpacing.md,
    ),
    this.showEyebrow = true,
  });

  /// True when painting [eyebrow] above [title] would only repeat it.
  ///
  /// Several screens pass the same string for both (System Activity, Catalog,
  /// Hierarchy) or an eyebrow the title already opens with ("Templates" over
  /// "Voucher Templates"). Stacking those reads as a rendering bug, not as
  /// section context, so they are suppressed. Case- and whitespace-insensitive;
  /// `toLowerCase` is a no-op for Arabic, where the equality check still holds.
  static bool _eyebrowIsRedundant(String eyebrow, String title) {
    final e = eyebrow.trim().toLowerCase();
    final t = title.trim().toLowerCase();
    if (e.isEmpty) return true;
    return t == e || t.startsWith(e);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final withEyebrow = showEyebrow && !_eyebrowIsRedundant(eyebrow, title);
    // UX-17: `actions` is the rule; `trailing` is the escape hatch. When both
    // are given the actions win, because a screen that passes both has almost
    // certainly grown a second toolbar — the thing the rule exists to stop.
    final end = actions ?? trailing;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withEyebrow) ...[
            Text(
              // Call sites are split between 'OVERSIGHT' and 'Stock'. Normalise
              // here so the section label is one thing across the app, and so it
              // matches the sidebar's `_GroupHeader` treatment.
              eyebrow.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // UX-141: `overline` drops the tracking for a cursive locale, so
              // the eyebrow keeps its Latin look without breaking Arabic joins.
              style: IntesharType.overline(
                color: cs.onSurfaceVariant,
                letterSpacing: 1.2,
              ).copyWith(fontWeight: IntesharWeight.heavy),
            ),
            IntesharSpacing.gapSm,
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
                      style: IntesharText.displayLg(color: cs.onSurface),
                    ),
                  ),
                ),
                if (end != null) ...[
                  const SizedBox(width: IntesharSpacing.md),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.55,
                    ),
                    child: end,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          const BrandRule(),
          if (subtitle != null) ...[
            IntesharSpacing.gapMd,
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

  /// When `true`, render the lockup on the BRAND surface (`cs.primary`, what
  /// [BrandBand] paints). When `false`, render on a paper surface.
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
    // UX-123: this used to hardcode near-black `IntesharColors.ink` on a surface
    // the theme paints with `cs.primary` — so a dark white-label brand (navy,
    // maroon: plausible telecom colours) rendered the wordmark black-on-dark.
    // `onPrimary` is measured by contrast for exactly this. The sibling version
    // string in the very same BrandBand (app_scaffold `_AboutDrawer`) already
    // did it this way, as does `brand_masthead.dart`.
    final fg = onBrandSurface ? cs.onPrimary : cs.onSurface;
    final fgSoft = onBrandSurface
        ? cs.onPrimary.withValues(alpha: 0.65)
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
          const SizedBox(width: IntesharSpacing.md),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // UX-127: was an off-scale 18/22.
                style: IntesharType.sans(
                  compact ? IntesharScale.title : IntesharScale.titleLg,
                  color: fg,
                  w: IntesharWeight.black,
                  letterSpacing: -0.4,
                  height: 1.0,
                ),
              ),
              if (showTagline) ...[
                IntesharSpacing.gapXs,
                Text(
                  tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // UX-127: was 10.5 / 11.5 — two half-point steps for one label.
                  style: IntesharText.caption(
                    color: fgSoft,
                    w: IntesharWeight.semibold,
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
/// UX-127: the default was an off-scale 13; `body` (12) is the size the ~39
/// explicit `IntesharType.mono` call sites already cluster on.
SelectableText monoText(
  String value, {
  double size = IntesharScale.body,
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
///
/// UX-149: this was a bare [GestureDetector], which is invisible to everything
/// that is not a finger. Tab skipped these tiles, Enter did nothing, and a
/// screen reader announced no control at all — on the POS selling tiles, which
/// are the most-used control in the product. It stays a GestureDetector (the
/// feedback here is a scale, deliberately not an ink ripple) but is now
/// focusable, keyboard-activatable and announced as a button.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  /// Corner radius of the keyboard focus ring. Match the tile it wraps —
  /// the ring is painted OVER the child, so it cannot be inferred.
  final double focusRadius;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.focusRadius = IntesharRadii.lg,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  bool _focused = false;

  void _activate() {
    HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      child: Focus(
        // A tile with no action is not a tab stop.
        canRequestFocus: widget.onTap != null,
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            _activate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: _activate,
          child: AnimatedScale(
            scale: _down ? widget.scale : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            // Foreground decoration: the ring paints over the tile without
            // taking layout space, so focusing one cannot reflow the grid.
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.focusRadius),
                border: _focused
                    ? Border.all(color: cs.primary, width: 2)
                    : const Border.fromBorderSide(BorderSide.none),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
