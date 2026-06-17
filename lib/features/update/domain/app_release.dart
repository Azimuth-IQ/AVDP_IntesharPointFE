/// A published app build, mirroring the backend `AppRelease`. The app compares
/// [versionCode] against its own build number to decide whether to update.
class AppRelease {
  final String channel;
  final String platform;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final int sizeBytes;
  final String? sha256;
  final bool mandatory;
  final int minSupportedVersionCode;
  final String? changelog;

  const AppRelease({
    required this.channel,
    required this.platform,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sizeBytes,
    required this.sha256,
    required this.mandatory,
    required this.minSupportedVersionCode,
    required this.changelog,
  });

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
        channel: j['channel'] as String? ?? 'uat',
        platform: j['platform'] as String? ?? 'android',
        versionName: j['versionName'] as String? ?? '',
        versionCode: (j['versionCode'] as num?)?.toInt() ?? 0,
        apkUrl: j['apkUrl'] as String? ?? '',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: j['sha256'] as String?,
        mandatory: j['mandatory'] as bool? ?? false,
        minSupportedVersionCode: (j['minSupportedVersionCode'] as num?)?.toInt() ?? 0,
        changelog: j['changelog'] as String?,
      );

  /// Human-readable download size, e.g. "23.4 MB".
  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Result of GET /api/app/check.
class UpdateCheck {
  final bool updateAvailable;
  final bool mandatory;
  final AppRelease? latest;

  const UpdateCheck({
    required this.updateAvailable,
    required this.mandatory,
    required this.latest,
  });

  factory UpdateCheck.fromJson(Map<String, dynamic> j) => UpdateCheck(
        updateAvailable: j['updateAvailable'] as bool? ?? false,
        mandatory: j['mandatory'] as bool? ?? false,
        latest: j['latest'] != null
            ? AppRelease.fromJson(j['latest'] as Map<String, dynamic>)
            : null,
      );
}
