import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/api/keep_alive_io.dart';

void main() {
  // The POS home refreshes every 60 s. An idle timeout shorter than that (dart:io's
  // default is 15 s) means a new TLS connection — about 5 KB and a handshake of server
  // CPU — for every refresh of every terminal.
  test('idle connections outlive the 60-second POS refresh', () {
    expect(kConnectionIdleTimeout, greaterThan(const Duration(seconds: 60)));
    // The server (Caddy) drops idle connections after 5 minutes; the client must let go first.
    expect(kConnectionIdleTimeout, lessThan(const Duration(minutes: 5)));
  });

  test('the Dio adapter builds its HttpClient with that idle timeout', () {
    final dio = Dio();
    keepConnectionsAlive(dio);
    final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
    final client = adapter.createHttpClient!();
    expect(client.idleTimeout, kConnectionIdleTimeout);
    client.close(force: true);
  });
}
