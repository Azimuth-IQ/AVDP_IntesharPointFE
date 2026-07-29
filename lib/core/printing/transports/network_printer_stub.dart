/// Web build: there are no raw TCP sockets in a browser, so a LAN printer is
/// unreachable by construction. Every call fails loudly rather than pretending.
class NetworkPrinter {
  /// The JetDirect convention every network thermal printer listens on.
  static const defaultPort = 9100;

  static Future<void> send(
    String host,
    int port,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    throw UnsupportedError('Network printing needs a TCP socket');
  }

  static Future<bool> probe(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async => false;
}
