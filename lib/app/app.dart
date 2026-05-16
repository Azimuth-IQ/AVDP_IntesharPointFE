import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class IntesharApp extends ConsumerWidget {
  const IntesharApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Inteshar Point',
      debugShowCheckedModeBanner: false,
      theme: intesharLightTheme,
      darkTheme: intesharDarkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate, GlobalWidgetsLocalizations.delegate],
    );
  }
}
