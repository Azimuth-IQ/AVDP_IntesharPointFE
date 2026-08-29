// TEMPORARY entrypoint for reviewing the user-register sheet without a login.
// Run: flutter build web -t lib/main_manage_users_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/manage_users_sheet.dart';
import 'package:inteshar/l10n/app_localizations.dart';

void main() => runApp(const _PreviewApp());

const _entity = Entity(
  id: 'a2-rusafa',
  meta: EntityMeta(name: 'وكيل الرصافة'),
  type: EntityType.AGENT2,
  users: [
    EntityUser(id: 'u1', phone: '07700000001', role: UserRole.ADMIN),
    EntityUser(id: 'u2', phone: '07700000002', role: UserRole.ADMIN),
    EntityUser(id: 'u3', phone: '07700000003', role: UserRole.ADMIN),
  ],
);

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
        body: Center(
          child: SizedBox(
            width: 520,
            child: Card(
              margin: const EdgeInsets.all(IntesharSpacing.xl),
              child: ManageUsersSheet(
                entity: _entity,
                onSave: (_) async {},
                onResetPassword: (_, _) async {},
                onResetTotp: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}
