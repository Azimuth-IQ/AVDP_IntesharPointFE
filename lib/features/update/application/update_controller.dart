import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:inteshar/core/utils/hand_off.dart';
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

/// PROD-017: how often an open app looks again for a newer build. A POS terminal is
/// left running for days, and signing out and back in does not restart the app.
const updateRecheckEvery = Duration(hours: 6);

/// PROD-017: returning to the app re-checks too, but at most this often.
const updateResumeGap = Duration(hours: 1);

/// Whether coming back to the app should look for an update again.
bool shouldRecheckOnResume(DateTime? lastCheck, DateTime now) =>
    lastCheck == null || now.difference(lastCheck) >= updateResumeGap;

class UpdateController extends Notifier<UpdateState> {
  bool _inFlight = false;
  DateTime? _lastCheck;

  /// When the backend last answered a check (null before the first answer).
  DateTime? get lastCheck => _lastCheck;

  @override
  UpdateState build() => const UpdateIdle();

  /// Queries the backend and moves to [UpdateAvailableState] or [UpToDate].
  /// Fails open: a check error never blocks the app (unless already forced).
  ///
  /// PROD-017: called again on resume and every [updateRecheckEvery]. A re-check never
  /// interrupts a download, and keeps what is on screen until the answer arrives (no
  /// flicker of the sheet); a failed re-check leaves the last answer in place.
  Future<void> check() async {
    // Self-install is Android-only; web/desktop/iOS have nothing to do.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      state = const UpToDate();
      return;
    }
    if (_inFlight || state is UpdateDownloading) return;
    _inFlight = true;
    final first = state is UpdateIdle;
    if (first) state = const UpdateChecking();
    try {
      final pkg = await PackageInfo.fromPlatform();
      final versionCode = int.tryParse(pkg.buildNumber) ?? 0;
      final result = await ref.read(releaseRepositoryProvider).check(versionCode: versionCode);
      _lastCheck = DateTime.now();
      if (state is UpdateDownloading) return; // the cashier started the download meanwhile
      if (result.updateAvailable && result.latest != null) {
        state = UpdateAvailableState(result.latest!, result.mandatory);
      } else {
        state = const UpToDate();
      }
    } catch (_) {
      if (first) state = const UpToDate();
    } finally {
      _inFlight = false;
    }
  }

  /// Downloads + verifies + launches the installer for the pending release.
  Future<void> install() async {
    HandOff.mark(); // PROD-033: the installer takes the screen; cancelling must not ask for the PIN
    final (release, mandatory) = switch (state) {
      UpdateAvailableState s => (s.release, s.mandatory),
      UpdateFailed s => (s.release, s.mandatory),
      UpdateDownloading s => (s.release, s.mandatory),
      _ => (null, false),
    };
    if (release == null || state is UpdateDownloading) return;

    state = UpdateDownloading(release, mandatory, 0);
    try {
      await downloadAndInstallApk(
        ref.read(dioProvider),
        release,
        onProgress: (p) => state = UpdateDownloading(release, mandatory, p),
      );
      // The system installer is now in front. Installing restarts the app; if the cashier
      // cancels it instead, the "Update now" button is back (PROD-018) — the verified file
      // is kept, so a second tap does not download it again.
      state = UpdateAvailableState(release, mandatory);
    } on InstallPermissionDenied {
      state = UpdateFailed(release, mandatory, 'permission', permissionDenied: true);
    } catch (e) {
      state = UpdateFailed(release, mandatory, e.toString());
    }
  }

  /// Put off an optional prompt until the next check (no-op for forced updates, and while
  /// downloading — the sheet stays up until the installer opens, PROD-018).
  void dismiss() {
    final s = state;
    if (s is UpdateDownloading) return;
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
