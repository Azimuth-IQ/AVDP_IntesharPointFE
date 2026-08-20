import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/app/theme_provider.dart';
import 'package:inteshar/core/api/session_expiry_gate.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/core/push/push_listener.dart';
import 'package:inteshar/core/utils/formatters.dart';
import 'package:inteshar/features/update/presentation/update_gate.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class IntesharApp extends ConsumerWidget {
  const IntesharApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeControllerProvider);
    final brandThemes = ref.watch(brandThemeProvider);
    // UX-57: the money formatter is a context-free static with ~53 call sites,
    // so the currency unit (د.ع vs IQD) follows the locale from here. Same value
    // the app is about to rebuild with — the two can never disagree for a frame.
    Formatters.languageCode = locale.languageCode;
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
      builder: (context, child) => PushListener(
        child: UpdateGate(
          child: SessionExpiryGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
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
