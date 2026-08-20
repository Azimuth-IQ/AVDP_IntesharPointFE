import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  static const dust       = Color(0xFFFFEAB8); // soft gold wash (tags, primaryContainer)

  // Dark surface stack
  static const inkPaper   = Color(0xFF121110); // dark page bg — brand warm charcoal
  static const inkCard    = Color(0xFF1C1A18); // dark elevated
  static const inkSunk    = Color(0xFF262320); // dark recessed
  static const bone       = Color(0xFFF5F2EA); // dark mode "ink" (text)
  static const boneSoft   = Color(0xFFB3B0A6);
  static const hairlineDark = Color(0x2EF5F2EA);

  static const saffronOnDark = Color(0xFFECBC3F); // brand gold lifted for legibility on charcoal
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

class IntesharSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
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

  /// Soft brand wash for chips/containers//tag backgrounds.
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
      brandWash: isDark ? _darken(brand, 0.72) : _lighten(brand, 0.86),
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

/// Static typography helpers — every named style draws from Codec Pro, with
/// weight and tracking doing the work that two competing families used to.
/// `mono` stays on JetBrainsMono because Codec Pro is proportional and breaks
/// alignment on voucher serials, PINs, and printer MAC addresses.
class IntesharType {
  /// Heavy display — page wordmarks, hero numerals on ledger cards.
  static TextStyle display(double size, {Color? color, FontWeight w = FontWeight.w800}) => TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: w,
        color: color,
        height: 1.05,
        letterSpacing: -0.6,
      );

  /// Editorial mid-weight — what was Fraunces. Reads as a "title with voice".
  /// Italic + News weight still gives the printed-broadsheet flavor.
  static TextStyle serif(double size,
          {Color? color, FontWeight w = FontWeight.w500, double? height, FontStyle? style, double? letterSpacing}) =>
      TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: w,
        fontStyle: style,
        color: color,
        height: height ?? 1.2,
        letterSpacing: letterSpacing ?? -0.2,
      );

  /// Body sans — Regular by default.
  static TextStyle sans(double size,
          {Color? color, FontWeight w = FontWeight.w400, double? height, double? letterSpacing}) =>
      TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: w,
        color: color,
        height: height ?? 1.35,
        letterSpacing: letterSpacing,
      );

  /// True monospace — reserved for serials, PINs, MAC addresses, hex dumps.
  static TextStyle mono(double size, {Color? color, FontWeight w = FontWeight.w500, double? letterSpacing}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: w, color: color, letterSpacing: letterSpacing ?? 0);

  /// Tracking-wide editorial overline. Reads like "DEPARTMENT — SECTION".
  static TextStyle overline({Color? color, double size = 11}) => TextStyle(
        fontFamily: _kCodec,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 2.2,
        height: 1,
      );
}

ThemeData _build(Brightness b, {Color? brandPrimary, Color? brandSecondary}) {
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
        letterSpacing: tracking,
      );

  final textTheme = TextTheme(
    displayLarge:   codec(size: 57, w: FontWeight.w900, c: onPaper, height: 1.0,  tracking: -1.6),
    displayMedium:  codec(size: 45, w: FontWeight.w900, c: onPaper, height: 1.05, tracking: -1.1),
    displaySmall:   codec(size: 36, w: FontWeight.w800, c: onPaper, height: 1.05, tracking: -0.7),
    headlineLarge:  codec(size: 32, w: FontWeight.w800, c: onPaper, height: 1.1,  tracking: -0.5),
    headlineMedium: codec(size: 28, w: FontWeight.w700, c: onPaper, height: 1.15, tracking: -0.4),
    headlineSmall:  codec(size: 24, w: FontWeight.w700, c: onPaper, height: 1.2,  tracking: -0.3),
    titleLarge:     codec(size: 20, w: FontWeight.w700, c: onPaper, height: 1.25, tracking: -0.2),
    titleMedium:    codec(size: 16, w: FontWeight.w600, c: onPaper, height: 1.3,  tracking: 0.0),
    titleSmall:     codec(size: 14, w: FontWeight.w600, c: onPaper, height: 1.3,  tracking: 0.1),
    bodyLarge:      codec(size: 16, w: FontWeight.w400, c: onPaper, height: 1.5),
    bodyMedium:     codec(size: 14, w: FontWeight.w400, c: onPaper, height: 1.45),
    bodySmall:      codec(size: 12.5, w: FontWeight.w400, c: onPaperSoft, height: 1.4),
    labelLarge:     codec(size: 14, w: FontWeight.w600, c: onPaper,     tracking: 0.4),
    labelMedium:    codec(size: 12, w: FontWeight.w600, c: onPaperSoft, tracking: 0.6),
    labelSmall:     codec(size: 11, w: FontWeight.w700, c: onPaperSoft, tracking: 1.2),
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
        isDark: isDark,
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
      titleTextStyle: codec(size: 22, w: FontWeight.w700, c: onPaper, tracking: -0.3),
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
      labelStyle: codec(size: 11, w: FontWeight.w700, c: onPaper, tracking: 1.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: codec(size: 14, w: FontWeight.w400, c: onPaperSoft.withValues(alpha: 0.55)),
      labelStyle: codec(size: 13, w: FontWeight.w500, c: onPaperSoft),
      floatingLabelStyle: codec(size: 13, w: FontWeight.w600, c: brandInk),
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
        textStyle: codec(size: 14, w: FontWeight.w700, tracking: 0.4),
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
        textStyle: codec(size: 14, w: FontWeight.w800, tracking: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onPaper,
        side: BorderSide(color: outline, width: 1),
        textStyle: codec(size: 14, w: FontWeight.w600, tracking: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brandInk,
        textStyle: codec(size: 13, w: FontWeight.w600, tracking: 0.3),
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
      titleTextStyle: codec(size: 14.5, w: FontWeight.w600, c: onPaper),
      subtitleTextStyle: codec(size: 12.5, w: FontWeight.w400, c: onPaperSoft),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: onPaper,
      contentTextStyle: codec(size: 14, w: FontWeight.w500, c: paper),
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
      titleTextStyle: codec(size: 22, w: FontWeight.w700, c: onPaper, tracking: -0.3),
      contentTextStyle: codec(size: 14, w: FontWeight.w400, c: onPaper, height: 1.45),
    ),
    // UX-145: the selected item used to be the LEAST readable thing on the bar —
    // raw gold on white is 2.05:1 against 6.25:1 for the unselected grey. It now
    // uses the measured brand ink, and carries a weight step as well as a colour
    // step so selection isn't signalled by hue alone (the tint pill is ~1.2:1
    // and can never carry it on its own without wrecking the light style).
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: saffron.withValues(alpha: 0.16),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? brandOnSurface : onPaperSoft, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return codec(
          size: 11,
          w: selected ? FontWeight.w800 : FontWeight.w600,
          tracking: 0.5,
          c: selected ? brandOnSurface : onPaperSoft,
        );
      }),
      height: 64,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      indicatorColor: saffron.withValues(alpha: 0.16),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
      selectedIconTheme: IconThemeData(color: brandOnSurface, size: 22),
      unselectedIconTheme: IconThemeData(color: onPaperSoft, size: 22),
      selectedLabelTextStyle: codec(size: 11, w: FontWeight.w800, c: brandOnSurface, tracking: 0.4),
      unselectedLabelTextStyle: codec(size: 11, w: FontWeight.w500, c: onPaperSoft, tracking: 0.4),
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
({ThemeData light, ThemeData dark}) buildBrandThemes({String? primaryHex, String? secondaryHex}) {
  final primary = parseHexColor(primaryHex);
  final secondary = parseHexColor(secondaryHex);
  if (primary == null && secondary == null) {
    return (light: intesharLightTheme, dark: intesharDarkTheme);
  }
  return (
    light: _build(Brightness.light, brandPrimary: primary, brandSecondary: secondary),
    dark: _build(Brightness.dark, brandPrimary: primary, brandSecondary: secondary),
  );
}
