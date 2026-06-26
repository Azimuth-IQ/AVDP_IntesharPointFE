import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/session_invalidation.dart';
import 'package:inteshar/core/logging/client_log_reporter.dart';
import 'package:inteshar/core/logging/device_context.dart';
import 'package:inteshar/core/storage/session_storage.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15), sendTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(_AuthInterceptor(ref));
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
    if (err.response?.statusCode == 401) {
      // Token rejected (expired, or the backend's SESSION_SUPERSEDED — signed in
      // elsewhere / logged out). Clear the dead session and tick the invalidation
      // signal so AuthController rebuilds and the router bounces to /login.
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
