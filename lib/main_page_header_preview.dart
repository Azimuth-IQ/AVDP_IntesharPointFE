// TEMPORARY entrypoint for reviewing PageHeader's eyebrow now that
// showEyebrow defaults to true (UX-98). ~20 screens gain a section overline and
// four self-suppress, so this puts the real cases side by side.
// Run: flutter build web -t lib/main_page_header_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

void main() => runApp(const _PreviewApp());

/// (eyebrow, title, subtitle) taken verbatim from real screens.
const _cases = <(String, String, String?)>[
  // Gains an overline — the common case.
  ('الإشراف', 'نشاط النظام', 'مراقبة الحركة عبر المنصة'),
  ('الرصيد', 'التحويلات', 'حوّل الرصيد إلى حساباتك'),
  ('نقاط البيع', 'مستخدمو نقاط البيع', 'إضافة وإدارة نقاط البيع'),
  // Should SELF-SUPPRESS: eyebrow == title.
  ('التقارير', 'التقارير', 'تصدير وتحليل الحركة'),
  ('الكتالوج', 'الكتالوج', 'فئات القسائم والأسعار الافتراضية'),
  // Should self-suppress: eyebrow is a prefix of the title.
  ('قوالب القسائم', 'قوالب القسائم', null),
  // English, to check the rule is language-symmetric.
  ('Oversight', 'System Activity', 'Watch activity across the platform'),
  ('Reports', 'Reports', 'Export and analyse movement'),
];

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
      home: Scaffold(
        backgroundColor: const Color(0xFFEDEEF1),
        body: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: _cases.length,
            separatorBuilder: (_, _) => const Divider(height: 28),
            itemBuilder: (_, i) {
              final (eyebrow, title, subtitle) = _cases[i];
              return PageHeader(
                eyebrow: eyebrow,
                title: title,
                subtitle: subtitle,
              );
            },
          ),
        ),
      ),
    );
  }
}
