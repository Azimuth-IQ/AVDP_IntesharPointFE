import 'package:dio/dio.dart';
import 'package:inteshar/features/update/domain/app_release.dart';

/// Non-Android (web / desktop) fallback: there is no in-app APK install.
Future<void> installApk(
  Dio dio,
  AppRelease release, {
  void Function(double)? onProgress,
}) async {
  throw UnsupportedError('In-app APK install is only available on Android');
}
