import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/storage/session_storage.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15), sendTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(_AuthInterceptor());
  return dio;
});

class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await sessionStorage.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      await sessionStorage.clear();
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

  Future<Response<dynamic>> post(String path, {dynamic data}) async {
    final base = await baseUrl;
    return _dio.post('$base$path', data: data);
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
