import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/app/theme_provider.dart';
import 'package:inteshar/core/locale/locale_controller.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class IntesharApp extends ConsumerWidget {
  const IntesharApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeControllerProvider);
    final brandThemes = ref.watch(brandThemeProvider);
    return MaterialApp.router(
      title: 'Inteshar Point',
      debugShowCheckedModeBanner: false,
      theme: brandThemes.light,
      darkTheme: brandThemes.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
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
