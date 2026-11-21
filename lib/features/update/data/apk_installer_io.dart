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
  final expected = release.sha256;
  // PROD-018: the cashier may cancel the installer and tap "Update now" again. A file that
  // already matches the published hash is reused instead of downloading ~50 MB again.
  final reusable = await file.exists() &&
      expected != null &&
      expected.isNotEmpty &&
      (await sha256.bind(file.openRead()).first).toString().toLowerCase() == expected.toLowerCase();
  if (reusable) {
    onProgress?.call(1);
  } else {
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
  }

  // 3. Integrity: refuse to install unless the bytes match the published hash. A release
  //    without a hash is refused too (audit G02) — skipping the check when it was missing
  //    meant anyone able to tamper with the release record could ship any APK.
  if (expected == null || expected.isEmpty) {
    await file.delete();
    throw Exception('APK integrity check failed (the release has no sha256)');
  }
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString().toLowerCase() != expected.toLowerCase()) {
    await file.delete();
    throw Exception('APK integrity check failed (sha256 mismatch)');
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
