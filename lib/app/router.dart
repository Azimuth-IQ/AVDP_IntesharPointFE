import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/auth/presentation/login_page.dart';
import 'package:inteshar/features/auth/presentation/splash_page.dart';
import 'package:inteshar/features/dashboard/presentation/dashboard_page.dart';
import 'package:inteshar/features/diagnostics/presentation/health_page.dart';
import 'package:inteshar/features/entities/presentation/entity_tree_page.dart';
import 'package:inteshar/features/inventory/presentation/batch_add_page.dart';
import 'package:inteshar/features/inventory/presentation/definitions_page.dart';
import 'package:inteshar/features/inventory/presentation/voucher_templates_page.dart';
import 'package:inteshar/features/inventory/presentation/inventory_page.dart';
import 'package:inteshar/features/inventory/presentation/child_inventory_page.dart';
import 'package:inteshar/features/agents/presentation/main_agents_page.dart';
import 'package:inteshar/features/agents/presentation/sub_agents_page.dart';
import 'package:inteshar/features/companies/presentation/companies_page.dart';
import 'package:inteshar/features/pos/presentation/pos_home_page.dart';
import 'package:inteshar/features/pricing/presentation/pricing_page.dart';
import 'package:inteshar/features/stores/presentation/stores_page.dart';
import 'package:inteshar/features/system_activity/presentation/system_activity_page.dart';
import 'package:inteshar/features/transactions/presentation/new_transaction_page.dart';
import 'package:inteshar/features/transactions/presentation/transactions_page.dart';
import 'package:inteshar/shared/widgets/app_scaffold.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Watch auth state so the router rebuilds on auth changes.
  final authAsync = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthStateListenable(ref),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final isPublic = loc == '/splash' || loc == '/login' || loc == '/diagnostics';

      // While loading, stay on splash.
      if (authAsync.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final authState = authAsync.valueOrNull;

      if (authState == null || authState is AuthUnauthenticated) {
        final isLoginPage = loc == '/login' || loc == '/diagnostics';
        return isLoginPage ? null : '/login';
      }

      if (authState is AuthAuthenticated) {
        if (isPublic) return authState.homeRoute;

        // Role guard: confine each session to its own route prefix. If the
        // matched location lives under a different role's prefix than the
        // signed-in session's home, bounce to the session home. homeRoute is
        // entity.type.homeRoute for HQ/agents/store and /pos/home for POS
        // users, so POS sessions are correctly kept inside /pos.
        final locPrefix = _rolePrefixOf(loc);
        final homePrefix = _rolePrefixOf(authState.homeRoute);
        if (locPrefix != null && homePrefix != null && locPrefix != homePrefix) {
          return authState.homeRoute;
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/diagnostics', builder: (_, _) => const HealthPage()),

      // POS sits outside the shell — full screen on the device.
      GoRoute(path: '/pos/home', builder: (_, _) => const PosHomePage()),

      // Detail routes (pushed on top, outside the shell) — keep their own
      // back-aware AppBars.
      GoRoute(path: '/hq/transactions/new', builder: (_, _) => const NewTransactionPage()),
      GoRoute(path: '/agent1/transactions/new', builder: (_, _) => const NewTransactionPage()),
      GoRoute(path: '/agent2/transactions/new', builder: (_, _) => const NewTransactionPage()),
      GoRoute(path: '/store/transactions/new', builder: (_, _) => const NewTransactionPage()),

      // Child-inventory drill-in (read-only). HQ + Distributor browse a
      // downstream entity's stock; pushed outside the shell with its own AppBar.
      GoRoute(
        path: '/hq/entities/:id/inventory',
        builder: (_, s) => ChildInventoryPage(
          entityId: s.pathParameters['id']!,
          entityName: s.uri.queryParameters['name'] ?? '',
        ),
      ),
      GoRoute(
        path: '/agent2/entities/:id/inventory',
        builder: (_, s) => ChildInventoryPage(
          entityId: s.pathParameters['id']!,
          entityName: s.uri.queryParameters['name'] ?? '',
        ),
      ),

      // All signed-in sections share the responsive [AppShell] (nav + URL).
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // HQ — the home/landing IS the System Activity oversight screen.
          GoRoute(path: '/hq/home', builder: (_, _) => const SystemActivityPage()),
          GoRoute(path: '/hq/main-agents', builder: (_, _) => const MainAgentsPage()),
          GoRoute(path: '/hq/sub-agents', builder: (_, _) => const SubAgentsPage()),
          GoRoute(path: '/hq/companies', builder: (_, _) => const CompaniesPage()),
          GoRoute(path: '/hq/stores', builder: (_, _) => const StoresPage()),
          GoRoute(path: '/hq/entities', builder: (_, _) => const EntityTreePage()),
          GoRoute(path: '/hq/definitions', builder: (_, _) => const DefinitionsPage()),
          GoRoute(path: '/hq/templates', builder: (_, _) => const VoucherTemplatesPage()),
          GoRoute(path: '/hq/inventory', builder: (_, _) => const InventoryPage()),
          GoRoute(path: '/hq/batch', builder: (_, _) => const BatchAddPage()),
          GoRoute(path: '/hq/transactions', builder: (_, _) => const TransactionsPage()),

          // Agent1
          GoRoute(path: '/agent1/home', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/agent1/entities', builder: (_, _) => const EntityTreePage()),
          GoRoute(path: '/agent1/inventory', builder: (_, _) => const InventoryPage()),
          GoRoute(path: '/agent1/transactions', builder: (_, _) => const TransactionsPage()),
          GoRoute(path: '/agent1/pricing', builder: (_, _) => const PricingPage()),
          GoRoute(path: '/agent1/stores', builder: (_, _) => const StoresPage()),

          // Agent2
          GoRoute(path: '/agent2/home', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/agent2/entities', builder: (_, _) => const EntityTreePage()),
          GoRoute(path: '/agent2/inventory', builder: (_, _) => const InventoryPage()),
          GoRoute(path: '/agent2/transactions', builder: (_, _) => const TransactionsPage()),
          GoRoute(path: '/agent2/stores', builder: (_, _) => const StoresPage()),

          // Store
          GoRoute(path: '/store/home', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/store/inventory', builder: (_, _) => const InventoryPage()),
          GoRoute(path: '/store/transactions', builder: (_, _) => const TransactionsPage()),
        ],
      ),
    ],
  );
});

/// The role route prefix a [location] belongs to, or `null` if it is not a
/// role-scoped route (e.g. `/splash`, `/login`, `/diagnostics`). Used by the
/// router redirect to keep a signed-in session inside its own section.
String? _rolePrefixOf(String location) {
  const prefixes = ['/hq', '/agent1', '/agent2', '/store', '/pos'];
  for (final p in prefixes) {
    if (location == p || location.startsWith('$p/')) return p;
  }
  return null;
}

/// Bridges Riverpod auth state changes into a [Listenable] that GoRouter
/// can use as [refreshListenable].
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}
