// Web-safe shim: the real implementation uses dart:io sockets (not available on
// web). Mirrors the project's core/files/web_download conditional-import pattern.
export 'network_printer_stub.dart'
    if (dart.library.io) 'network_printer_io.dart';
