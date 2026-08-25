import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/app/theme_provider.dart';
import 'package:inteshar/core/api/session_expiry_gate.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/core/push/push_listener.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/update/presentation/update_gate.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/offline_banner.dart';

class IntesharApp extends ConsumerWidget {
  const IntesharApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // UX-125: JetBrains Mono is BUNDLED (assets/fonts/mono/, see pubspec), so
    // google_fonts must never reach the network for it — a POS handheld on a
    // poor link would otherwise keep rendering serials/PINs proportional until a
    // download landed. With fetching off, google_fonts resolves the bundled
    // faces from the asset manifest; a face that is genuinely missing now logs a
    // loud "unable to load font" instead of silently degrading forever. Set here
    // (not in main) so preview/test entry points get the same policy.
    GoogleFonts.config.allowRuntimeFetching = false;
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeControllerProvider);
    final brandThemes = ref.watch(brandThemeProvider);
    // UX-57: the money formatter is a context-free static with ~53 call sites,
    // so the currency unit (د.ع vs IQD) follows the locale from here. Same value
    // the app is about to rebuild with — the two can never disagree for a frame.
    Formatters.languageCode = locale.languageCode;
    // UX-141: same idiom, same reason — letter-spacing is a Latin device, and
    // applying it to Arabic (the primary locale) pulls the joins of a cursive
    // script apart. Setting the flag here corrects all 25 `IntesharType.overline`
    // call sites, and every other tracked style widgets build directly, without
    // editing any of them. The baked `TextTheme` is handled by
    // `brandThemeProvider`, which watches the same locale.
    IntesharType.cursiveScript =
        kCursiveLanguageCodes.contains(locale.languageCode);
    return MaterialApp.router(
      title: 'Inteshar',
      debugShowCheckedModeBanner: false,
      theme: brandThemes.light,
      darkTheme: brandThemes.dark,
      // B-078: lock to the polished light style. Much of the UI paints fixed light
      // inks (IntesharColors.ink/lichen/…), so honouring the OS dark setting left
      // low-contrast text on charcoal. Light is the team's intended look.
      themeMode: ThemeMode.light,
      routerConfig: router,
      // App-wide update gate: a mandatory update replaces the whole UI; an
      // optional one surfaces a dismissible sheet. No-op off Android.
      //
      // UX-79: the offline strip is a gate here, NOT a banner inside AppShell —
      // `/pos/home` (the till) is routed outside the shell, and that is exactly
      // the screen a dead link costs money on.
      builder: (context, child) {
        // UX-113: app-wide text-scaling policy — pass the OS setting through up
        // to 1.3×, clamp above that.
        //
        // The decision, written down so it is not re-litigated per screen:
        // Android lets the user go to 2.0× and our shopkeepers DO raise it, but
        // the layout is full of hand-tuned fixed extents (the POS product grid's
        // `mainAxisExtent: 118`, pill and tile heights) that overflow well before
        // 2.0×. The two honest options were "clamp" or "leave it and fix every
        // screen"; the latter is a large per-screen job and until it is done the
        // failure mode is a RenderFlex overflow on the till — the one screen
        // where a broken layout costs a sale.
        //
        // 1.3× is a measured-conservative cap, not a proven ceiling: the first
        // overflow we know of shows up around 1.8× (`pos_home_page.dart:667`,
        // `mainAxisExtent: 118`), and the rest of the fixed extents have not been
        // measured, so this leaves headroom. Below the cap the accessibility
        // setting is honoured exactly. Clamping to 1.0 was rejected outright —
        // that ignores the setting entirely. The `minScaleFactor` side is
        // deliberately left alone: shrinking never overflows, and a user who
        // chose smaller text should get it.
        //
        // Raise the cap as screens are made scale-safe; it is a stopgap, not a
        // reason to stop fixing them.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3),
          ),
          child: PushListener(
            child: UpdateGate(
              child: ConnectivityGate(
                child: SessionExpiryGate(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
      locale: locale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
    );
  }
}
