import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inteshar/app/router.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/company_portal/domain/company_portal_models.dart';
import 'package:inteshar/features/entities/domain/entity.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// PROD-037: a telecom company's read-only account (Asiacell, Zain).
class _StubAuth extends AuthController {
  _StubAuth(this._state);
  final AuthState _state;
  @override
  Future<AuthState> build() async => _state;
}

void main() {
  group('the company tier', () {
    test('lands on its one screen and has no transfers or stock', () {
      expect(EntityType.COMPANY.homeRoute, '/company/home');
      expect(EntityType.COMPANY.transfersRoute, isNull);
      expect(EntityType.COMPANY.inventoryBacked, isFalse);
    });

    test('a COMPANY entity parses as one (not as HQ, the fallback)', () {
      final e = Entity.fromJson({
        'id': 'company-1',
        'type': 'COMPANY',
        'meta': {'name': 'Asiacell'},
        'users': [],
      });
      expect(e.type, EntityType.COMPANY);
    });

    test('is never a POS session, so it is routed to /company/home', () {
      final auth = AuthAuthenticated(
        entity: Entity(id: 'company-1', meta: const EntityMeta(name: 'Asiacell'), type: EntityType.COMPANY),
        role: UserRole.USER,
      );
      expect(auth.isPosUser, isFalse);
      expect(auth.homeRoute, '/company/home');
    });
  });

  group('routes', () {
    GoRouter buildRouter() {
      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith(() => _StubAuth(AuthAuthenticated(
              entity: Entity(id: 'e', meta: const EntityMeta(name: 'HQ'), type: EntityType.INTESHAR),
              role: UserRole.ADMIN,
            ))),
      ]);
      addTearDown(container.dispose);
      return container.read(routerProvider);
    }

    Iterable<GoRoute> goRoutes(List<RouteBase> roots) sync* {
      for (final r in roots) {
        if (r is GoRoute) yield r;
        yield* goRoutes(r.routes);
      }
    }

    test('the company screen, HQ\'s management page and the preview are mounted', () {
      final paths = goRoutes(buildRouter().configuration.routes).map((r) => r.path).toSet();
      expect(paths, containsAll(['/company/home', '/hq/company-accounts', '/hq/company-accounts/preview']));
    });
  });

  group('wire models', () {
    test('upload rows and accounts read the server\'s shapes', () {
      final r = CompanyUploadRow.fromJson(
          {'day': '2026-11-26', 'governorate': null, 'category': 'آسيا 5000', 'sku': 'ASIA5', 'count': 140});
      expect(r.governorate, '');
      expect(r.count, 140);

      final a = CompanyAccount.fromJson({
        'id': 'company-1',
        'name': 'Asiacell',
        'companyName': 'آسيا سيل',
        'phone': '07800000001',
        'active': false,
        'totpEnrolled': true,
        'lastSeenAt': '2026-11-26T19:00:00Z',
      });
      expect(a.active, isFalse);
      expect(a.totpEnrolled, isTrue);
      expect(a.lastSeenAt!.toUtc(), DateTime.utc(2026, 11, 26, 19));
    });

    test('activity reads in plain words, and a refused attempt says so', () {
      expect(const CompanyActivity(path: '/api/company-portal/uploads', status: 200).describe(ar: false),
          'Opened the uploads report');
      expect(const CompanyActivity(path: '/api/company-portal/exported', status: 200).describe(ar: true),
          'حفظ التقرير كملف Excel');
      const refused = CompanyActivity(method: 'GET', path: '/api/reports/sales', status: 403);
      expect(refused.refused, isTrue);
      expect(refused.describe(ar: false), 'Refused attempt: GET /api/reports/sales');
    });
  });
}
