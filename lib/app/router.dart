import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/auth/presentation/login_page.dart';
import 'package:inteshar/features/auth/presentation/splash_page.dart';
import 'package:inteshar/features/diagnostics/presentation/health_page.dart';
import 'package:inteshar/features/entities/presentation/entity_tree_page.dart';
import 'package:inteshar/features/inventory/presentation/batch_add_page.dart';
import 'package:inteshar/features/inventory/presentation/definitions_page.dart';
import 'package:inteshar/features/inventory/presentation/inventory_page.dart';
import 'package:inteshar/features/pos/presentation/pos_home_page.dart';
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
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/diagnostics', builder: (_, _) => const HealthPage()),

      // HQ routes
      GoRoute(
        path: '/hq/home',
        builder: (_, _) => const AppScaffold(role: 'INTESHAR'),
      ),
      GoRoute(path: '/hq/entities', builder: (_, _) => const EntityTreePage()),
      GoRoute(path: '/hq/inventory', builder: (_, _) => const InventoryPage()),
      GoRoute(path: '/hq/definitions', builder: (_, _) => const DefinitionsPage()),
      GoRoute(path: '/hq/batch', builder: (_, _) => const BatchAddPage()),
      GoRoute(path: '/hq/transactions', builder: (_, _) => const TransactionsPage()),
      GoRoute(path: '/hq/transactions/new', builder: (_, _) => const NewTransactionPage()),

      // Agent1 routes
      GoRoute(
        path: '/agent1/home',
        builder: (_, _) => const AppScaffold(role: 'AGENT1'),
      ),
      GoRoute(path: '/agent1/entities', builder: (_, _) => const EntityTreePage()),
      GoRoute(path: '/agent1/inventory', builder: (_, _) => const InventoryPage()),
      GoRoute(path: '/agent1/transactions', builder: (_, _) => const TransactionsPage()),
      GoRoute(path: '/agent1/transactions/new', builder: (_, _) => const NewTransactionPage()),

      // Agent2 routes
      GoRoute(
        path: '/agent2/home',
        builder: (_, _) => const AppScaffold(role: 'AGENT2'),
      ),
      GoRoute(path: '/agent2/entities', builder: (_, _) => const EntityTreePage()),
      GoRoute(path: '/agent2/inventory', builder: (_, _) => const InventoryPage()),
      GoRoute(path: '/agent2/transactions', builder: (_, _) => const TransactionsPage()),
      GoRoute(path: '/agent2/transactions/new', builder: (_, _) => const NewTransactionPage()),

      // Store routes
      GoRoute(
        path: '/store/home',
        builder: (_, _) => const AppScaffold(role: 'STORE'),
      ),
      GoRoute(path: '/store/inventory', builder: (_, _) => const InventoryPage()),
      GoRoute(path: '/store/transactions', builder: (_, _) => const TransactionsPage()),
      GoRoute(path: '/store/transactions/new', builder: (_, _) => const NewTransactionPage()),

      // POS
      GoRoute(path: '/pos/home', builder: (_, _) => const PosHomePage()),
    ],
  );
});

/// Bridges Riverpod auth state changes into a [Listenable] that GoRouter
/// can use as [refreshListenable].
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}
