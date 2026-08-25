import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/session_invalidation.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:inteshar/features/auth/data/auth_repository.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/branding.dart';
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

  /// B-055: the server-resolved capability set from `GET /entity/me` (own caps ∩
  /// the HQ-set section ceiling on the parent chain, wildcards expanded to an
  /// explicit list). Authoritative when present — see [can].
  final Set<Capability>? effectiveCapabilities;

  /// Resolved white-label brand (Main-Agent logo/colours + HQ slider) for this
  /// session. Empty when unresolved or for HQ.
  final BrandInfo brand;

  AuthAuthenticated({required this.entity, required this.role, this.isPosUser = false, this.capabilities = const {}, this.effectiveCapabilities, this.brand = const BrandInfo()});

  String get homeRoute {
    if (isPosUser) return '/pos/home';
    return entity.type.homeRoute;
  }

  /// Whether the signed-in user may perform an action requiring any of [required].
  /// When the server provided a resolved effective set (B-055) it is authoritative —
  /// the ADMIN-role bypass must not resurrect sections HQ hid for this subtree.
  /// Otherwise the legacy rule applies. UI gating only — the backend re-checks
  /// every protected request.
  bool can(Set<Capability> required) {
    final eff = effectiveCapabilities;
    if (eff != null) {
      if (eff.contains(Capability.AGENT_ADMIN)) return true;
      return required.any(eff.contains);
    }
    return hasAnyCapability(role, capabilities, required);
  }
}

/// Result of a login attempt — drives the login screen's TOTP step.
sealed class LoginOutcome {
  const LoginOutcome();
}

class LoginDone extends LoginOutcome {
  const LoginDone();
}

class LoginEnroll extends LoginOutcome {
  final String otpauthUri;
  final String secret;
  final String? message;
  const LoginEnroll(this.otpauthUri, this.secret, this.message);
}

class LoginNeedsCode extends LoginOutcome {
  final String? message;
  const LoginNeedsCode(this.message);
}

class LoginFailed extends LoginOutcome {
  final String message;
  final int? statusCode;
  const LoginFailed(this.message, [this.statusCode]);
}

class LoginNeedsPasswordChange extends LoginOutcome {
  const LoginNeedsPasswordChange();
}

/// The password was changed, but no session was created (B-011: change-password
/// issues no token). The client must send the user back to sign in.
class LoginPasswordChanged extends LoginOutcome {
  const LoginPasswordChanged();
}

final authStateProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // Rebuild when the API layer signals the session was invalidated (a 401 /
    // SESSION_SUPERSEDED): the token will have been cleared, so we resolve to
    // unauthenticated and the router redirects to /login.
    ref.watch(sessionInvalidationProvider);
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
      // /me also carries the B-055 resolved effectiveCapabilities for this user.
      final entity = await entityRepo.me();
      debugPrint('[AUTH] entity fetched: ${entity.id}');
      final phone = await sessionStorage.getCurrentPhone() ?? '';
      // UX-156: liveUsers — an archived account must never resolve a session.
      final user = entity.liveUsers.where((u) => u.phone == phone).firstOrNull;
      final role = user?.role ?? UserRole.ADMIN;
      // POS-user quota model: a POS is any USER flagged isPos (on any entity). Backward-compatible
      // with the legacy rule (a USER on a STORE) so existing store logins still route to /pos.
      final isPosUser = (user?.isPos ?? false) || (role == UserRole.USER && entity.type == EntityType.STORE);
      final brand = await _loadBrand(api);
      return AuthAuthenticated(entity: entity, role: role, isPosUser: isPosUser, capabilities: user?.capabilities ?? const {}, effectiveCapabilities: entity.effectiveCapabilities, brand: brand);
    } catch (e) {
      debugPrint('[AUTH] error: $e');
      await sessionStorage.clear();
      return AuthUnauthenticated();
    }
  }

  Future<LoginOutcome> login(String phone, String password, {String? totp}) async {
    // Do NOT flip global auth state to loading/unauthenticated here. The router
    // redirects to /splash while auth isLoading (and to /login on unauthenticated),
    // which REMOUNTS the login page and discards its in-progress TOTP step — so the
    // enrollment QR / code screen would never appear (it'd snap back to credentials).
    // Keep the state stable; the login page renders its own spinner via _loading.
    // Only _completeWithToken transitions to authenticated, on real success.
    try {
      final api = ref.read(apiClientProvider);
      final result = await AuthRepository(api).login(phone, password, totp: totp);
      switch (result) {
        case LoginSuccess(:final token):
          return await _completeWithToken(api, phone, token);
        case LoginEnrollResult(:final otpauthUri, :final secret, :final message):
          return LoginEnroll(otpauthUri, secret, message);
        case LoginTotpRequired(:final message):
          return LoginNeedsCode(message);
        case LoginMustChange():
          return const LoginNeedsPasswordChange();
      }
    } on ApiException catch (e) {
      return LoginFailed(e.message, e.statusCode);
    } catch (e) {
      return LoginFailed(e.toString());
    }
  }

  /// Stores [token], resolves the signed-in entity/role, and sets authenticated state.
  Future<LoginOutcome> _completeWithToken(ApiClient api, String phone, String token) async {
    await sessionStorage.setToken(token);
    await sessionStorage.setCurrentPhone(phone);
    final entityRepo = EntityRepository(api);
    // B-023: fetch only the caller's OWN entity (O(1)) instead of readAll-then-find,
    // which downloaded every entity in the system on each login.
    final Entity found;
    try {
      found = await entityRepo.me();
    } catch (_) {
      state = AsyncValue.data(AuthUnauthenticated());
      return const LoginFailed('Could not find entity for this user');
    }
    final user = found.liveUsers.where((u) => u.phone == phone).firstOrNull;
    if (user == null) {
      state = AsyncValue.data(AuthUnauthenticated());
      return const LoginFailed('Could not find entity for this user');
    }
    final foundRole = user.role;
    final foundCaps = user.capabilities;
    final foundIsPos = user.isPos;
    await sessionStorage.setCurrentEntityId(found.id);
    await sessionStorage.setCurrentEntityType(found.type.name);
    // isPos (any entity) OR the legacy USER-on-STORE rule → POS session.
    final isPosUser = foundIsPos || (foundRole == UserRole.USER && found.type == EntityType.STORE);
    final brand = await _loadBrand(api);
    state = AsyncValue.data(AuthAuthenticated(
        entity: found, role: foundRole, isPosUser: isPosUser, capabilities: foundCaps,
        effectiveCapabilities: found.effectiveCapabilities, brand: brand));
    return const LoginDone();
  }

  /// Best-effort branding fetch — a failure must never block login, so it falls
  /// back to an empty [BrandInfo] (the app then uses the entity's own theme).
  Future<BrandInfo> _loadBrand(ApiClient api) async {
    try {
      return await EntityRepository(api).branding();
    } catch (_) {
      return const BrandInfo();
    }
  }

  /// Forced password change (auth Phase 4): sets the new password and signs in.
  Future<LoginOutcome> changePassword(String phone, String oldPassword, String newPassword) async {
    // Same rule as login(): no loading/unauthenticated churn — it would remount the
    // login page and lose the change-password step (and its error message).
    // _completeWithToken sets the authenticated state on success.
    try {
      final api = ref.read(apiClientProvider);
      // B-011: change-password returns no token; the user re-authenticates via
      // login() so the second factor (TOTP/SMS OTP) is enforced.
      await AuthRepository(api).changePassword(phone, oldPassword, newPassword);
      return const LoginPasswordChanged();
    } on ApiException catch (e) {
      return LoginFailed(e.message, e.statusCode);
    } catch (e) {
      return LoginFailed(e.toString());
    }
  }

  Future<void> logout() async {
    // Revoke the token server-side first (best-effort), then clear locally.
    final api = ref.read(apiClientProvider);
    await AuthRepository(api).logout();
    await sessionStorage.clear();
    state = AsyncValue.data(AuthUnauthenticated());
  }

  /// Re-resolve the signed-in entity from `/entity/me` in place, keeping the
  /// session (B-054: the POS location gate lifts once the shop confirms). A
  /// failure leaves the current state untouched.
  Future<void> refresh() async {
    final auth = state.valueOrNull;
    if (auth is! AuthAuthenticated) return;
    try {
      final api = ref.read(apiClientProvider);
      final entity = await EntityRepository(api).me();
      state = AsyncValue.data(AuthAuthenticated(
        entity: entity,
        role: auth.role,
        isPosUser: auth.isPosUser,
        capabilities: auth.capabilities,
        effectiveCapabilities: entity.effectiveCapabilities,
        brand: auth.brand,
      ));
    } catch (_) {
      // Keep the current session on a transient failure.
    }
  }

  AuthAuthenticated? get current {
    final v = state.valueOrNull;
    return v is AuthAuthenticated ? v : null;
  }
}
