import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Inteshar Sunburst" — the brand-led design language.
///
/// Sampled from the Inteshar Store identity: a saturated marigold yellow as
/// the single hero accent, anchored by deep ink black for structure and clean
/// off-white surfaces. Sage stands in for "available/success" because a green
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

  // Accents — `saffron` keeps its name but is now the deeper brand gold.
  static const saffron    = Color(0xFFF5B100); // brand gold — primary fills
  static const saffronDeep = Color(0xFFA8770A); // dark amber — brand-tinted text/icons, pressed/hover
  static const oxblood    = Color(0xFFDC2626); // outgoing / danger — clean red
  static const sage       = Color(0xFF1E9E5A); // available / success — clean green
  static const dust       = Color(0xFFFFEAB8); // soft gold wash (tags, primaryContainer)

  // Dark surface stack
  static const inkPaper   = Color(0xFF0B0B0F); // dark page bg
  static const inkCard    = Color(0xFF16171C); // dark elevated
  static const inkSunk    = Color(0xFF1E1F25); // dark recessed
  static const bone       = Color(0xFFF5F2EA); // dark mode "ink" (text)
  static const boneSoft   = Color(0xFFB3B0A6);
  static const hairlineDark = Color(0x2EF5F2EA);

  static const saffronOnDark = Color(0xFFFCC629); // yellow still pops on dark
  static const sageOnDark   = Color(0xFF7CA690);
  static const oxbloodOnDark = Color(0xFFE0625A);
}

class IntesharRadii {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 18.0;
  static const xl = 24.0;
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
  static const elev1 = [
    BoxShadow(blurRadius: 16, offset: Offset(0, 4), color: Color(0x14000000)),
  ];
  static const elev2 = [
    BoxShadow(blurRadius: 28, offset: Offset(0, 10), color: Color(0x1F000000)),
  ];
  static const ctaShadow = [
    BoxShadow(blurRadius: 22, offset: Offset(0, 8), color: Color(0x33A06A00)),
  ];
}

/// CTA gradient stops (top → middle → bottom) for the glossy yellow pill.
class IntesharGradients {
  static const List<Color> ctaPill = [
    Color(0xFFFFE066), // top highlight
    Color(0xFFFCC629), // brand body
    Color(0xFFE8B419), // bottom shadow lip
  ];
  /// Inner highlight — drawn as a 1px top hairline inside the CTA for shine.
  static const Color ctaInnerHighlight = Color(0xFFFFEDA8);
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
  // on-accent colours track the brand luminance so labels stay legible on any hue.
  final onSaffron   = brandPrimary == null
      ? IntesharColors.ink
      : (ThemeData.estimateBrightnessForColor(brandPrimary) == Brightness.dark ? Colors.white : IntesharColors.ink);
  final onSage      = brandSecondary == null
      ? (isDark ? IntesharColors.ink : Colors.white)
      : (ThemeData.estimateBrightnessForColor(brandSecondary) == Brightness.dark ? Colors.white : IntesharColors.ink);
  final oxblood     = isDark ? IntesharColors.oxbloodOnDark : IntesharColors.oxblood;

  final scheme = ColorScheme(
    brightness: b,
    // Yellow is a "light" hue — onPrimary must be ink in BOTH modes for contrast.
    primary: saffron,
    onPrimary: onSaffron,
    primaryContainer: isDark ? const Color(0xFF3A2C08) : IntesharColors.dust,
    onPrimaryContainer: isDark ? IntesharColors.saffronOnDark : IntesharColors.saffronDeep,

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
      floatingLabelStyle: codec(size: 13, w: FontWeight.w600, c: saffron),
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
        borderSide: BorderSide(color: saffron, width: 1.6),
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
        // Bright marigold demands ink in both modes — white fails WCAG on yellow.
        foregroundColor: IntesharColors.ink,
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
        foregroundColor: saffron,
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
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: saffron.withValues(alpha: 0.16),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? saffron : onPaperSoft, size: 22);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return codec(
          size: 11,
          w: FontWeight.w700,
          tracking: 0.5,
          c: selected ? saffron : onPaperSoft,
        );
      }),
      height: 64,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      indicatorColor: saffron.withValues(alpha: 0.16),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IntesharRadii.sm)),
      selectedIconTheme: IconThemeData(color: saffron, size: 22),
      unselectedIconTheme: IconThemeData(color: onPaperSoft, size: 22),
      selectedLabelTextStyle: codec(size: 11, w: FontWeight.w700, c: saffron, tracking: 0.4),
      unselectedLabelTextStyle: codec(size: 11, w: FontWeight.w500, c: onPaperSoft, tracking: 0.4),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: saffron,
      inactiveTrackColor: outline,
      thumbColor: onPaper,
      overlayColor: saffron.withValues(alpha: 0.12),
      trackHeight: 3,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: saffron,
      linearTrackColor: outline,
      circularTrackColor: outline,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? saffron : onPaperSoft),
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
