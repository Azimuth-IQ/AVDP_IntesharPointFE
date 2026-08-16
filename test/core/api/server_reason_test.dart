import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/error_mapper.dart';

/// serverReason exists so a caller can show the one detail the client cannot
/// work out for itself — which shop already holds a phone number. Everything
/// else still belongs to friendlyError.
void main() {
  group('serverReason', () {
    test('returns the message the backend sent', () {
      final e = ApiException('This phone number is already used by "موبايلات الرصافة"', 409);
      expect(serverReason(e), 'This phone number is already used by "موبايلات الرصافة"');
    });

    test('unwraps the DioException the interceptor packs it into', () {
      // A bare `catch (e)` yields the DioException, not the ApiException — the
      // same trap isDuplicatePhone documents.
      final wrapped = DioException(
        requestOptions: RequestOptions(path: '/api/pos-users/onboard'),
        error: const ApiException('registered to a point of sale under another agent', 409),
      );
      expect(serverReason(wrapped), 'registered to a point of sale under another agent');
    });

    test('trims surrounding whitespace', () {
      expect(serverReason(const ApiException('   spaced   ', 409)), 'spaced');
    });

    test('an empty or blank message yields null so the caller can fall back', () {
      expect(serverReason(const ApiException('', 409)), isNull);
      expect(serverReason(const ApiException('    ', 409)), isNull);
    });

    test('a non-API error yields null rather than leaking a stack string', () {
      expect(serverReason(StateError('boom')), isNull);
      expect(serverReason(null), isNull);
    });
  });
}
