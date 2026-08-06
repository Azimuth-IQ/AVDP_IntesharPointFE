/// B-131: pull coordinates out of a pasted map link.
///
/// Onboarding a POS asked the operator to pin the shop on a map, which is
/// awkward on a phone and impossible if they are not standing there. In practice
/// the location arrives as a link someone shared over WhatsApp, so accept that
/// directly.
///
/// This is only the optional ADD-time hint. The on-site confirmation that gates
/// selling (B-054, `EntityProfile.confirmedLatitude/Longitude`) is untouched —
/// a pasted link cannot satisfy it, and must not.
class LatLngPair {
  final double latitude;
  final double longitude;
  const LatLngPair(this.latitude, this.longitude);
}

/// Latitude −90..90, longitude −180..180. Anything outside is not a coordinate
/// pair, whatever it looked like.
bool _inRange(double lat, double lng) =>
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

/// Parses [input] into coordinates, or null when it carries none.
///
/// Handles what people actually paste:
/// * `https://www.google.com/maps/@33.31,44.36,15z`
/// * `https://maps.google.com/?q=33.31,44.36`
/// * `https://www.google.com/maps/place/Name/@33.31,44.36,17z/...`
/// * `https://maps.apple.com/?ll=33.31,44.36`
/// * a bare `33.31, 44.36`
///
/// Short links (`goo.gl/maps/...`, `maps.app.goo.gl/...`) resolve only by
/// following a redirect, so they return null rather than a wrong guess — the
/// caller tells the operator to open it and paste the expanded URL.
LatLngPair? parseLatLngFromMapsLink(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  // `@lat,lng` (Google's canonical map-view form) wins: a place URL carries both
  // an `@` viewport and often a `q=` search string, and the viewport is the pin.
  final at = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(text);
  if (at != null) {
    final lat = double.parse(at.group(1)!);
    final lng = double.parse(at.group(2)!);
    if (_inRange(lat, lng)) return LatLngPair(lat, lng);
  }

  // Query parameters: q=, ll=, query=, daddr=, sll=.
  final q = RegExp(
    r'[?&](?:q|ll|query|daddr|sll)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (q != null) {
    final lat = double.parse(q.group(1)!);
    final lng = double.parse(q.group(2)!);
    if (_inRange(lat, lng)) return LatLngPair(lat, lng);
  }

  // A bare pair, but ONLY when that is the whole string — otherwise the digits
  // inside an arbitrary URL (zoom levels, ids, timestamps) get read as a place.
  final bare = RegExp(r'^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$').firstMatch(text);
  if (bare != null) {
    final lat = double.parse(bare.group(1)!);
    final lng = double.parse(bare.group(2)!);
    if (_inRange(lat, lng)) return LatLngPair(lat, lng);
  }

  return null;
}

/// True for a shortened map link — parseable only by following the redirect.
/// Worth detecting so the operator gets "open it and paste the full link"
/// instead of a flat "not a valid location".
bool isShortenedMapLink(String input) {
  final t = input.trim().toLowerCase();
  return t.contains('goo.gl/maps') ||
      t.contains('maps.app.goo.gl') ||
      t.contains('bit.ly/');
}
