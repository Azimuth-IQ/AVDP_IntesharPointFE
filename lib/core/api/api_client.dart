import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/session_invalidation.dart';
import 'package:inteshar/core/logging/client_log_reporter.dart';
import 'package:inteshar/core/logging/device_context.dart';
import 'package:inteshar/core/storage/session_storage.dart';

/// Pure function — no I/O. Returns the delay before the next retry attempt,
/// or [null] if the request must NOT be retried.
///
/// Only idempotent GETs on transport-level failures (no server response) are
/// eligible — POSTs (login, transaction create, draw) are never retried
/// regardless of error type.
///
/// [method]      HTTP verb (case-insensitive).
/// [hasResponse] true when the server returned any HTTP status (4xx/5xx etc.).
/// [errorType]   Dio error classification.
/// [attempt]     1-based number of the attempt that just failed.
/// [maxAttempts] Total attempts allowed (first try + retries); defaults to 3.
Duration? retryDelay({
  required String method,
  required bool hasResponse,
  required DioExceptionType errorType,
  required int attempt,
  int maxAttempts = 3,
}) {
  if (method.toUpperCase() != 'GET') return null;
  if (hasResponse) return null;
  const retryableTypes = {
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.connectionError,
  };
  if (!retryableTypes.contains(errorType)) return null;
  if (attempt >= maxAttempts) return null;
  // Exponential back-off: 500 ms → 1 000 ms → 2 000 ms …
  return Duration(milliseconds: 500 * (1 << (attempt - 1)));
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15), sendTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(_AuthInterceptor(ref));
  // _RetryInterceptor is added AFTER _AuthInterceptor so that in the reverse
  // error-processing order it fires FIRST: it retries GETs on transport errors
  // and only calls handler.next when retries are exhausted, letting
  // _AuthInterceptor.onError run exactly once for the final failure.
  dio.interceptors.add(_RetryInterceptor(dio));
  return dio;
});

class _AuthInterceptor extends Interceptor {
  final Ref _ref;
  _AuthInterceptor(this._ref);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await sessionStorage.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    // Operational-logging context — recorded by the server request log.
    options.headers.addAll(DeviceContext.headers);
    final entityId = await sessionStorage.getCurrentEntityId();
    if (entityId != null) options.headers['X-Entity-Id'] = entityId;
    final entityType = await sessionStorage.getCurrentEntityType();
    if (entityType != null) {
      options.headers['X-Client-Surface'] = surfaceForEntityType(entityType);
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // End the session on a 401 (expired / SESSION_SUPERSEDED) OR the working-hours
    // 403 (the account window closed mid-session): clear and tick the invalidation
    // signal so AuthController rebuilds and the router bounces to /login. A plain
    // 403 (forbidden action) does NOT end the session.
    final code = err.response?.statusCode;
    final data = err.response?.data;
    final sessionEnded = code == 401 ||
        (code == 403 && data is Map && data['data'] == 'OUTSIDE_WORKING_HOURS');
    if (sessionEnded) {
      await sessionStorage.clear();
      _ref.read(sessionInvalidationProvider.notifier).state++;
    }
    // A null response = the request never reached the server (timeout, refused,
    // offline). The server log can't see these, so report from the client.
    // Guard the log path so a failing report can't loop.
    final path = err.requestOptions.path;
    if (err.response == null && !path.contains('/api/logs/')) {
      unawaited(ClientLogReporter.report(
        level: 'ERROR',
        errorType: err.type.toString(),
        message: err.message ?? 'Network error',
        path: path,
        action: 'networkFailure',
      ));
    }
    final msg = _extractMessage(err);
    handler.reject(
      DioException(requestOptions: err.requestOptions, error: ApiException(msg, err.response?.statusCode, err.response?.data), response: err.response, type: err.type),
    );
  }

  String _extractMessage(DioException err) {
    final data = err.response?.data;
    if (data is Map && data['message'] != null) return data['message'] as String;
    return err.message ?? 'Unknown error';
  }
}

/// Retries idempotent GET requests on transport errors with exponential
/// back-off. The retry/delay decision is delegated to [retryDelay].
///
/// On success the resolved response bypasses the rest of the interceptor chain.
/// On exhausted retries [handler.next] is called so [_AuthInterceptor.onError]
/// (the next interceptor in reverse order) runs exactly once for the final
/// failure — handling session-end and client-side transport-error reporting.
/// Intermediate failures caught from inner [_dio.fetch] calls use
/// [handler.reject] to skip re-running [_AuthInterceptor.onError] a second time.
class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  static const String _attemptKey = '_retry_attempt';

  _RetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 1;
    final delay = retryDelay(
      method: err.requestOptions.method,
      hasResponse: err.response != null,
      errorType: err.type,
      attempt: attempt,
    );
    if (delay == null) {
      // Not retrying — let _AuthInterceptor.onError handle it.
      handler.next(err);
      return;
    }
    await Future<void>.delayed(delay);
    final opts = err.requestOptions;
    opts.extra[_attemptKey] = attempt + 1;
    try {
      // Re-issue through the full interceptor chain so _AuthInterceptor stamps
      // a fresh token. On success, resolve directly (skip remaining chain).
      handler.resolve(await _dio.fetch<dynamic>(opts));
    } on DioException catch (retryErr) {
      // The inner fetch already ran through the full error chain (including
      // _AuthInterceptor.onError which wrapped the error). Use reject — not
      // next — to propagate without running _AuthInterceptor.onError again.
      handler.reject(retryErr);
    }
  }
}

class ApiClient {
  final Dio _dio;

  ApiClient(this._dio);

  Future<String> get baseUrl async => sessionStorage.getBaseUrl();

  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? params}) async {
    final base = await baseUrl;
    return _dio.get('$base$path', queryParameters: params);
  }

  Future<Response<dynamic>> post(String path, {dynamic data, Map<String, dynamic>? params}) async {
    final base = await baseUrl;
    return _dio.post('$base$path', data: data, queryParameters: params);
  }

  Future<Response<dynamic>> put(String path, {dynamic data}) async {
    final base = await baseUrl;
    return _dio.put('$base$path', data: data);
  }

  Future<Response<dynamic>> delete(String path, {Map<String, dynamic>? params, dynamic data}) async {
    final base = await baseUrl;
    return _dio.delete('$base$path', queryParameters: params, data: data);
  }

  /// Download raw bytes (e.g. a TXT batch export). Uses [ResponseType.bytes] so
  /// Dio does not attempt JSON decoding — returns the raw body as [Uint8List].
  Future<Uint8List> getBytes(String path,
      {Map<String, dynamic>? params}) async {
    final base = await baseUrl;
    final response = await _dio.get<List<int>>(
      '$base$path',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? []);
  }

  T unwrap<T>(Response<dynamic> r, T Function(dynamic) parse) {
    final body = r.data;
    if (body is Map) {
      final bodyStatus = (body['status'] as num?)?.toInt();
      if (bodyStatus != null && (bodyStatus < 200 || bodyStatus >= 300)) {
        throw ApiException(body['message'] as String? ?? 'Request failed', r.statusCode);
      }
      if (body.containsKey('data') && body['data'] != null) {
        return parse(body['data']);
      }
    }
    return parse(body);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(dioProvider));
});
