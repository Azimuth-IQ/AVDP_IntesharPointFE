import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/auth/data/auth_repository.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

sealed class AuthState {}

class AuthLoading extends AuthState {}

class AuthUnauthenticated extends AuthState {}

class AuthAuthenticated extends AuthState {
  final Entity entity;
  final UserRole role;
  final bool isPosUser;
  final Set<Capability> capabilities;

  AuthAuthenticated({required this.entity, required this.role, this.isPosUser = false, this.capabilities = const {}});

  String get homeRoute {
    if (isPosUser) return '/pos/home';
    return entity.type.homeRoute;
  }

  /// Whether the signed-in user may perform an action requiring any of [required].
  /// ADMIN role and the AGENT_ADMIN capability satisfy everything. UI gating only —
  /// the backend re-checks every protected request.
  bool can(Set<Capability> required) => hasAnyCapability(role, capabilities, required);
}

final authStateProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    debugPrint('[AUTH] build() started');
    final token = await sessionStorage.getToken();
    debugPrint('[AUTH] token=${token != null ? "found" : "null"}');
    if (token == null) return AuthUnauthenticated();

    final entityId = await sessionStorage.getCurrentEntityId();
    final entityType = await sessionStorage.getCurrentEntityType();
    debugPrint('[AUTH] entityId=$entityId entityType=$entityType');
    if (entityId == null || entityType == null) {
      await sessionStorage.clear();
      return AuthUnauthenticated();
    }

    final baseUrl = await sessionStorage.getBaseUrl();
    debugPrint('[AUTH] baseUrl=$baseUrl');

    try {
      debugPrint('[AUTH] fetching entity...');
      final api = ref.read(apiClientProvider);
      final entityRepo = EntityRepository(api);
      final entity = await entityRepo.read(entityId);
      debugPrint('[AUTH] entity fetched: ${entity.id}');
      final phone = await sessionStorage.getCurrentPhone() ?? '';
      final user = entity.users.where((u) => u.phone == phone).firstOrNull;
      final role = user?.role ?? UserRole.ADMIN;
      final isPosUser = role == UserRole.USER && entity.type == EntityType.STORE;
      return AuthAuthenticated(entity: entity, role: role, isPosUser: isPosUser, capabilities: user?.capabilities ?? const {});
    } catch (e) {
      debugPrint('[AUTH] error: $e');
      await sessionStorage.clear();
      return AuthUnauthenticated();
    }
  }

  Future<void> login(String phone, String password) async {
    state = const AsyncValue.loading();
    try {
      final api = ref.read(apiClientProvider);
      final authRepo = AuthRepository(api);
      final token = await authRepo.login(phone, password);
      await sessionStorage.setToken(token);
      await sessionStorage.setCurrentPhone(phone);

      final entityRepo = EntityRepository(api);
      final entities = await entityRepo.readAll();
      Entity? found;
      UserRole foundRole = UserRole.USER;
      Set<Capability> foundCaps = const {};
      for (final e in entities) {
        final user = e.users.where((u) => u.phone == phone).firstOrNull;
        if (user != null) {
          found = e;
          foundRole = user.role;
          foundCaps = user.capabilities;
          break;
        }
      }

      if (found == null) {
        throw const ApiException('Could not find entity for this user');
      }

      await sessionStorage.setCurrentEntityId(found.id);
      await sessionStorage.setCurrentEntityType(found.type.name);

      final isPosUser = foundRole == UserRole.USER && found.type == EntityType.STORE;
      state = AsyncValue.data(AuthAuthenticated(entity: found, role: foundRole, isPosUser: isPosUser, capabilities: foundCaps));
    } on ApiException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    await sessionStorage.clear();
    state = AsyncValue.data(AuthUnauthenticated());
  }

  AuthAuthenticated? get current {
    final v = state.valueOrNull;
    return v is AuthAuthenticated ? v : null;
  }
}
