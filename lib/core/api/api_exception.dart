import 'package:dio/dio.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic raw;

  const ApiException(this.message, [this.statusCode, this.raw]);

  /// Unwraps the [ApiException] the auth interceptor packs into a thrown
  /// [DioException] (`DioException.error`). Returns null if [e] is neither an
  /// [ApiException] nor a [DioException] wrapping one. Use this at every catch
  /// site instead of `e is ApiException` — a raw `catch (e)` yields the
  /// DioException, so the bare type check never matches.
  static ApiException? from(Object? e) {
    if (e is ApiException) return e;
    if (e is DioException && e.error is ApiException) return e.error as ApiException;
    return null;
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
