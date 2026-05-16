import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/api_exception.dart';
import 'package:inteshar/core/api/endpoints.dart';

class AuthRepository {
  final ApiClient _api;
  AuthRepository(this._api);

  Future<String> login(String phone, String password) async {
    try {
      final response = await _api.post(
        Endpoints.login,
        data: {'phone': phone, 'password': password},
      );
      final body = response.data;
      if (body is Map && body['token'] != null) {
        return body['token'] as String;
      }
      throw const ApiException('Login failed: no token in response');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(e.toString());
    }
  }
}
