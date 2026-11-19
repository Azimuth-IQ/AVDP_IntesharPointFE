import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// PROD-010: the device's own position, for confirming a shop's location in one tap.
///
/// Returns null — never throws — whenever there is no usable position: location turned off,
/// permission refused, no fix within [timeout], or a platform without location. The caller then
/// falls back to picking the spot on the map by hand, exactly as before.
///
/// A fresh fix is asked for first; if none arrives in time, the last position the device knows is
/// used (indoor counters often see no satellites but have a recent network fix). [platform] is
/// injectable for tests.
Future<LatLng?> currentDeviceLocation({
  GeolocatorPlatform? platform,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final geo = platform ?? GeolocatorPlatform.instance;
  try {
    if (!await geo.isLocationServiceEnabled()) return null;
    var permission = await geo.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await geo.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return null;
    }
    Position? pos;
    try {
      pos = await geo
          .getCurrentPosition(
            locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
          )
          .timeout(timeout + const Duration(seconds: 2));
    } on TimeoutException {
      pos = null;
    }
    pos ??= await _lastKnown(geo);
    return pos == null ? null : LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
}

/// The last position the device knows of; null where the platform has none (the web).
Future<Position?> _lastKnown(GeolocatorPlatform geo) async {
  try {
    return await geo.getLastKnownPosition();
  } catch (_) {
    return null;
  }
}
