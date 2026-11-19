import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:inteshar/core/geo/device_location.dart';

/// PROD-010: "as soon as I press, it should get my location". The shop-location button reads the
/// device's position; when there is none, it must fall back quietly to the map (never throw).
Position _at(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 11, 19),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _FakeGeo extends GeolocatorPlatform {
  _FakeGeo({
    this.serviceOn = true,
    this.permission = LocationPermission.whileInUse,
    this.afterRequest = LocationPermission.whileInUse,
    this.current,
    this.currentDelay = Duration.zero,
    this.last,
    this.throwOnCurrent = false,
  });

  final bool serviceOn;
  final LocationPermission permission;
  final LocationPermission afterRequest;
  final Position? current;
  final Duration currentDelay;
  final Position? last;
  final bool throwOnCurrent;
  int requests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceOn;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return afterRequest;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    if (throwOnCurrent) throw const LocationServiceDisabledException();
    await Future<void>.delayed(currentDelay);
    if (current == null) throw TimeoutException('no fix');
    return current!;
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async => last;
}

void main() {
  const baghdad = (33.3152, 44.3661);

  test('a fresh fix is returned', () async {
    final out = await currentDeviceLocation(platform: _FakeGeo(current: _at(baghdad.$1, baghdad.$2)));
    expect(out?.latitude, baghdad.$1);
    expect(out?.longitude, baghdad.$2);
  });

  test('asks for permission once when it has not been asked yet', () async {
    final geo = _FakeGeo(permission: LocationPermission.denied, current: _at(1, 2));
    expect(await currentDeviceLocation(platform: geo), isNotNull);
    expect(geo.requests, 1);
  });

  test('location turned off → null (the map opens instead)', () async {
    expect(await currentDeviceLocation(platform: _FakeGeo(serviceOn: false, current: _at(1, 2))), isNull);
  });

  test('permission refused, now or for good → null, no crash', () async {
    for (final p in [LocationPermission.denied, LocationPermission.deniedForever]) {
      final geo = _FakeGeo(permission: p, afterRequest: p, current: _at(1, 2));
      expect(await currentDeviceLocation(platform: geo), isNull, reason: '$p');
    }
  });

  test('no fresh fix in time (indoors) → the last known position', () async {
    final out = await currentDeviceLocation(
      platform: _FakeGeo(current: null, last: _at(30.5, 47.8)),
      timeout: const Duration(milliseconds: 10),
    );
    expect(out?.latitude, 30.5);
  });

  test('a fix that never arrives is cut off, not waited on forever', () async {
    final out = await currentDeviceLocation(
      platform: _FakeGeo(current: _at(1, 2), currentDelay: const Duration(seconds: 30), last: null),
      timeout: const Duration(milliseconds: 10),
    ).timeout(const Duration(seconds: 5));
    expect(out, isNull);
  });

  test('a platform error → null', () async {
    expect(await currentDeviceLocation(platform: _FakeGeo(throwOnCurrent: true)), isNull);
  });

  test('Android may ask for precise location (it was capped at API 30 for Bluetooth only)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>'));
    expect(manifest, contains('android.permission.ACCESS_COARSE_LOCATION'));
  });
}
