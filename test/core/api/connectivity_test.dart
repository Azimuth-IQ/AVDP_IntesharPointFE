import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/connectivity.dart';

/// The offline strip's trigger.
///
/// The asymmetry is the whole design: a false "offline" on a working till is
/// worse than no banner, because the operator stops trying to sell. So these
/// assert as hard on what must NOT raise it as on what must.
void main() {
  ConnectivityState after(List<DioExceptionType> failures) {
    var s = ConnectivityState.online;
    for (final f in failures) {
      s = ConnectivityState(
          strikes: (s.strikes + strikeWeightFor(f)).clamp(0, kOfflineStrikes));
    }
    return s;
  }

  group('what raises the strip', () {
    test('a socket that never opened is enough on its own', () {
      // Nothing on the other end of the link — no second opinion needed.
      expect(after([DioExceptionType.connectionError]).offline, isTrue);
      expect(after([DioExceptionType.connectionTimeout]).offline, isTrue);
    });

    test('one slow endpoint does not mean a dead link — two do', () {
      // We connected and the server was slow: usually a heavy report, not the
      // network. One is not evidence.
      expect(after([DioExceptionType.receiveTimeout]).offline, isFalse);
      expect(after([DioExceptionType.sendTimeout]).offline, isFalse);
      expect(
        after([DioExceptionType.receiveTimeout, DioExceptionType.sendTimeout])
            .offline,
        isTrue,
      );
    });
  });

  group('what must never raise it', () {
    test('an HTTP error is a REACHED server, not an unreachable one', () {
      // 401/403/409/500 all mean the link works. This is the case that would
      // put an offline banner over a till that is selling perfectly well.
      expect(strikeWeightFor(DioExceptionType.badResponse), 0);
      expect(after([DioExceptionType.badResponse]).offline, isFalse);
      expect(
        after(List.filled(20, DioExceptionType.badResponse)).offline,
        isFalse,
        reason: 'no number of server errors is evidence of a dead link',
      );
    });

    test('a cancelled request is the app changing its mind', () {
      expect(strikeWeightFor(DioExceptionType.cancel), 0);
      expect(after(List.filled(5, DioExceptionType.cancel)).offline, isFalse);
    });
  });

  group('recovery', () {
    test('is always one successful round trip away', () {
      // Strikes are capped, so a long outage cannot bury the recovery: whatever
      // happened, a single response clears it.
      final buried = after(List.filled(50, DioExceptionType.connectionError));
      expect(buried.strikes, kOfflineStrikes);
      expect(ConnectivityState.online.offline, isFalse);
    });

    test('a timeout does not linger below the threshold forever', () {
      // One slow call leaves a strike; the next response must clear it, or a
      // single heavy report would arm the banner for the rest of the session.
      final one = after([DioExceptionType.receiveTimeout]);
      expect(one.strikes, 1);
      expect(one.offline, isFalse);
      expect(ConnectivityState.online.strikes, 0);
    });
  });
}
