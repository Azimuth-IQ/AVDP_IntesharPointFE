import 'dart:io';

/// Raw TCP to a LAN/WiFi thermal printer — no plugin, just a socket.
///
/// Port 9100 is the JetDirect convention: the printer treats the stream as a
/// print job, so our ESC/POS bytes go on the wire exactly as built.
class NetworkPrinter {
  static const defaultPort = 9100;

  static Future<void> send(
    String host,
    int port,
    List<int> bytes, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final socket = await Socket.connect(host, port, timeout: timeout);
    try {
      socket.add(bytes);
      await socket.flush();
      // Closing the instant flush() returns can cut the last packet on printers
      // with a slow input buffer; a short settle costs nothing per receipt.
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } finally {
      socket.destroy();
    }
  }

  /// Cheap reachability check used when adopting a remembered network printer,
  /// so a powered-off unit reads as "not connected" instead of failing mid-sale.
  static Future<bool> probe(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
