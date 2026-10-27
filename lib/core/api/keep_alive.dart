// Web-safe shim: the real implementation uses dart:io (not available on web, where the
// browser owns connection reuse). Mirrors the project's core/files/web_download
// conditional-import pattern.
export 'keep_alive_stub.dart'
    if (dart.library.io) 'keep_alive_io.dart';
