import 'package:dio/dio.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/logging/device_context.dart';
import 'package:inteshar/core/storage/session_storage.dart';

/// Ships client-side events (crashes, uncaught errors, network failures the
/// server never saw) to `POST /api/logs/client`. Uses its OWN Dio with no
/// interceptors so it can never trigger the request-logging/error loop, and is
/// strictly best-effort — it must never throw or block the app.
class ClientLogReporter {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    sendTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  static Future<void> report({
    required String message,
    String level = 'ERROR',
    String? errorType,
    String? stack,
    String? path,
    String? action,
  }) async {
    try {
      final base = await sessionStorage.getBaseUrl();
      final entityId = await sessionStorage.getCurrentEntityId();
      final phone = await sessionStorage.getCurrentPhone();
      final entityType = await sessionStorage.getCurrentEntityType();
      await _dio.post('$base${Endpoints.logClient}', data: {
        'level': level,
        'platform': DeviceContext.platform,
        'surface': surfaceForEntityType(entityType),
        'deviceModel': DeviceContext.deviceModel,
        'osVersion': DeviceContext.osVersion,
        'appVersion': DeviceContext.appVersion,
        'entityId': entityId,
        'userPhone': phone,
        'path': path,
        'action': action,
        'errorType': errorType,
        'message': message,
        'stack': stack,
      });
    } catch (_) {
      // swallow — telemetry must never crash or slow the app
    }
  }
}
