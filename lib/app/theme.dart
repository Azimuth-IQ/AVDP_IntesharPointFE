import 'package:flutter/material.dart';
import 'package:inteshar/shared/widgets/responsive.dart';

/// "Inteshar Sunburst" — the brand-led design language.
///
/// Sampled from the Inteshar identity: the official brand gold (#E2AD25) as
/// the single hero accent, anchored by near-black ink for structure and clean
/// off-white surfaces (warm charcoal in dark mode). Sage stands in for "available/success" because a green
/// reads cleanly against yellow; a clean crimson handles errors. The whole UI
/// is set in Codec Pro (twelve weights covering display through body) with
/// JetBrainsMono reserved for serials, PINs and MAC addresses.

/// Local font family registered in pubspec.yaml.
const String _kCodec = 'CodecPro';
class IntesharColors {
  // Light surface stack — cool neutrals + pure-white cards (Figma-aligned;
  // deliberately NOT cream, so the brand gold reads as the only warm note).
  static const paper      = Color(0xFFF6F7F9); // page bg — cool off-white
  static const card       = Color(0xFFFFFFFF); // elevated surface — pure white
  static const sunk       = Color(0xFFEEF0F3); // recessed surface (filter bars)
  static const ink        = Color(0xFF16181D); // primary text/structure
  static const inkSoft    = Color(0xFF5A616C); // secondary text — cool grey
  static const lichen     = Color(0xFF7B828F); // tertiary text / placeholders
  static const hairline   = Color(0xFFE2E5EA); // borders — cool hairline
  static const hairlineSoft = Color(0xFFEEF0F3); // faint divider

  // Accents — `saffron` keeps its name but is now the official brand gold.
  static const saffron    = Color(0xFFE2AD25); // official brand gold #E2AD25 (was #F5B100) — primary fills
  static const saffronDeep = Color(0xFF9C7515); // dark amber — brand-tinted text/icons, pressed/hover
  static const oxblood    = Color(0xFFDC2626); // outgoing / danger — clean red
  static const sage       = Color(0xFF1E9E5A); // available / success — clean green
  /// SEMANTIC warning amber (pending/warn states). Deliberately NOT brand-tinted —
  /// a status colour must stay readable as "caution" under any white-label brand.
  static const warn       = Color(0xFF9C7515);
  /// SEMANTIC "in flight" blue — pending / processing / queued / sending. Same
  /// rule as [warn]: never brand-tinted, because "still moving" must not read as
  /// "done" or "failed" under a white-label palette.
  static const azure      = Color(0xFF2563EB);
  static const dust       = Color(0xFFFFEAB8); // soft gold wash (tags, primaryContainer)
  /// ROLE tint for AGENT1 (Main Agent) — an ink blue that reads as "structure"
  /// and collides with neither the brand gold nor any semantic status colour.
  /// UX-137: this was a bare `Color(0xFF2C3A55)` inlined in `role_badge.dart`
  /// with no token and no dark counterpart.
  static const slate      = Color(0xFF2C3A55);

  // Dark surface stack
  static const inkPaper   = Color(0xFF121110); // dark page bg — brand warm charcoal
  static const inkCard    = Color(0xFF1C1A18); // dark elevated
  static const inkSunk    = Color(0xFF262320); // dark recessed
  static const bone       = Color(0xFFF5F2EA); // dark mode "ink" (text)
  static const boneSoft   = Color(0xFFB3B0A6);
  static const hairlineDark = Color(0x2EF5F2EA);

  static const saffronOnDark = Color(0xFFECBC3F); // brand gold lifted for legibility on charcoal
  static const slateOnDark  = Color(0xFF9DB0CE); // AGENT1 role tint, lifted for charcoal
  static const sageOnDark   = Color(0xFF7CA690);
  static const oxbloodOnDark = Color(0xFFE0625A);
}

class IntesharRadii {
  // B-094: larger radii read as current; 8→10, 12→14, 18→20 keeps the scale's
  // rhythm while softening every surface at once.
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

/// The spacing scale (UX-135). Gaps, paddings and insets come from here.
///
/// It was declared long ago and referenced **zero** times in 49k lines, so the
/// app drifted to 169 off-scale gaps with `EdgeInsets.all(14)` — a value that is
/// on no scale at all — as its single most common padding. Two adjacent cards
/// with 14 and 16 of padding do not read as "different"; they read as sloppy.
///
/// [sm2] is the one deliberate half-step: it is the old `10` that shows up in
/// tight chip/pill interiors where 8 crowds the glyphs and 12 wastes a phone's
/// width. Everything else snaps to 4/8/12/16/24/32.
class IntesharSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const sm2 = 10.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// Vertical gap of [size]. Reads better than a bare `SizedBox` in a Column.
  static const gapXs = SizedBox(height: xs);
  static const gapSm = SizedBox(height: sm);
  static const gapMd = SizedBox(height: md);
  static const gapLg = SizedBox(height: lg);
  static const gapXl = SizedBox(height: xl);
}

// ─── Type scale (UX-127) ─────────────────────────────────────────────────────

/// The app's **seven** type sizes. Every new `fontSize` comes from here.
///
/// The app had drifted to **28** distinct sizes, including half-point steps
/// (9.5/10.5/11.5/12.5/13.5/14.5) that no screen can render as distinct, and
/// seven near-identical body sizes carrying ~307 call sites. Meanwhile
/// [IntesharType.sans] was called 238× — *always* with an explicit size — while
/// the carefully tuned 16-style [TextTheme] was read 41 times. Two type systems,
/// one of them dead.
///
/// So the steps below are deliberately **the same numbers the `TextTheme`
/// already uses**, and each one names the theme style it corresponds to. Reading
/// `Theme.of(context).textTheme.bodyMedium` and writing
/// `IntesharType.bodyLg(...)` now produce the same size — they cannot drift.
///
/// | step        | px | `TextTheme` equivalent            | use |
/// |-------------|----|-----------------------------------|-----|
/// | [caption]   | 11 | `labelSmall`                      | overlines, meta, timestamps, unit suffixes |
/// | [body]      | 12 | `labelMedium` / `bodySmall`       | secondary body, chip labels, table cells |
/// | [bodyLg]    | 14 | `bodyMedium` / `titleSmall`       | **default body**, list rows, form text |
/// | [title]     | 16 | `bodyLarge` / `titleMedium`       | card titles, list-row primaries |
/// | [titleLg]   | 20 | `titleLarge`                      | section/sheet titles, app-bar titles |
/// | [display]   | 24 | `headlineSmall`                   | stat-tile numerals, sheet hero |
/// | [displayLg] | 32 | `headlineLarge`                   | page titles, balance heroes |
///
/// Sizes above 32 (a splash wordmark, the POS total) are genuinely one-offs and
/// stay explicit — they are not a *tier*, and pretending otherwise would just
/// grow the scale back.
class IntesharScale {
  static const double caption = 11;
  static const double body = 12;
  static const double bodyLg = 14;
  static const double title = 16;
  static const double titleLg = 20;
  static const double display = 24;
  static const double displayLg = 32;

  /// Ascending, for migration tooling and tests.
  static const List<double> steps = <double>[
    caption,
    body,
    bodyLg,
    title,
    titleLg,
    display,
    displayLg,
  ];

  /// The step nearest to [size] — the migration helper for the ~307 legacy call
  /// sites. Ties round **up**, because shrinking text on a POS handheld held at
  /// arm's length is the more expensive mistake. Sizes above [displayLg] are
  /// returned untouched (see the class note on one-offs).
  static double snap(double size) {
    if (size >= displayLg) return size;
    var best = steps.first;
    var bestDelta = (size - best).abs();
    for (final step in steps) {
      final delta = (size - step).abs();
      // `<=` makes a tie resolve to the LARGER step, since `steps` ascends.
      if (delta <= bestDelta) {
        best = step;
        bestDelta = delta;
      }
    }
    return best;
  }
}

/// The CodecPro weights that actually have a face registered in `pubspec.yaml`.
///
/// **There is no 600 face** — the family ships Light/News/Regular/Bold/ExtraBold/
/// Heavy and nothing between Regular and Bold. `FontWeight.w600` was written at
/// ~100 sites anyway, so the intended "semibold" tier does not exist and each
/// platform invents a different answer for it:
///
/// * **Android** (minikin, nearest-match, ties to the first declared face)
///   resolves 600 to **News** — which, measured, is *lighter than Regular*
///   (normalised ink area 0.376 vs 0.420). So on the Sunmi POS the semibold tier
///   renders **lighter than body text**.
/// * **Web** (CSS font matching, "≥ target first") resolves 600 to **Bold**.
///
/// Same widget, opposite weight, depending on which half of the fleet you are
/// looking at. There is no SemiBold TTF to ship, so [semibold] is an explicit
/// **alias of [bold]**: the nearest real face, and already what the browser
/// shows.
///
/// **[news] is a trap and is not used by this file.** Codec Pro's News sits
/// between Light and Regular, but `pubspec.yaml` registers it at weight 500, so
/// every `FontWeight.w500` in the app renders *lighter* than the `w400` body it
/// is meant to emphasise. Fixing that means re-registering the face (a
/// whole-app rendering change) — see the follow-up note; until then, do not
/// reach for 500 to mean "slightly bolder".
class IntesharWeight {
  /// CodecPro-Light.
  static const FontWeight light = FontWeight.w300;

  /// CodecPro-Regular — body text.
  static const FontWeight regular = FontWeight.w400;

  /// CodecPro-News. **Lighter than [regular]** despite the higher number; see
  /// the class note. Present for completeness, not for use.
  static const FontWeight news = FontWeight.w500;

  /// CodecPro-Bold.
  static const FontWeight bold = FontWeight.w700;

  /// The "semibold" tier. Deliberately **the same face as [bold]** — no 600
  /// face exists. Named separately so the intent stays legible at the call site
  /// and so a real SemiBold, if one is ever licensed, lands in one place.
  static const FontWeight semibold = bold;

  /// CodecPro-ExtraBold.
  static const FontWeight heavy = FontWeight.w800;

  /// CodecPro-Heavy.
  static const FontWeight black = FontWeight.w900;

  /// Weights with a real registered face. `w600` is absent on purpose.
  ///
  /// `final`, not `const`: Dart forbids a const set whose element type
  /// overrides `==`/`hashCode`, and `FontWeight` does. Local Flutter (3.38.5)
  /// still accepts the const form, CI (3.47.1) rejects it as
  /// `const_set_element_not_primitive_equality` — so a clean local `analyze`
  /// is not a CI pass. Leave this `final`.
  static final Set<FontWeight> registered = <FontWeight>{
    light,
    regular,
    news,
    bold,
    heavy,
    black,
  };
}

/// Soft drop-shadow stack — replaces the hairline-border elevation pattern.
/// `elev1` is the default for floating tiles; `elev2` for emphasis (sheets,
/// hero cards). `ctaShadow` is the warm yellow glow under primary CTA pills.
class IntesharShadows {
  // B-094: lighter, tighter elevation — surfaces should feel like paper on paper,
  // not cards floating over a page. Depth now comes mostly from hairline borders.
  static const elev1 = [
    BoxShadow(blurRadius: 10, offset: Offset(0, 2), color: Color(0x0D000000)),
  ];
  static const elev2 = [
    BoxShadow(blurRadius: 20, offset: Offset(0, 6), color: Color(0x14000000)),
  ];
  static const ctaShadow = [
    BoxShadow(blurRadius: 22, offset: Offset(0, 8), color: Color(0x33A06A00)),
  ];
}

/// CTA gradient stops (top → middle → bottom) for the glossy yellow pill.
class IntesharGradients {
  static const List<Color> ctaPill = [
    Color(0xFFF2CE63), // top highlight
    Color(0xFFE2AD25), // brand body — official gold
    Color(0xFFC28F18), // bottom shadow lip
  ];
  /// Inner highlight — drawn as a 1px top hairline inside the CTA for shine.
  static const Color ctaInnerHighlight = Color(0xFFF7DFA0);
}

// ─── Contrast maths (UX-143) ─────────────────────────────────────────────────
//
// Pure, side-effect-free helpers. Everything that picks a foreground for a
// white-label brand goes through these instead of guessing from luminance.

/// WCAG 2.1 contrast ratio between two opaque colours — 1.0 (identical) to
/// 21.0 (black on white). Alpha is ignored; blend first if you need it.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// The more legible of [light] / [dark] ON [background], by actual ratio.
///
/// Replaces `ThemeData.estimateBrightnessForColor`, which is a luminance
/// THRESHOLD (it flips at ~0.34), not a comparison — so a mid-tone brand such
/// as a `#F97316` orange is called "dark" and gets white at 2.8:1 where near
/// black would have given 6.3:1.
Color legibleOn(
  Color background, {
  Color light = Colors.white,
  Color dark = IntesharColors.ink,
}) =>
    contrastRatio(light, background) >= contrastRatio(dark, background)
        ? light
        : dark;

/// [color] blended toward black (on a light [background]) or white (on a dark
/// one) until it clears [minRatio] against that background.
///
/// Blending toward black/white keeps the hue, so a brand-toned or semantic
/// colour stays recognisable — it only loses lightness. Returns [color]
/// untouched when it already passes.
Color contrastAdjusted(Color color, Color background, {double minRatio = 4.5}) {
  if (contrastRatio(color, background) >= minRatio) return color;
  final toward = background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  for (var step = 1; step <= 50; step++) {
    final blended = Color.alphaBlend(toward.withValues(alpha: step / 50), color);
    if (contrastRatio(blended, background) >= minRatio) return blended;
  }
  // Only reachable for a mid-grey background, where nothing clears the bar.
  return toward;
}

// ─── White-label brand tones (B-085) ─────────────────────────────────────────

Color _lighten(Color c, double amount) =>
    Color.alphaBlend(Colors.white.withValues(alpha: amount), c);
Color _darken(Color c, double amount) =>
    Color.alphaBlend(Colors.black.withValues(alpha: amount), c);

/// Every brand-tinted colour in the app, DERIVED from the session's resolved
/// brand colour so a white-label agent re-tints the whole UI (B-085).
///
/// Widgets must read these from the theme (`context.tones`) instead of the
/// `IntesharColors.saffron*` constants — those are the DEFAULT palette only and
/// stay gold no matter which agent is signed in. With no white-label override the
/// derivations reproduce the original Sunburst gold almost exactly, so the stock
/// look is unchanged.
@immutable
class BrandTones extends ThemeExtension<BrandTones> {
  /// The brand colour itself — fills, accents, active states.
  final Color brand;

  /// Legible label/icon colour ON a [brand] fill (ink or white by luminance).
  final Color onBrand;

  /// Brand-toned colour for text/icons ON A SURFACE — a pale brand is darkened
  /// so it never fails contrast on paper (B-078).
  final Color brandInk;

  /// Brand-toned foreground with a HARD guarantee of ≥4.5:1 against the
  /// surface (UX-143). [brandInk] is the historical token and stays as-is for
  /// the stock gold; this one is measured, so it is what the theme uses
  /// wherever the brand acts as ink (nav label/icon, focus ring, switch,
  /// progress, slider) rather than as a fill.
  final Color brandOnSurface;

  /// Soft brand wash for chip / container / tag BACKGROUNDS — the canonical
  /// one (UX-138).
  ///
  /// It is an *opaque* pre-blended tint, not `brand.withValues(alpha: …)`. The
  /// app had fourteen hand-rolled washes spanning alpha 0.12–0.22 for this one
  /// visual role, none of them this token; being translucent they also drifted
  /// with whatever surface happened to sit behind them. This is the same colour
  /// the theme hands to `ColorScheme.primaryContainer`, so a wash and a
  /// primaryContainer can never disagree.
  ///
  /// For text/icons ON this wash use [brandInk]/[brandOnSurface] — never
  /// `ColorScheme.primary`, which is the fill role and fails contrast as ink.
  final Color brandWash;

  /// Glossy CTA pill gradient (top highlight → body → bottom lip).
  final List<Color> ctaGradient;

  /// 1px inner top hairline that gives the CTA its "chromed candy" shine.
  final Color ctaHighlight;

  /// Warm drop shadow under a primary CTA, tinted by the brand.
  final List<BoxShadow> ctaShadow;

  const BrandTones({
    required this.brand,
    required this.onBrand,
    required this.brandInk,
    required this.brandOnSurface,
    required this.brandWash,
    required this.ctaGradient,
    required this.ctaHighlight,
    required this.ctaShadow,
  });

  /// Derives the full set from a resolved [brand] colour.
  ///
  /// [brandOnSurface] defaults to the brand contrast-corrected against the
  /// mode's page surface, so a caller that doesn't know the resolved surface
  /// still gets a legible token.
  factory BrandTones.from({
    required Color brand,
    required Color onBrand,
    required Color brandInk,
    required bool isDark,
    Color? brandOnSurface,
    Color? brandWash,
  }) {
    return BrandTones(
      brand: brand,
      onBrand: onBrand,
      brandInk: brandInk,
      brandOnSurface: brandOnSurface ??
          contrastAdjusted(
            brand,
            isDark ? IntesharColors.inkPaper : IntesharColors.paper,
          ),
      // UX-138: the theme passes its own wash — the one it also gives to
      // `primaryContainer`. The fallback below is only for a bare
      // `BrandTones.from` (tests, the no-extension default), and used to be a
      // DIFFERENT mix (0.86 vs the theme's 0.78), so the token and
      // `primaryContainer` disagreed wherever both were read.
      brandWash: brandWash ?? (isDark ? _darken(brand, 0.72) : _lighten(brand, 0.78)),
      // B-094: the CTA is now a FLAT brand fill. The old three-stop gradient +
      // inner highlight + warm glow was a skeuomorphic "candy button" and the
      // single most dated element in the app. A whisper of darkening at the
      // bottom keeps it from looking like a flat rectangle without faking gloss.
      ctaGradient: [brand, brand, _darken(brand, 0.05)],
      ctaHighlight: Colors.transparent,
      ctaShadow: [
        BoxShadow(
          blurRadius: 12,
          offset: const Offset(0, 3),
          color: _darken(brand, 0.35).withValues(alpha: 0.14),
        ),
      ],
    );
  }

  @override
  BrandTones copyWith({
    Color? brand,
    Color? onBrand,
    Color? brandInk,
    Color? brandOnSurface,
    Color? brandWash,
    List<Color>? ctaGradient,
    Color? ctaHighlight,
    List<BoxShadow>? ctaShadow,
  }) =>
      BrandTones(
        brand: brand ?? this.brand,
        onBrand: onBrand ?? this.onBrand,
        brandInk: brandInk ?? this.brandInk,
        brandOnSurface: brandOnSurface ?? this.brandOnSurface,
        brandWash: brandWash ?? this.brandWash,
        ctaGradient: ctaGradient ?? this.ctaGradient,
        ctaHighlight: ctaHighlight ?? this.ctaHighlight,
        ctaShadow: ctaShadow ?? this.ctaShadow,
      );

  @override
  BrandTones lerp(covariant BrandTones? other, double t) {
    if (other == null) return this;
    return BrandTones(
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      brandInk: Color.lerp(brandInk, other.brandInk, t)!,
      brandOnSurface: Color.lerp(brandOnSurface, other.brandOnSurface, t)!,
      brandWash: Color.lerp(brandWash, other.brandWash, t)!,
      ctaGradient: [
        for (var i = 0; i < ctaGradient.length; i++)
          Color.lerp(ctaGradient[i], other.ctaGradient[i], t)!,
      ],
      ctaHighlight: Color.lerp(ctaHighlight, other.ctaHighlight, t)!,
      ctaShadow: BoxShadow.lerpList(ctaShadow, other.ctaShadow, t) ?? ctaShadow,
    );
  }
}

/// Ergonomic access to the session's [BrandTones]. Falls back to the default
/// gold palette when no theme extension is registered (e.g. bare test pumps).
extension BrandToneContext on BuildContext {
  BrandTones get tones =>
      Theme.of(this).extension<BrandTones>() ??
      BrandTones.from(
        brand: IntesharColors.saffron,
        onBrand: IntesharColors.ink,
        brandInk: IntesharColors.saffronDeep,
        isDark: false,
      );
}

// ─── Status semantics (UX-128) ───────────────────────────────────────────────

/// The app's SIX status meanings, each with exactly one colour.
///
/// The same state was being drawn in opposite colours on adjacent screens —
/// "Used"/`PRINTED` is brand gold in `inventory_page` and `cs.error` **red** in
/// `batch_add_page`, one tap apart on the same field. And `cs.error` was doing
/// duty for things that are not errors at all (an outgoing transfer, a completed
/// sale, unread mail, "ready to delete", a constructive Resume button). On a
/// sales floor red means something went wrong; spending it on a normal sale
/// trains the operator to ignore it on the one screen where it matters.
///
/// Every tone is **contrast-corrected against the page surface** for the current
/// mode, so it is legible as ink or as an icon, and safe to hand to
/// [StampPill] (which re-corrects against the tint it paints — the correction is
/// idempotent). Reach for these instead of `IntesharColors.sage` /
/// `IntesharColors.warn` / `cs.error`, none of which track dark mode.
///
/// | tone       | means                                              | examples |
/// |------------|----------------------------------------------------|----------|
/// | [success]  | finished well, in stock, delivered, available      | `AVAILABLE`, COMPLETED transfer, grant applied |
/// | [warn]     | needs attention, nothing is broken yet             | low stock, unpriced agent, expiring soon |
/// | [danger]   | **a real failure or a destructive act**             | FAILED transaction, delete, printer error |
/// | [neutral]  | inert, archived, not applicable, read              | archived POS, read mail, "—" cells |
/// | [inFlight] | still moving — pending, processing, queued          | `PENDING`, sending, uploading |
/// | [brand]    | ours and deliberate, not a fault                   | `PRINTED`/"Used", a completed sale, an outgoing transfer |
///
/// The last row is the important one: a voucher that has been sold is the happy
/// path, so it is [brand] (and re-tints for a white-label agent), never [danger].
///
/// [success], [warn], [inFlight] and [danger] are deliberately **not**
/// brand-derived — see the note on [IntesharColors.warn]. Only [brand] follows
/// the white-label primary.
@immutable
class StatusTones extends ThemeExtension<StatusTones> {
  final Color success;
  final Color warn;
  final Color danger;
  final Color neutral;
  final Color inFlight;
  final Color brand;

  const StatusTones({
    required this.success,
    required this.warn,
    required this.danger,
    required this.neutral,
    required this.inFlight,
    required this.brand,
  });

  /// Derives the set for [surface], correcting each semantic hue to ≥4.5:1
  /// against it. [brand] is passed in already-measured (the theme's
  /// `brandOnSurface`) so a white-label primary carries through.
  factory StatusTones.forSurface({
    required Color surface,
    required bool isDark,
    required Color brand,
    required Color neutral,
  }) =>
      StatusTones(
        // NOT the theme's `secondary`: see the UX-124 note on `_build`. A
        // white-label secondary must not be able to repaint "available" red.
        success: contrastAdjusted(
          isDark ? IntesharColors.sageOnDark : IntesharColors.sage,
          surface,
        ),
        warn: contrastAdjusted(IntesharColors.warn, surface),
        danger: contrastAdjusted(
          isDark ? IntesharColors.oxbloodOnDark : IntesharColors.oxblood,
          surface,
        ),
        neutral: neutral,
        inFlight: contrastAdjusted(IntesharColors.azure, surface),
        brand: brand,
      );

  @override
  StatusTones copyWith({
    Color? success,
    Color? warn,
    Color? danger,
    Color? neutral,
    Color? inFlight,
    Color? brand,
  }) =>
      StatusTones(
        success: success ?? this.success,
        warn: warn ?? this.warn,
        danger: danger ?? this.danger,
        neutral: neutral ?? this.neutral,
        inFlight: inFlight ?? this.inFlight,
        brand: brand ?? this.brand,
      );

  @override
  StatusTones lerp(covariant StatusTones? other, double t) {
    if (other == null) return this;
    return StatusTones(
      success: Color.lerp(success, other.success, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      inFlight: Color.lerp(inFlight, other.inFlight, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
    );
  }
}

/// Ergonomic access to the session's [StatusTones]. Falls back to the light
/// default when no extension is registered (bare test pumps).
extension StatusToneContext on BuildContext {
  StatusTones get status =>
      Theme.of(this).extension<StatusTones>() ??
      StatusTones.forSurface(
        surface: IntesharColors.paper,
        isDark: false,
        brand: IntesharColors.saffronDeep,
        neutral: IntesharColors.inkSoft,
      );
}

/// The bundled JetBrains Mono family (see `pubspec.yaml`, `assets/fonts/mono/`).
/// Weights 400–800 ship; a `w900` request resolves to ExtraBold, the heaviest
/// face the family has.
const String kMonoFamily = 'JetBrainsMono';

/// Platform monospace families to fall back to if the bundled face is somehow
/// unavailable — and, more usefully, for the glyphs it does not carry (UX-125).
///
/// This used to be the whole defence: `google_fonts` fetched JetBrains Mono at
/// RUNTIME with nothing bundled, so on a POS handheld with a poor link every
/// serial, PIN, price and balance rendered in the PROPORTIONAL default until the
/// fetch landed — permanently if it never did. That breaks column alignment and
/// any `letterSpacing` tuned for fixed advance widths. The face is bundled now,
/// so this chain is a safety net rather than the normal path.
const List<String> kMonoFallback = <String>[
  'RobotoMono', // Android
  'monospace', // Android / Linux / web generic
  'Menlo', // macOS / iOS
  'Courier New', // Windows / web
];

/// Static typography helpers — every named style draws from Codec Pro, with
/// weight and tracking doing the work that two competing families used to.
/// `mono` stays on JetBrainsMono because Codec Pro is proportional and breaks
/// alignment on voucher serials, PINs, and printer MAC addresses.
class IntesharType {
  /// True when the active locale is written in a **cursive** script — Arabic,
  /// which is this product's primary locale (UX-141).
  ///
  /// Letter-spacing is a Latin typographic device: it opens even gaps between
  /// standalone letterforms. Arabic letters *join*, so positive tracking pulls
  /// the joins apart and a word visibly falls into pieces; negative tracking
  /// makes them collide. The app was applying `letterSpacing: 2.2` to 25
  /// [overline] labels and 1.2 to `labelSmall` — on strings that are **always**
  /// translated.
  ///
  /// Set once from `IntesharApp.build`, exactly like `Formatters.languageCode`
  /// next to it, so every existing call site is corrected without touching any
  /// of them. Tracking a caller passes **explicitly** is always honoured — this
  /// only governs the defaults.
  static bool cursiveScript = false;

  /// [tracking] for the current script: suppressed when the locale is cursive.
  static double? _track(double? tracking) {
    if (tracking == null || tracking == 0) return tracking;
    return cursiveScript ? null : tracking;
  }

  /// Heavy display — page wordmarks, hero numerals on ledger cards.
  ///
  /// Prefer the named steps [IntesharText.display] / [IntesharText.displayLg];
  /// this free-size form stays for the genuine one-offs (splash wordmark, POS
  /// total) and for the call sites not yet migrated.
  static TextStyle display(double size,
          {Color? color, FontWeight w = IntesharWeight.heavy}) =>
      TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.05,
        letterSpacing: _track(-0.6),
      );

  /// Body sans — Regular by default.
  ///
  /// Prefer the named steps on [IntesharText]. This is the 238-call-site legacy
  /// entry point: every one of those sites passes an explicit size, which is
  /// how the app ended up with 28 of them (UX-127).
  static TextStyle sans(double size,
          {Color? color,
          FontWeight w = IntesharWeight.regular,
          double? height,
          double? letterSpacing}) =>
      TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: w,
        color: color,
        height: height ?? 1.35,
        letterSpacing: _track(letterSpacing),
      );

  /// **Vestigial** (UX-140). Codec Pro replaced the old Fraunces serif, so this
  /// is now byte-for-byte [sans] with a different default weight — and that
  /// default, `w500`, is Codec Pro's News, which renders *lighter* than the
  /// `w400` it is meant to emphasise (see [IntesharWeight]). Three call sites
  /// remain; use [sans] or an [IntesharText] step instead.
  static TextStyle serif(double size,
          {Color? color,
          FontWeight w = IntesharWeight.news,
          double? height,
          FontStyle? style,
          double? letterSpacing}) =>
      TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: w,
        fontStyle: style,
        color: color,
        height: height ?? 1.2,
        letterSpacing: _track(letterSpacing ?? -0.2),
      );

  /// True monospace — reserved for serials, PINs, MAC addresses, hex dumps.
  ///
  /// UX-125: resolves the BUNDLED [kMonoFamily] synchronously. It used to call
  /// `GoogleFonts.jetBrainsMono`, which returns a style naming a font that may
  /// not have been downloaded yet — every one of these ~110 call sites rendered
  /// proportional until the fetch landed. [kMonoFallback] stays attached for the
  /// glyphs JetBrains Mono does not carry (e.g. Arabic).
  static TextStyle mono(double size, {Color? color, FontWeight w = FontWeight.w500, double? letterSpacing}) =>
      TextStyle(
        fontFamily: kMonoFamily,
        fontFamilyFallback: kMonoFallback,
        fontSize: size,
        fontWeight: w,
        color: color,
        letterSpacing: letterSpacing ?? 0,
      );

  /// Tracking-wide editorial overline. Reads like "DEPARTMENT — SECTION".
  ///
  /// UX-141: the 2.2 tracking is applied **only to Latin**. All 25 call sites
  /// label localized strings, and in Arabic — the primary locale — that tracking
  /// tore the joins of a cursive script apart. Weight, case and colour carry the
  /// "department label" read on their own; the tracking was never load-bearing.
  /// See [cursiveScript].
  static TextStyle overline({
    Color? color,
    double size = IntesharScale.caption,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: IntesharWeight.bold,
        color: color,
        letterSpacing: _track(letterSpacing ?? 2.2),
        height: 1,
      );
}

/// The **seven named type steps** (UX-127) — the API new code should reach for.
///
/// Each returns a Codec Pro [TextStyle] already sized from [IntesharScale] and
/// weighted from [IntesharWeight], so a call site can no longer invent a size or
/// ask for a weight that has no face. They live on their own class because
/// [IntesharType.display] and [IntesharType.sans] are free-size functions with
/// ~263 existing call sites and a required positional `size`; Dart forbids a
/// signature with both optional-positional and named parameters, so the steps
/// could not be layered onto those names without breaking every one of them.
///
/// Equivalent theme styles are listed on [IntesharScale]. When a widget already
/// has a `BuildContext` and wants the *default* colour too, prefer the theme
/// (`Theme.of(context).textTheme.bodyMedium`) — these are for the cases that
/// need a specific colour or weight.
class IntesharText {
  /// 11 · overlines, meta, timestamps, unit suffixes. Bold by default because a
  /// caption this small needs the weight to survive daylight on a POS handheld.
  static TextStyle caption({
    Color? color,
    FontWeight w = IntesharWeight.bold,
    double? height,
    double? letterSpacing,
  }) =>
      IntesharType.sans(IntesharScale.caption,
          color: color, w: w, height: height ?? 1.2, letterSpacing: letterSpacing);

  /// 12 · secondary body, chip labels, dense table cells.
  static TextStyle body({
    Color? color,
    FontWeight w = IntesharWeight.regular,
    double? height,
    double? letterSpacing,
  }) =>
      IntesharType.sans(IntesharScale.body,
          color: color, w: w, height: height, letterSpacing: letterSpacing);

  /// 14 · **the default body step** — list rows, form text, paragraphs.
  static TextStyle bodyLg({
    Color? color,
    FontWeight w = IntesharWeight.regular,
    double? height,
    double? letterSpacing,
  }) =>
      IntesharType.sans(IntesharScale.bodyLg,
          color: color, w: w, height: height, letterSpacing: letterSpacing);

  /// 16 · card titles and list-row primaries. Semibold by default.
  static TextStyle title({
    Color? color,
    FontWeight w = IntesharWeight.semibold,
    double? height,
    double? letterSpacing,
  }) =>
      IntesharType.sans(IntesharScale.title,
          color: color, w: w, height: height ?? 1.25, letterSpacing: letterSpacing);

  /// 20 · section and sheet titles.
  static TextStyle titleLg({
    Color? color,
    FontWeight w = IntesharWeight.heavy,
    double? height,
    double? letterSpacing,
  }) =>
      IntesharType.sans(IntesharScale.titleLg,
          color: color, w: w, height: height ?? 1.2, letterSpacing: letterSpacing);

  /// 24 · stat-tile numerals, sheet heroes.
  static TextStyle display({Color? color, FontWeight w = IntesharWeight.heavy}) =>
      IntesharType.display(IntesharScale.display, color: color, w: w);

  /// 32 · page titles, balance heroes.
  static TextStyle displayLg({Color? color, FontWeight w = IntesharWeight.black}) =>
      IntesharType.display(IntesharScale.displayLg, color: color, w: w);
}

/// Builds a mode's theme, optionally seeded by a white-label brand.
///
/// **UX-124 — [brandSecondary] is a dead control, on purpose.** It feeds
/// `ColorScheme.secondary`, which has **zero readers** in the app; meanwhile
/// every green in the product is the raw `IntesharColors.sage` constant. The
/// tempting fix — route the semantic greens through `cs.secondary` — is the
/// wrong one, and the file already says why one line above
/// [IntesharColors.warn]: a status colour must stay readable as its meaning
/// under any white-label brand. Wiring an agent-chosen hex into "available /
/// success" lets a red or grey secondary make in-stock vouchers read as failed.
/// So the greens now go through [StatusTones.success] (brand-INdependent,
/// mode-aware) and `secondary` keeps its inert Material default.
///
/// That makes `secondaryColor` an editable field that legitimately changes
/// nothing, which is the shipped bug. The honest end state is to REMOVE the
/// control; those edits are outside this file — see the follow-up list for
/// `agent_form.dart`, `entity_tree_page.dart`, `entity.dart`, `branding.dart`
/// and `theme_provider.dart`.
ThemeData _build(
  Brightness b, {
  Color? brandPrimary,
  Color? brandSecondary,
  bool cursive = false,
}) {
  final isDark = b == Brightness.dark;

  final paper       = isDark ? IntesharColors.inkPaper : IntesharColors.paper;
  final card        = isDark ? IntesharColors.inkCard  : IntesharColors.card;
  final sunk        = isDark ? IntesharColors.inkSunk  : IntesharColors.sunk;
  final onPaper     = isDark ? IntesharColors.bone     : IntesharColors.ink;
  final onPaperSoft = isDark ? IntesharColors.boneSoft : IntesharColors.inkSoft;
  final outline     = isDark ? IntesharColors.hairlineDark : IntesharColors.hairline;
  // Brand accents — overridable per Main Agent (white-label, FR-28). With no
  // override the default Sunburst gold/sage are used unchanged.
  final saffron     = brandPrimary   ?? (isDark ? IntesharColors.saffronOnDark : IntesharColors.saffron);
  final sage        = brandSecondary ?? (isDark ? IntesharColors.sageOnDark    : IntesharColors.sage);
  // on-accent colours pick whichever of white/ink actually MEASURES better on
  // the brand (UX-143). `estimateBrightnessForColor` is a luminance threshold,
  // not a contrast comparison, so it handed a mid-tone brand the losing option.
  final onSaffron   = brandPrimary == null ? IntesharColors.ink : legibleOn(brandPrimary);
  final onSage      = brandSecondary == null
      ? (isDark ? IntesharColors.ink : Colors.white)
      : legibleOn(brandSecondary);
  final oxblood     = isDark ? IntesharColors.oxbloodOnDark : IntesharColors.oxblood;
  // Brand-toned foreground with a measured ≥4.5:1 against the page surface —
  // used wherever the brand acts as INK rather than as a fill (nav label/icon,
  // focus ring, switch, progress, slider). Raw `saffron` on white is 2.05:1.
  final brandOnSurface = contrastAdjusted(saffron, paper);
  // Brand-toned colour for TEXT/labels ON a surface — raw `saffron` (bright gold,
  // or a pale white-label primary) fails contrast on paper (B-078). Use the deep
  // amber by default; a white-label brand goes through the measured correction.
  final brandInk = brandPrimary == null
      ? (isDark ? IntesharColors.saffronOnDark : IntesharColors.saffronDeep)
      : brandOnSurface;

  // Soft brand wash used for chips/tags/containers — derived so it tracks a
  // white-label brand instead of staying the stock gold `dust` (B-085).
  final brandWash = isDark ? _darken(saffron, 0.72) : _lighten(saffron, 0.78);

  final scheme = ColorScheme(
    brightness: b,
    // Yellow is a "light" hue — onPrimary must be ink in BOTH modes for contrast.
    primary: saffron,
    onPrimary: onSaffron,
    primaryContainer: brandWash,
    onPrimaryContainer: brandInk,

    secondary: sage,
    onSecondary: onSage,
    secondaryContainer: isDark ? const Color(0xFF1E2A24) : const Color(0xFFD8E4DC),
    onSecondaryContainer: isDark ? IntesharColors.sageOnDark : IntesharColors.sage,

    tertiary: IntesharColors.ink,
    onTertiary: isDark ? IntesharColors.bone : IntesharColors.paper,
    tertiaryContainer: isDark ? const Color(0xFF22232A) : const Color(0xFFE6E4DD),
    onTertiaryContainer: onPaperSoft,

    error: oxblood,
    onError: Colors.white,
    errorContainer: isDark ? const Color(0xFF2A1414) : const Color(0xFFFADAD9),
    onErrorContainer: oxblood,

    surface: paper,
    onSurface: onPaper,
    surfaceContainerLowest: paper,
    surfaceContainerLow: paper,
    surfaceContainer: card,
    surfaceContainerHigh: card,
    surfaceContainerHighest: sunk,
    onSurfaceVariant: onPaperSoft,
    outline: outline,
    outlineVariant: outline,

    inverseSurface: onPaper,
    onInverseSurface: paper,
    inversePrimary: saffron,
    shadow: Colors.black,
    scrim: Colors.black.withValues(alpha: 0.45),
  );

  // Whole text theme in Codec Pro. Display/headline weights lean on Heavy and
  // ExtraBold, body sits at Regular, labels at News/Bold caps.
  TextStyle codec({
    required double size,
    required FontWeight w,
    Color? c,
    double? height,
    double? tracking,
    FontStyle? style,
  }) =>
      TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: w,
        fontStyle: style,
        color: c,
        height: height,
        // UX-141: tracking is a Latin device — suppressed for cursive scripts.
        letterSpacing: cursive ? null : tracking,
      );

  // UX-127: the seven sizes below the headline tier now come from
  // [IntesharScale], so the theme and `IntesharText.*` cannot drift apart.
  // `bodySmall` was the theme's only half-point step (12.5) and is now `body`.
  //
  // Every `w600` is gone: CodecPro registers no 600 face, so that tier resolved
  // to News on Android (lighter than the body it emphasised) and to Bold on the
  // web — see [IntesharWeight]. `semibold` is Bold, the nearest real face.
  final textTheme = TextTheme(
    displayLarge:   codec(size: 57, w: IntesharWeight.black, c: onPaper, height: 1.0,  tracking: -1.6),
    displayMedium:  codec(size: 45, w: IntesharWeight.black, c: onPaper, height: 1.05, tracking: -1.1),
    displaySmall:   codec(size: 36, w: IntesharWeight.heavy, c: onPaper, height: 1.05, tracking: -0.7),
    headlineLarge:  codec(size: IntesharScale.displayLg, w: IntesharWeight.heavy, c: onPaper, height: 1.1,  tracking: -0.5),
    headlineMedium: codec(size: 28, w: IntesharWeight.bold, c: onPaper, height: 1.15, tracking: -0.4),
    headlineSmall:  codec(size: IntesharScale.display, w: IntesharWeight.bold, c: onPaper, height: 1.2,  tracking: -0.3),
    titleLarge:     codec(size: IntesharScale.titleLg, w: IntesharWeight.bold, c: onPaper, height: 1.25, tracking: -0.2),
    titleMedium:    codec(size: IntesharScale.title, w: IntesharWeight.semibold, c: onPaper, height: 1.3,  tracking: 0.0),
    titleSmall:     codec(size: IntesharScale.bodyLg, w: IntesharWeight.semibold, c: onPaper, height: 1.3,  tracking: 0.1),
    bodyLarge:      codec(size: IntesharScale.title, w: IntesharWeight.regular, c: onPaper, height: 1.5),
    bodyMedium:     codec(size: IntesharScale.bodyLg, w: IntesharWeight.regular, c: onPaper, height: 1.45),
    bodySmall:      codec(size: IntesharScale.body, w: IntesharWeight.regular, c: onPaperSoft, height: 1.4),
    labelLarge:     codec(size: IntesharScale.bodyLg, w: IntesharWeight.semibold, c: onPaper,     tracking: 0.4),
    labelMedium:    codec(size: IntesharScale.body, w: IntesharWeight.semibold, c: onPaperSoft, tracking: 0.6),
    labelSmall:     codec(size: IntesharScale.caption, w: IntesharWeight.bold, c: onPaperSoft, tracking: 1.2),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    // B-085: brand-derived tones so every accent (CTA pill, balance card, chips,
    // active states) re-tints for a white-label agent instead of staying gold.
    extensions: <ThemeExtension<dynamic>>[
      BrandTones.from(
        brand: saffron,
        onBrand: onSaffron,
        brandInk: brandInk,
        brandOnSurface: brandOnSurface,
        brandWash: brandWash,
        isDark: isDark,
      ),
      // UX-128: one colour per status meaning, resolved against THIS mode's
      // surface. Read via `context.status`.
      StatusTones.forSurface(
        surface: paper,
        isDark: isDark,
        brand: brandOnSurface,
        neutral: onPaperSoft,
      ),
    ],
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    dividerColor: outline,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: onPaper,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: codec(size: IntesharScale.titleLg, w: IntesharWeight.bold, c: onPaper, tracking: -0.3),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        side: BorderSide(color: outline, width: 1),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: sunk,
      side: BorderSide(color: outline, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.xs)),
      labelStyle: codec(size: IntesharScale.caption, w: IntesharWeight.bold, c: onPaper, tracking: 1.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: IntesharSpacing.lg, vertical: IntesharSpacing.lg),
      hintStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.regular, c: onPaperSoft.withValues(alpha: 0.55)),
      labelStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.regular, c: onPaperSoft),
      floatingLabelStyle: codec(size: IntesharScale.body, w: IntesharWeight.semibold, c: brandInk),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        borderSide: BorderSide(color: outline, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        borderSide: BorderSide(color: outline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        // The focus ring is the only "which field am I in" cue — it has to be
        // visible against the white fill, which raw brand gold is not.
        borderSide: BorderSide(color: brandOnSurface, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        borderSide: BorderSide(color: oxblood, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        borderSide: BorderSide(color: oxblood, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: onPaper,
        foregroundColor: paper,
        textStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.bold, tracking: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        minimumSize: const Size(0, 48),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: saffron,
        // Ink for the stock marigold (white fails WCAG on yellow), but measured
        // per brand — a hardcoded ink was unreadable on a dark white-label fill.
        foregroundColor: onSaffron,
        textStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.heavy, tracking: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onPaper,
        side: BorderSide(color: outline, width: 1),
        textStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.semibold, tracking: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brandInk,
        textStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.semibold, tracking: 0.3),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: onPaper,
      foregroundColor: paper,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
    ),
    dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: onPaperSoft,
      textColor: onPaper,
      titleTextStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.semibold, c: onPaper),
      subtitleTextStyle: codec(size: IntesharScale.body, w: IntesharWeight.regular, c: onPaperSoft),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: onPaper,
      contentTextStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.regular, c: paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: card,
      elevation: 0,
      // UX-120: without this every sheet is viewport-wide, so a one-line input
      // stretches to ~1390dp on a desktop browser. Below 560 it's a no-op, so
      // phones and the POS handheld are unaffected.
      constraints: const BoxConstraints(maxWidth: Breakpoints.formMax),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(IntesharRadii.lg)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        side: BorderSide(color: outline, width: 1),
      ),
      titleTextStyle: codec(size: IntesharScale.titleLg, w: IntesharWeight.bold, c: onPaper, tracking: -0.3),
      contentTextStyle: codec(size: IntesharScale.bodyLg, w: IntesharWeight.regular, c: onPaper, height: 1.45),
    ),
    // UX-145: the selected item used to be the LEAST readable thing on the bar —
    // raw gold on white is 2.05:1 against 6.25:1 for the unselected grey. It now
    // uses the measured brand ink, and carries a weight step as well as a colour
    // step so selection isn't signalled by hue alone (the tint pill is ~1.2:1
    // and can never carry it on its own without wrecking the light style).
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: brandWash,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? brandOnSurface : onPaperSoft, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return codec(
          size: IntesharScale.caption,
          w: selected ? IntesharWeight.heavy : IntesharWeight.semibold,
          tracking: 0.5,
          c: selected ? brandOnSurface : onPaperSoft,
        );
      }),
      height: 64,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      indicatorColor: brandWash,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
      selectedIconTheme: IconThemeData(color: brandOnSurface, size: 22),
      unselectedIconTheme: IconThemeData(color: onPaperSoft, size: 22),
      selectedLabelTextStyle: codec(size: IntesharScale.caption, w: IntesharWeight.heavy, c: brandOnSurface, tracking: 0.4),
      unselectedLabelTextStyle: codec(size: IntesharScale.caption, w: IntesharWeight.regular, c: onPaperSoft, tracking: 0.4),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: brandOnSurface,
      inactiveTrackColor: outline,
      thumbColor: onPaper,
      overlayColor: saffron.withValues(alpha: 0.12),
      trackHeight: 3,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: brandOnSurface,
      linearTrackColor: outline,
      circularTrackColor: outline,
    ),
    switchTheme: SwitchThemeData(
      // The thumb is the state read-out; it must clear the surface, not just the track.
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brandOnSurface : onPaperSoft),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? saffron.withValues(alpha: 0.32) : outline),
    ),
    iconTheme: IconThemeData(color: onPaperSoft, size: 22),
    splashFactory: InkSparkle.splashFactory,
  );
}

final intesharLightTheme = _build(Brightness.light);
final intesharDarkTheme = _build(Brightness.dark);
final _intesharLightThemeCursive = _build(Brightness.light, cursive: true);
final _intesharDarkThemeCursive = _build(Brightness.dark, cursive: true);

/// Parses `#RRGGBB`, `RRGGBB`, or `#AARRGGBB`. Returns null on null/empty/invalid.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim();
  if (h.isEmpty) return null;
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return null;
  return Color(value);
}

/// Light+dark themes seeded by optional brand hex colours (white-label, FR-28).
/// Falls back to the default Inteshar Sunburst themes when both are unset/invalid.
///
/// [cursiveScript] carries the UX-141 rule into the baked `TextTheme`: with a
/// cursive locale active every letter-spacing in the theme is dropped, because
/// tracking breaks the joins of Arabic. It mirrors [IntesharType.cursiveScript],
/// which does the same for the styles widgets build directly.
({ThemeData light, ThemeData dark}) buildBrandThemes({
  String? primaryHex,
  String? secondaryHex,
  bool cursiveScript = false,
}) {
  final primary = parseHexColor(primaryHex);
  final secondary = parseHexColor(secondaryHex);
  if (primary == null && secondary == null) {
    return cursiveScript
        ? (light: _intesharLightThemeCursive, dark: _intesharDarkThemeCursive)
        : (light: intesharLightTheme, dark: intesharDarkTheme);
  }
  return (
    light: _build(Brightness.light,
        brandPrimary: primary, brandSecondary: secondary, cursive: cursiveScript),
    dark: _build(Brightness.dark,
        brandPrimary: primary, brandSecondary: secondary, cursive: cursiveScript),
  );
}
