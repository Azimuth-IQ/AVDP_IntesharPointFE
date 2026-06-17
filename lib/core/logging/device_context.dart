import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Resolves the platform / device / app-version once and exposes them as request
/// headers (for the server operation log) and for client crash reports. Uses
/// [defaultTargetPlatform] (not dart:io) so it compiles cleanly for web.
class DeviceContext {
  static String platform = 'unknown';
  static String deviceModel = '';
  static String osVersion = '';
  static String appVersion = '';
  static bool _ready = false;

  static Map<String, String> get headers => {
        if (platform.isNotEmpty) 'X-Client-Platform': platform,
        if (deviceModel.isNotEmpty) 'X-Device-Model': deviceModel,
        if (osVersion.isNotEmpty) 'X-OS-Version': osVersion,
        if (appVersion.isNotEmpty) 'X-App-Version': appVersion,
      };

  static Future<void> init() async {
    if (_ready) return;
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        platform = 'web';
        final w = await info.webBrowserInfo;
        deviceModel = '${w.browserName.name} ${w.platform ?? ''}'.trim();
        osVersion = (w.userAgent ?? '').trim();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        platform = 'android';
        final a = await info.androidInfo;
        deviceModel = '${a.manufacturer} ${a.model}'.trim();
        osVersion = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        platform = 'ios';
        final i = await info.iosInfo;
        deviceModel = i.utsname.machine;
        osVersion = '${i.systemName} ${i.systemVersion}';
      } else {
        platform = defaultTargetPlatform.name;
      }
      final pkg = await PackageInfo.fromPlatform();
      appVersion = '${pkg.version}+${pkg.buildNumber}';
    } catch (_) {
      // best-effort; leave whatever defaults resolved
    }
    _ready = true;
  }
}

/// Maps a stored EntityType name to the UI surface used in logs.
String surfaceForEntityType(String? entityType) {
  switch (entityType) {
    case 'INTESHAR':
      return 'hq';
    case 'AGENT1':
      return 'agent1';
    case 'AGENT2':
      return 'agent2';
    case 'STORE':
      return 'store';
    default:
      return entityType?.toLowerCase() ?? 'unknown';
  }
}
