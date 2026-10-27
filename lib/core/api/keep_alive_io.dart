import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// How long an idle connection to the server stays open for reuse.
///
/// dart:io closes an idle connection after 15 s by default, so the POS home's 60-second
/// refresh (and most sales) opened a fresh TLS connection every time: about 5 KB of
/// handshake on top of a 3–4 KB refresh, and a handshake's worth of server CPU. Holding
/// the connection a little longer than the refresh interval lets it be reused instead.
/// The server (Caddy) keeps idle connections for 5 minutes, so it never closes first.
const Duration kConnectionIdleTimeout = Duration(seconds: 75);

/// Reuse connections across the POS refresh interval instead of reconnecting each time.
void keepConnectionsAlive(Dio dio) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()..idleTimeout = kConnectionIdleTimeout,
  );
}
