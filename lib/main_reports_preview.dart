// TEMPORARY entrypoint for reviewing the Reports visuals without a login.
// Run: flutter build web -t lib/main_reports_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/reports/presentation/reports_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();
  @override
  Widget build(BuildContext context) {
    final themes = buildBrandThemes();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      locale: const Locale('ar'),
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ReportsPreviewPage(),
    );
  }
}
