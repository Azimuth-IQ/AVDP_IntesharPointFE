import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

final _cache = <String, img.Image?>{};

/// In-flight fetches, keyed by URL. Without this, a "print all" of ten cards
/// fired ten identical downloads for the same agent logo, each with its own
/// timeout, and every one of them sat in front of a receipt for a card that was
/// already sold.
final _inflight = <String, Future<img.Image?>>{};

/// A logo host that accepts the socket and then says nothing used to hang the
/// print for as long as it liked: there was no connect timeout at all and the
/// receive budget was six seconds.
final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 3),
  sendTimeout: const Duration(seconds: 3),
  receiveTimeout: const Duration(seconds: 3),
  responseType: ResponseType.bytes,
));

/// How long a print may wait on a logo it does not already hold. The card is
/// already sold by the time anything prints, so a decorative image gets a
/// budget, not a promise. See [receiptLogoForPrinting].
const Duration kReceiptLogoPrintBudget = Duration(milliseconds: 1200);

/// Fetches a logo URL and decodes it to a thermal-friendly raster (resized to at most
/// [width] dots, grayscale) for ESC/POS printing. Returns null on ANY failure (no URL,
/// network error, undecodable) so the receipt prints fine without the logo. Cached by
/// URL so repeated prints don't re-fetch, and de-duplicated while in flight.
///
/// This is the WARM-UP path — call it off the print's critical path (the POS warms
/// it the moment a card is drawn). Anything ON the print path must instead use
/// [receiptLogoForPrinting], which never waits longer than a budget.
Future<img.Image?> loadReceiptLogo(String? url, {int width = 240}) {
  if (url == null || url.trim().isEmpty) return Future.value(null);
  final key = url.trim();
  if (_cache.containsKey(key)) return Future.value(_cache[key]);
  final existing = _inflight[key];
  if (existing != null) return existing;
  final future = _fetch(key, width);
  _inflight[key] = future;
  return future.whenComplete(() => _inflight.remove(key));
}

/// The logo to put on a receipt that is about to print, without ever holding up
/// the paper (UX-59).
///
/// A cached logo comes back immediately. Otherwise the fetch is given [budget] —
/// if it has not landed by then the receipt prints WITHOUT the logo and the
/// download is left to finish in the background, so the next receipt gets it.
/// Never throws.
Future<img.Image?> receiptLogoForPrinting(
  String? url, {
  int width = 240,
  Duration budget = kReceiptLogoPrintBudget,
}) async {
  if (url == null || url.trim().isEmpty) return null;
  final key = url.trim();
  if (_cache.containsKey(key)) return _cache[key];
  try {
    // `timeout` abandons the WAIT, not the fetch: the request keeps running and
    // still populates the cache for the next receipt.
    return await loadReceiptLogo(key, width: width).timeout(budget);
  } catch (_) {
    return null;
  }
}

Future<img.Image?> _fetch(String key, int width) async {
  try {
    final resp = await _dio.get<List<int>>(key);
    final data = resp.data;
    if (data == null) return _cache[key] = null;
    var image = img.decodeImage(Uint8List.fromList(data));
    if (image == null) return _cache[key] = null;
    if (image.width > width) {
      image = img.copyResize(image, width: width);
    }
    image = img.grayscale(image);
    return _cache[key] = image;
  } catch (_) {
    // Cached as "no logo" for the run, exactly as before: a receipt must never
    // pay for the same failing download twice.
    return _cache[key] = null;
  }
}
