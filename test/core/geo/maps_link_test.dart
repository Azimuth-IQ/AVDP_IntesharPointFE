import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/geo/maps_link.dart';

/// B-131: onboarding a POS now accepts a pasted map link instead of pinning on
/// a map. These assert the shapes people actually paste, and — more importantly
/// — that ambiguous input yields NOTHING rather than a plausible wrong pin.
/// A silently wrong shop location is worse than an empty field.
void main() {
  group('formats that must work', () {
    test('Google map view (@lat,lng,zoom)', () {
      final r = parseLatLngFromMapsLink('https://www.google.com/maps/@33.3152,44.3661,15z')!;
      expect(r.latitude, closeTo(33.3152, 1e-9));
      expect(r.longitude, closeTo(44.3661, 1e-9));
    });

    test('Google query link', () {
      final r = parseLatLngFromMapsLink('https://maps.google.com/?q=33.3152,44.3661')!;
      expect(r.latitude, closeTo(33.3152, 1e-9));
    });

    test('Google place link — the @ viewport is the pin, not the search text', () {
      // A place URL carries both; taking `q=` would land on the search term.
      final r = parseLatLngFromMapsLink(
          'https://www.google.com/maps/place/Shop/@33.3152,44.3661,17z/data=!3m1')!;
      expect(r.latitude, closeTo(33.3152, 1e-9));
      expect(r.longitude, closeTo(44.3661, 1e-9));
    });

    test('Apple maps ll=', () {
      final r = parseLatLngFromMapsLink('https://maps.apple.com/?ll=33.3152,44.3661&z=16')!;
      expect(r.longitude, closeTo(44.3661, 1e-9));
    });

    test('a bare pair typed by hand', () {
      final r = parseLatLngFromMapsLink('33.3152, 44.3661')!;
      expect(r.latitude, closeTo(33.3152, 1e-9));
    });

    test('negative coordinates', () {
      final r = parseLatLngFromMapsLink('https://maps.google.com/?q=-33.86,-151.2')!;
      expect(r.latitude, closeTo(-33.86, 1e-9));
      expect(r.longitude, closeTo(-151.2, 1e-9));
    });

    test('surrounding whitespace is tolerated', () {
      expect(parseLatLngFromMapsLink('  33.3,44.3  '), isNotNull);
    });
  });

  group('input that must NOT produce a pin', () {
    test('empty or junk', () {
      for (final v in ['', '   ', 'hello', 'https://example.com/page']) {
        expect(parseLatLngFromMapsLink(v), isNull, reason: v);
      }
    });

    test('out-of-range values are not coordinates', () {
      expect(parseLatLngFromMapsLink('999.0, 44.0'), isNull);
      expect(parseLatLngFromMapsLink('33.0, 999.0'), isNull);
    });

    test('digits inside an unrelated URL are not a location', () {
      // The critical case: a URL full of ids and timestamps must not be mined
      // for any two numbers that happen to sit next to a comma.
      expect(
        parseLatLngFromMapsLink('https://example.com/track/12.5,99.9/id/778899'),
        isNull,
      );
    });

    test('a shortened link yields nothing, and is identified as shortened', () {
      const short = 'https://maps.app.goo.gl/AbCdEf123';
      expect(parseLatLngFromMapsLink(short), isNull);
      expect(isShortenedMapLink(short), isTrue,
          reason: 'so the operator is told to expand it, not that it is invalid');
    });

    test('a full link is not mistaken for a shortened one', () {
      expect(isShortenedMapLink('https://www.google.com/maps/@33.3,44.3,15z'), isFalse);
    });
  });
}
