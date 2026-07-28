import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/system_activity/domain/log_phrase.dart';
import 'package:inteshar/features/system_activity/domain/operation_log.dart';

/// B-110: the first dictionary covered ~40 routes and the activity feed was
/// still mostly "Request" — reads dominate the log, and reads were what was
/// missing. This asserts EVERY route the backend exposes resolves to a real
/// phrase, so the gap can't silently reopen when endpoints are added.
///
/// The route list is generated from the backend controllers (see
/// test/fixtures/backend_routes.txt) rather than hand-copied, so a new
/// `@…Mapping` shows up here the moment the fixture is refreshed.
void main() {
  final fixture = File('test/fixtures/backend_routes.txt');

  test('the fixture exists and looks like a full route dump', () {
    expect(fixture.existsSync(), isTrue,
        reason: 'regenerate with the snippet in this file\'s header');
    expect(fixture.readAsLinesSync().where((l) => l.trim().isNotEmpty).length,
        greaterThan(100),
        reason: 'a truncated dump would make the coverage assertion meaningless');
  });

  test('every backend route resolves to a phrase, in both languages', () {
    final routes = fixture
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l.startsWith('/api'))
        .toList();

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
