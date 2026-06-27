// Tests for the pure [retryDelay] function in api_client.dart.
//
// No new dependencies — imports only flutter_test (already in dev_dependencies)
// and the production library under test.  No Dio mocking or widget pumping is
// needed because [retryDelay] accepts plain String / bool / enum values.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_client.dart';

void main() {
  // Shorthand so each test stays on one line.
  Duration? delay({
    String method = 'GET',
    bool hasResponse = false,
    DioExceptionType errorType = DioExceptionType.connectionTimeout,
    int attempt = 1,
    int maxAttempts = 3,
  }) =>
      retryDelay(
        method: method,
        hasResponse: hasResponse,
        errorType: errorType,
        attempt: attempt,
        maxAttempts: maxAttempts,
      );

  group('retryDelay — eligible requests', () {
    test('returns 500 ms on the first failed GET (attempt 1)', () {
      expect(delay(), equals(const Duration(milliseconds: 500)));
    });

    test('doubles to 1 000 ms on attempt 2 (exponential back-off)', () {
      expect(delay(attempt: 2), equals(const Duration(milliseconds: 1000)));
    });

    test('retries on connectionError', () {
      expect(delay(errorType: DioExceptionType.connectionError), isNotNull);
    });

    test('retries on receiveTimeout', () {
      expect(delay(errorType: DioExceptionType.receiveTimeout), isNotNull);
    });

    test('retries on sendTimeout', () {
      expect(delay(errorType: DioExceptionType.sendTimeout), isNotNull);
    });

    test('method comparison is case-insensitive (lowercase get)', () {
      expect(delay(method: 'get'), isNotNull);
    });
  });

  group('retryDelay — exhausted attempts', () {
    test('returns null when attempt == maxAttempts (default 3)', () {
      expect(delay(attempt: 3), isNull);
    });

    test('returns null when attempt > maxAttempts', () {
      expect(delay(attempt: 10), isNull);
    });

    test('custom maxAttempts=2 stops after attempt 2', () {
      expect(delay(attempt: 2, maxAttempts: 2), isNull);
    });

    test('custom maxAttempts=2 still retries attempt 1', () {
      expect(delay(attempt: 1, maxAttempts: 2), isNotNull);
    });
  });

  group('retryDelay — ineligible requests (must return null)', () {
    test('does not retry POST', () {
      expect(delay(method: 'POST'), isNull);
    });

    test('does not retry PUT', () {
      expect(delay(method: 'PUT'), isNull);
    });

    test('does not retry DELETE', () {
      expect(delay(method: 'DELETE'), isNull);
    });

    test('does not retry PATCH', () {
      expect(delay(method: 'PATCH'), isNull);
    });

    test('does not retry when server responded (hasResponse=true)', () {
      // Any 4xx/5xx — server was reached, never retry.
      expect(delay(hasResponse: true), isNull);
    });

    test('does not retry on badResponse (server-level error type)', () {
      expect(delay(errorType: DioExceptionType.badResponse), isNull);
    });

    test('does not retry on badCertificate', () {
      expect(delay(errorType: DioExceptionType.badCertificate), isNull);
    });

    test('does not retry on cancel', () {
      expect(delay(errorType: DioExceptionType.cancel), isNull);
    });

    test('does not retry on unknown', () {
      expect(delay(errorType: DioExceptionType.unknown), isNull);
    });
  });
}
