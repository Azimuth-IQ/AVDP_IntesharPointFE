import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:inteshar/features/update/domain/app_release.dart';
import 'package:inteshar/features/update/domain/update_errors.dart';

/// Android implementation: grant install permission → download → verify → open
/// the system package installer. Selected via conditional import in
/// `apk_installer.dart` so the dart:io reference never reaches a web build.
Future<void> installApk(
  Dio dio,
  AppRelease release, {
  void Function(double)? onProgress,
}) async {
  if (!Platform.isAndroid) {
    throw UnsupportedError('In-app APK install is Android-only');
  }

  // 1. "Install unknown apps" permission (REQUEST_INSTALL_PACKAGES).
  final status = await Permission.requestInstallPackages.request();
  if (!status.isGranted) {
    throw const InstallPermissionDenied();
  }

  // 2. Save into the app-specific external dir. It needs no storage permission
  //    (scoped storage) and is reachable by the package installer through
  //    open_filex's bundled FileProvider.
  final dir = await getExternalStorageDirectory();
  if (dir == null) {
    throw Exception('No external storage directory available');
  }
  final file = File('${dir.path}/inteshar-${release.versionCode}.apk');
  if (await file.exists()) {
    await file.delete();
  }

  await dio.download(
    release.apkUrl,
    file.path,
    onReceiveProgress: (received, total) {
      if (total > 0) onProgress?.call(received / total);
    },
  );

  // 3. Integrity: refuse to install if the bytes don't match the published hash.
  final expected = release.sha256;
  if (expected != null && expected.isNotEmpty) {
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != expected.toLowerCase()) {
      await file.delete();
      throw Exception('APK integrity check failed (sha256 mismatch)');
    }
  }

  // 4. Hand the APK to the system installer.
  final result = await OpenFilex.open(
    file.path,
    type: 'application/vnd.android.package-archive',
  );
  if (result.type != ResultType.done) {
    throw Exception('Could not open installer: ${result.message}');
  }
}
