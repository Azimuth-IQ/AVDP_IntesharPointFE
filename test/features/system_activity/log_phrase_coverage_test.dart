import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/system_activity/domain/log_phrase.dart';
import 'package:inteshar/features/system_activity/domain/operation_log.dart';

import '../../../tool/gen_backend_routes.dart' as gen;

/// B-110: the first dictionary covered ~40 routes and the activity feed was
/// still mostly "Request" — reads dominate the log, and reads were what was
/// missing. This asserts EVERY route the backend exposes resolves to a real
/// phrase, so the gap can't silently reopen when endpoints are added.
///
/// The route list lives in `test/fixtures/backend_routes.txt`, which is
/// GENERATED — never hand-edited:
///
///     dart run tool/gen_backend_routes.dart
///
/// It used to be a one-off snapshot, which meant a new backend endpoint failed
/// nothing at all: it just rendered as a bare "Request" in the app until
/// somebody happened to refresh the file. The "in sync with the backend
/// controllers" test below closes that hole by re-parsing the controllers on
/// every run. When the backend repo isn't checked out (the FE builds alone in
/// CI — see .github/workflows/apk.yml) that ONE test skips; the phrase-coverage
/// assertion still runs against the committed fixture.
void main() {
  final fixture = File(gen.fixturePath);
  List<String> fixtureRoutes() => gen.parseFixture(fixture.readAsStringSync());

  test('the fixture exists and looks like a full route dump', () {
    expect(fixture.existsSync(), isTrue,
        reason: 'regenerate with: ${gen.regenerateCommand}');
    final routes = fixtureRoutes();
    expect(routes.length, greaterThan(100),
        reason: 'a truncated dump would make the coverage assertion meaningless');
    // Every line is asserted on below. Nothing here may be quietly filtered out
    // — a route parsed without its `/api` base would mean the generator read a
    // class-level @RequestMapping it could not resolve.
    expect(routes.where((r) => !r.startsWith('/api')), isEmpty,
        reason: 'these fixture lines are not API routes; the parser in '
            'tool/gen_backend_routes.dart probably lost a base path');
  });

  test('the fixture is in sync with the backend controllers', () {
    final backend = gen.locateBackendSource();
    if (backend == null) {
      // FE-only checkout. Skip THIS check only — coverage still runs below.
      markTestSkipped(
          'backend source not found (looked in ${gen.backendSearchPaths().join(", ")}); '
          'set ${gen.backendSrcEnvVar} to point at avdp_inteshar_be/src/main/java');
      return;
    }

    final scan = gen.scanBackendRoutes(backend);
    expect(scan.paths.length, greaterThan(100),
        reason: 'only ${scan.paths.length} routes parsed out of ${backend.path} — '
            'either the parser in tool/gen_backend_routes.dart broke, or that '
            'checkout is on a much older branch. Either way the comparison below '
            'would be meaningless, so it is not run');

    final known = fixtureRoutes().toSet();
    final missing = scan.paths.where((p) => !known.contains(p)).toList();
    final stale = known.where((p) => !scan.paths.contains(p)).toList();

    // Routes the fixture lists that no longer exist are only cruft — and a
    // backend checkout sitting on an older branch would produce a pile of them
    // — so they warn. A route the fixture is MISSING is the actual bug.
    if (stale.isNotEmpty) {
      // ignore: avoid_print
      print('note: ${stale.length} fixture route(s) no longer exist in the '
          'backend; `${gen.regenerateCommand}` will drop them:'
          '\n  ${stale.join('\n  ')}');
    }

    final detail = missing.map((r) {
      final concrete = r.replaceAll(RegExp(r'\{[^}]+\}'), 'abc123');
      final phrased =
          logPhrase(OperationLog(path: concrete), ar: false).title != 'Request';
      final origin = scan.routes.firstWhere((x) => x.path == r).origin;
      return '  $r  ($origin)'
          '${phrased ? '' : '  <- also needs a phrase in log_phrase.dart'}';
    }).join('\n');

    expect(missing, isEmpty,
        reason: '${gen.fixturePath} is STALE — the backend maps ${missing.length} '
            'route(s) it does not list, so they render as a bare "Request" in the '
            'activity feed:\n$detail\n'
            'Regenerate it (from the Flutter package root):\n'
            '  ${gen.regenerateCommand}\n'
            'then add a phrase for each new route in '
            'lib/features/system_activity/domain/log_phrase.dart.');
  });

  test('every backend route resolves to a phrase, in both languages', () {
    final routes = fixtureRoutes();

    final unmapped = <String>[];
    for (final route in routes) {
      // Substitute a realistic value for any path variable.
      final concrete = route.replaceAll(RegExp(r'\{[^}]+\}'), 'abc123');
      final en = logPhrase(OperationLog(path: concrete), ar: false);
      final ar = logPhrase(OperationLog(path: concrete), ar: true);
      if (en.title == 'Request' || ar.title == 'طلب') unmapped.add(route);

      // Whatever it resolved to, it must never be a URL.
      expect(en.line.contains('/'), isFalse, reason: 'URL leaked for $route');
      expect(ar.line.contains('/'), isFalse, reason: 'URL leaked for $route');
    }

    expect(unmapped, isEmpty,
        reason: 'these routes still read as a bare "Request":\n  ${unmapped.join('\n  ')}');
  });

  test('the two languages never return the same string for a real route', () {
    // A phrase that is identical in both is almost always an untranslated one.
    const sample = [
      '/api/auth/login',
      '/api/balance/grant',
      '/api/inventory/product/sendForPrinting',
      '/api/entity/create',
      '/api/reports/sales',
      '/api/chat/send',
    ];
    for (final r in sample) {
      final en = logPhrase(OperationLog(path: r), ar: false).title;
      final ar = logPhrase(OperationLog(path: r), ar: true).title;
      expect(ar, isNot(en), reason: '$r looks untranslated');
      expect(RegExp(r'[؀-ۿ]').hasMatch(ar), isTrue, reason: '$r has no Arabic');
    }
  });

  test('an unknown route still degrades to a translated request', () {
    final en = logPhrase(OperationLog(path: '/api/not/a/real/route'), ar: false);
    final ar = logPhrase(OperationLog(path: '/api/not/a/real/route'), ar: true);
    expect(en.title, 'Request');
    expect(ar.title, 'طلب');
  });
}
