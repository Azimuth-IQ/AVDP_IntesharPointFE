import 'package:dio/dio.dart';
import 'package:inteshar/features/update/domain/app_release.dart';

// Web-safe shim: the real implementation uses dart:io (not available on web).
// Mirrors the project's core/files/web_download conditional-import pattern.
import 'apk_installer_stub.dart'
    if (dart.library.io) 'apk_installer_io.dart';

export 'package:inteshar/features/update/domain/update_errors.dart';

typedef ApkProgress = void Function(double fraction);

/// Downloads [release]'s APK into the app-specific external dir, verifies its
/// sha256, then launches the Android package installer. Android-only; throws
/// [UnsupportedError] elsewhere. See `apk_installer_io.dart`.
Future<void> downloadAndInstallApk(
  Dio dio,
  AppRelease release, {
  ApkProgress? onProgress,
}) =>
    installApk(dio, release, onProgress: onProgress);
