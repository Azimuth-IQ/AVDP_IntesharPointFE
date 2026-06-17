import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/features/update/data/apk_installer.dart';
import 'package:inteshar/features/update/data/release_repository.dart';
import 'package:inteshar/features/update/domain/app_release.dart';

/// State of the in-app updater.
sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpToDate extends UpdateState {
  const UpToDate();
}

/// A newer build exists. [mandatory] gates the app behind a forced screen.
class UpdateAvailableState extends UpdateState {
  final AppRelease release;
  final bool mandatory;
  const UpdateAvailableState(this.release, this.mandatory);
}

class UpdateDownloading extends UpdateState {
  final AppRelease release;
  final bool mandatory;
  final double progress; // 0..1
  const UpdateDownloading(this.release, this.mandatory, this.progress);
}

class UpdateFailed extends UpdateState {
  final AppRelease release;
  final bool mandatory;
  final String message;
  final bool permissionDenied;
  const UpdateFailed(this.release, this.mandatory, this.message, {this.permissionDenied = false});
}

class UpdateController extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateIdle();

  /// Queries the backend and moves to [UpdateAvailableState] or [UpToDate].
  /// Fails open: a check error never blocks the app (unless already forced).
  Future<void> check() async {
    // Self-install is Android-only; web/desktop/iOS have nothing to do.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      state = const UpToDate();
      return;
    }
    state = const UpdateChecking();
    try {
      final pkg = await PackageInfo.fromPlatform();
      final versionCode = int.tryParse(pkg.buildNumber) ?? 0;
      final result = await ref.read(releaseRepositoryProvider).check(versionCode: versionCode);
      if (result.updateAvailable && result.latest != null) {
        state = UpdateAvailableState(result.latest!, result.mandatory);
      } else {
        state = const UpToDate();
      }
    } catch (_) {
      state = const UpToDate();
    }
  }

  /// Downloads + verifies + launches the installer for the pending release.
  Future<void> install() async {
    final (release, mandatory) = switch (state) {
      UpdateAvailableState s => (s.release, s.mandatory),
      UpdateFailed s => (s.release, s.mandatory),
      UpdateDownloading s => (s.release, s.mandatory),
      _ => (null, false),
    };
    if (release == null) return;

    state = UpdateDownloading(release, mandatory, 0);
    try {
      await downloadAndInstallApk(
        ref.read(dioProvider),
        release,
        onProgress: (p) => state = UpdateDownloading(release, mandatory, p),
      );
      // The system installer is now in front; nothing more to do here.
    } on InstallPermissionDenied {
      state = UpdateFailed(release, mandatory, 'permission', permissionDenied: true);
    } catch (e) {
      state = UpdateFailed(release, mandatory, e.toString());
    }
  }

  /// Dismiss an optional prompt for this session (no-op for forced updates).
  void dismiss() {
    final s = state;
    final mandatory = switch (s) {
      UpdateAvailableState v => v.mandatory,
      UpdateFailed v => v.mandatory,
      _ => false,
    };
    if (!mandatory) state = const UpToDate();
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
