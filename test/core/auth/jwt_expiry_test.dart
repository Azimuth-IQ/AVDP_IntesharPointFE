import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/auth/jwt_expiry.dart';

/// A JWT-shaped string whose payload carries [exp] (seconds since the epoch). The signature is
/// irrelevant: the app never verifies it, it only reads `exp`.
String _token(Object? exp) {
  String part(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': '0770', 'exp': ?exp})}.c2ln';
}

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  test('a token past its exp is expired', () {
    expect(isJwtExpired(_token(secs(now.subtract(const Duration(hours: 1)))), now: now), isTrue);
  });

  test('a token still inside its 24h life is not expired', () {
    expect(isJwtExpired(_token(secs(now.add(const Duration(hours: 23)))), now: now), isFalse);
  });

  test('a device clock running slightly fast does not end a live session', () {
    expect(isJwtExpired(_token(secs(now.subtract(const Duration(seconds: 10)))), now: now), isFalse);
  });

  test('an unreadable token is left to the server to judge', () {
    expect(isJwtExpired('not-a-jwt', now: now), isFalse);
    expect(isJwtExpired('a.%%%.c', now: now), isFalse);
    expect(isJwtExpired(_token(null), now: now), isFalse);
  });
}
