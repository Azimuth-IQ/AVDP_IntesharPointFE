import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// B-106: the blob's MIME must match the file, or the download arrives as an
/// opaque byte stream and Excel reports "unknown format" (صيغة غير معروفة) even
/// though the bytes are a perfectly valid workbook. Inferred from the extension
/// so every caller gets it right without having to remember.
String _mimeFor(String filename) {
  final n = filename.toLowerCase();
  if (n.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (n.endsWith('.csv')) return 'text/csv';
  if (n.endsWith('.txt')) return 'text/plain';
  if (n.endsWith('.pdf')) return 'application/pdf';
  return 'application/octet-stream';
}

void downloadBytes(String filename, Uint8List bytes) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: _mimeFor(filename)),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
