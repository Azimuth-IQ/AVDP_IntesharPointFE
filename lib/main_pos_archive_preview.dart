// TEMPORARY entrypoint for reviewing the POS archive visuals without a login.
// Run: flutter build web -t lib/main_pos_archive_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/pos_admin/domain/archived_pos.dart';
import 'package:inteshar/features/pos_admin/presentation/pos_archive.dart';
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
      home: const _PreviewPage(),
    );
  }
}

const _rows = [
  ArchivedPos(
    id: 's1',
    name: 'موبايلات الرصافة',
    governorate: 'BAGHDAD',
    hostName: 'وكيل الرصافة',
    operatorPhone: '07813300001',
    daysRemaining: 28,
  ),
  ArchivedPos(
    id: 's2',
    name: 'مركز النور للاتصالات',
    governorate: 'BAGHDAD',
    hostName: 'وكيل الرصافة',
    operatorPhone: '07813300002',
    daysRemaining: 3,
  ),
  ArchivedPos(
    id: 's3',
    name: 'موبايل المنصور',
    governorate: 'BAGHDAD',
    hostName: 'وكيل الكرخ',
    operatorPhone: '07813300003',
    daysRemaining: 0,
    purgeable: true,
  ),
];

class _PreviewPage extends StatelessWidget {
  const _PreviewPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEEF1),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(IntesharSpacing.xl),
          child: SizedBox(
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Archive — waiting, nearly due, and ready',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: IntesharSpacing.md),
                PosArchiveList(
                  rows: _rows,
                  busyIds: const {},
                  onDownload: (_) {},
                  onPurge: (_) {},
                  onRestore: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
