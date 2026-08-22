import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/core/api/endpoints.dart';
import 'package:inteshar/core/storage/session_storage.dart';

/// Is the server reachable? — derived from the traffic the app already makes.
///
/// UX-79. Every POS sale is a network round trip over an unreliable Iraqi mobile
/// link with a customer standing at the counter, and until this existed the only
/// way to discover the link was down was to tap Sell and wait out a 10 s connect
/// / 15 s receive timeout. Nothing in the app said a word.
///
/// There is deliberately **no connectivity plugin** here. A platform "has wifi"
/// flag answers the wrong question anyway (a captive portal, a dead backend and
/// an expired DNS entry all report "connected"); what the till actually needs to
/// know is whether *our server* answers. The API layer already sees that on
/// every request, for free.
///
/// The rule, in one sentence: **a request that could not open a connection to
/// the server means offline; any HTTP response at all — of any status — means
/// online.**

/// Strike total at which the app declares the link down.
const int kOfflineStrikes = 2;

/// How often the app re-probes the server while it believes it is offline.
const Duration kOfflineProbeInterval = Duration(seconds: 5);

/// How many strikes one failed request contributes.
///
/// The two families are not the same evidence:
///
/// * [DioExceptionType.connectionError] / [DioExceptionType.connectionTimeout] —
///   the socket never opened. There is nothing on the other end of the link, so
///   one of these is enough on its own ([kOfflineStrikes]).
/// * [DioExceptionType.sendTimeout] / [DioExceptionType.receiveTimeout] — we
///   *did* connect and the server then took too long. That is usually one slow
///   endpoint (a heavy report), not a dead link, so it takes two in a row.
///
/// Everything else — including [DioExceptionType.cancel] and
/// [DioExceptionType.badResponse] — is worth nothing: a false "offline" banner
/// on a working till is worse than no banner at all.
int strikeWeightFor(DioExceptionType type) => switch (type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout =>
        kOfflineStrikes,
      DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout => 1,
      _ => 0,
    };

@immutable
class ConnectivityState {
  /// Accumulated consecutive-failure weight; see [strikeWeightFor]. Reset to 0
  /// by any response, capped at [kOfflineStrikes] so recovery is always one
  /// successful round trip away.
  final int strikes;

  const ConnectivityState({this.strikes = 0});

  static const online = ConnectivityState();

  bool get offline => strikes >= kOfflineStrikes;

  @override
  bool operator ==(Object other) =>
      other is ConnectivityState && other.strikes == strikes;

  @override
  int get hashCode => strikes.hashCode;

  @override
  String toString() => 'ConnectivityState(strikes: $strikes, offline: $offline)';
}

/// Pure — no I/O. The next state after one completed request.
///
/// [reachedServer] is true when the server returned **any** HTTP status. A 500
/// and a 403 both prove the link is up, which is the only thing this decides.
ConnectivityState nextConnectivity(
  ConnectivityState current, {
  required bool reachedServer,
  DioExceptionType? errorType,
}) {
  if (reachedServer) return ConnectivityState.online;
  final weight = errorType == null ? 0 : strikeWeightFor(errorType);
  if (weight == 0) return current;
  final strikes = current.strikes + weight;
  return ConnectivityState(
    strikes: strikes > kOfflineStrikes ? kOfflineStrikes : strikes,
  );
}

/// Holds the derived signal and, **while offline only**, re-probes the server so
/// the banner clears on its own.
///
/// The probe matters: the app has no global poll, so on an idle screen a
/// recovered link would otherwise stay flagged as down until the operator
/// happened to touch something. It hits the *public* `GET /api/app/latest` on a
/// bare Dio with no interceptors — so it cannot be retried, cannot end the
/// session on a 401, and cannot feed itself another strike.
class ConnectivityController extends Notifier<ConnectivityState> {
  static final Dio _probeDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    sendTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  Timer? _probeTimer;

  @override
  ConnectivityState build() {
    ref.onDispose(_stopProbing);
    return ConnectivityState.online;
  }

  /// The server answered — with any status at all.
  void recordReachedServer() => _apply(nextConnectivity(state, reachedServer: true));

  /// The request never got a response. [errorType] decides how much that counts
  /// for; see [strikeWeightFor].
  void recordTransportFailure(DioExceptionType errorType) =>
      _apply(nextConnectivity(state, reachedServer: false, errorType: errorType));

  /// Probe now — the banner's "retry" affordance.
  Future<void> checkNow() => _probe();

  void _apply(ConnectivityState next) {
    if (next == state) return;
    final wasOffline = state.offline;
    state = next;
    if (next.offline && !wasOffline) {
      _startProbing();
    } else if (!next.offline && wasOffline) {
      _stopProbing();
    }
  }

  void _startProbing() {
    _probeTimer ??= Timer.periodic(kOfflineProbeInterval, (_) => _probe());
  }

  void _stopProbing() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  Future<void> _probe() async {
    try {
      final base = await sessionStorage.getBaseUrl();
      await _probeDio.get<dynamic>('$base${Endpoints.appLatest}');
      recordReachedServer();
    } on DioException catch (e) {
      // A 404/500 still proves the link is up — only a transport failure keeps
      // us offline, and the probe deliberately does NOT add strikes of its own.
      if (e.response != null) recordReachedServer();
    } catch (_) {
      // Still down. The timer will try again.
    }
  }
}

final connectivityProvider =
    NotifierProvider<ConnectivityController, ConnectivityState>(
  ConnectivityController.new,
);
