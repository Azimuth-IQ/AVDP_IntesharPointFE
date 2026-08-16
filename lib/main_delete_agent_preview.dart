// TEMPORARY entrypoint for reviewing the delete-agent sheet without a login.
// Run: flutter run -d chrome -t lib/main_delete_agent_preview.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/entities/domain/entity_dependents.dart';
import 'package:inteshar/features/entities/presentation/delete_agent_sheet.dart';
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

/// The three states worth looking at, side by side: blocked, part-way through,
/// and cleared.
final _blocked = EntityDependents(
  id: 'agent1-baghdad',
  name: 'وكيل بغداد الرئيسي',
  type: 'AGENT1',
  subAgentCount: 3,
  storeCount: 4,
  deletable: false,
  subAgents: const [
    DependentSubAgent(
        id: 'a2-1', name: 'وكيل الرصافة', governorate: 'BAGHDAD', storeCount: 2),
    DependentSubAgent(
        id: 'a2-2', name: 'وكيل الكرخ', governorate: 'BAGHDAD', storeCount: 1),
    DependentSubAgent(
        id: 'a2-3', name: 'وكيل بعقوبة', governorate: 'DIYALA', storeCount: 0),
  ],
  stores: const [
    DependentStore(
        id: 's1',
        name: 'موبايلات الرصافة',
        governorate: 'BAGHDAD',
        hostId: 'a2-1',
        hostName: 'وكيل الرصافة',
        operatorPhone: '07813300001'),
    DependentStore(
        id: 's2',
        name: 'مركز النور للاتصالات',
        governorate: 'BAGHDAD',
        hostId: 'a2-1',
        hostName: 'وكيل الرصافة',
        operatorPhone: '07813300002'),
    DependentStore(
        id: 's3',
        name: 'موبايل المنصور',
        governorate: 'BAGHDAD',
        hostId: 'a2-2',
        hostName: 'وكيل الكرخ',
        operatorPhone: '07813300003'),
    DependentStore(
        id: 's4',
        name: 'معرض انتشار المركزي',
        governorate: 'BAGHDAD',
        hostId: 'agent1-baghdad',
        hostName: 'وكيل بغداد الرئيسي',
        operatorPhone: '07813300022'),
  ],
);

const _cleared = EntityDependents(
  id: 'agent1-baghdad',
  name: 'وكيل بغداد الرئيسي',
  type: 'AGENT1',
  deletable: true,
);

class _PreviewPage extends StatelessWidget {
  const _PreviewPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDEEF1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _panel(context, 'Blocked — 3 sub-agents, 4 shops', _blocked, const {}),
            _panel(context, 'Deleting one shop', _blocked, const {'s2'}),
            _panel(context, 'Cleared — unlocked', _cleared, const {}),
          ],
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, String label, EntityDependents deps,
      Set<String> busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        Container(
          width: 460,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: DeleteAgentSheetBody(
            entityName: deps.name,
            entityId: deps.id,
            dependents: deps,
            loading: false,
            error: null,
            busyIds: busy,
            onRetry: () {},
            onDeleteStore: (_) {},
            onDeleteSubAgent: (_) {},
            onDeleteSelf: () {},
          ),
        ),
      ],
    );
  }
}
