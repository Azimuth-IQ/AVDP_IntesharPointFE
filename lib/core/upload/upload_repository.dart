import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/endpoints.dart';

/// Maps a [filename] extension to a MIME type string.
///
/// This is a pure function with no I/O — it can be tested in isolation.
/// Falls back to `application/octet-stream` for unknown or absent extensions.
String mimeTypeForFilename(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'svg' => 'image/svg+xml',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}

/// Thin wrapper around `POST /api/storage/upload` (multipart/form-data).
///
/// [uploadFile] posts [bytes] as a `file` part together with a `kind` form
/// field and returns the `url` string from the response envelope
/// `{status, message, data: {url}}`.  Throws [ApiException] (via
/// [ApiClient.unwrap]) on non-2xx responses or when the `url` key is absent.
///
/// If the backend is not configured for object storage it returns HTTP 503
/// with `{status:503, message:"Object storage not configured", data:null}` —
/// [ApiClient.unwrap] will surface this as an [ApiException] with the
/// server-supplied message.
class UploadRepository {
  const UploadRepository(this._api);
  final ApiClient _api;

  Future<String> uploadFile(
    Uint8List bytes,
    String filename,
    String kind,
  ) async {
    final mime = mimeTypeForFilename(filename);
    final parts = mime.split('/');
    final ct = DioMediaType(parts[0], parts[1]);

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: ct,
      ),
      'kind': kind,
    });

    final r = await _api.post(Endpoints.storageUpload, data: formData);
    return _api.unwrap(r, (d) => (d as Map)['url'] as String);
  }
}
