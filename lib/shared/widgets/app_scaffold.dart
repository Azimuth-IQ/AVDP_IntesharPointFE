import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/core/printing/printer_registry.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/features/entities/presentation/entity_tree_page.dart';
import 'package:inteshar/features/inventory/presentation/batch_add_page.dart';
import 'package:inteshar/features/inventory/presentation/definitions_page.dart';
import 'package:inteshar/features/inventory/presentation/inventory_page.dart';
import 'package:inteshar/features/transactions/presentation/transactions_page.dart';
import 'package:inteshar/l10n/app_localizations.dart';

class AppScaffold extends ConsumerStatefulWidget {
  final String role;
  const AppScaffold({super.key, required this.role});

  @override
  ConsumerState<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends ConsumerState<AppScaffold> {
  int _index = 0;

  List<_NavItem> _buildItems(AppLocalizations l) {
    switch (widget.role) {
      case 'INTESHAR':
        return [
          _NavItem(Icons.dashboard, l.navDashboard, const _DashboardPage()),
          _NavItem(Icons.account_tree, l.navHierarchy, const EntityTreePage()),
          _NavItem(Icons.inventory_2, l.navCatalog, const DefinitionsPage()),
          _NavItem(Icons.warehouse, l.navInventory, const InventoryPage()),
          _NavItem(Icons.upload_file, l.navBatchAdd, const BatchAddPage()),
          _NavItem(Icons.swap_horiz, l.navTransactions, const TransactionsPage()),
        ];
      case 'AGENT1':
      case 'AGENT2':
        return [
          _NavItem(Icons.dashboard, l.navDashboard, const _DashboardPage()),
          _NavItem(Icons.account_tree, l.navChildren, const EntityTreePage()),
          _NavItem(Icons.warehouse, l.navInventory, const InventoryPage()),
          _NavItem(Icons.swap_horiz, l.navTransactions, const TransactionsPage()),
        ];
      case 'STORE':
        return [
          _NavItem(Icons.dashboard, l.navDashboard, const _DashboardPage()),
          _NavItem(Icons.warehouse, l.navInventory, const InventoryPage()),
          _NavItem(Icons.swap_horiz, l.navTransactions, const TransactionsPage()),
          _NavItem(Icons.point_of_sale, l.navPos, const _PosLauncherPage()),
        ];
      default:
        return [_NavItem(Icons.dashboard, l.navDashboard, const _DashboardPage())];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final items = _buildItems(l);
    final clampedIndex = _index.clamp(0, items.length - 1);
    final page = items[clampedIndex].page;
    final wide = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onLongPress: () => context.go('/diagnostics'), child: Text(l.appTitle)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.signOut,
            onPressed: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      drawer: _AboutDrawer(l: l),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: clampedIndex,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: items.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.label))).toList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ],
            )
          : page,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: clampedIndex,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: items.map((e) => NavigationDestination(icon: Icon(e.icon), label: e.label)).toList(),
            ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Widget page;
  const _NavItem(this.icon, this.label, this.page);
}

class _DashboardPage extends ConsumerWidget {
  const _DashboardPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    final entity = (auth is AuthAuthenticated) ? auth.entity : null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back!', style: Theme.of(context).textTheme.headlineSmall),
          if (entity != null) ...[
            const SizedBox(height: 8),
            Text(entity.meta.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            if (entity.meta.slogan.isNotEmpty) ...[const SizedBox(height: 4), Text(entity.meta.slogan, style: Theme.of(context).textTheme.bodyMedium)],
            const SizedBox(height: 4),
            Text(entity.type.label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ],
      ),
    );
  }
}

class _PosLauncherPage extends StatelessWidget {
  const _PosLauncherPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.icon(onPressed: () => context.go('/pos/home'), icon: const Icon(Icons.point_of_sale), label: const Text('Open POS')),
    );
  }
}

class _AboutDrawer extends StatelessWidget {
  final AppLocalizations l;
  const _AboutDrawer({required this.l});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: scheme.primary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(l.appTitle, style: TextStyle(color: scheme.onPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(l.aboutVersion, style: TextStyle(color: scheme.onPrimary.withAlpha(180))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(l.aboutSupportedPrinters, style: Theme.of(context).textTheme.titleSmall),
          ),
          ...supportedPrinterModels.map(
            (m) => ListTile(
              dense: true,
              leading: const Icon(Icons.print, size: 18),
              title: Text(m.name),
              subtitle: Text('${m.paperMm} mm ESC/POS'),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(l.aboutPrinterNote, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
