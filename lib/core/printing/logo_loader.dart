import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

final _cache = <String, img.Image?>{};

/// Fetches a logo URL and decodes it to a thermal-friendly raster (resized to at most
/// [width] dots, grayscale) for ESC/POS printing. Returns null on ANY failure (no URL,
/// network error, undecodable) so the receipt prints fine without the logo. Cached by
/// URL so repeated prints don't re-fetch.
Future<img.Image?> loadReceiptLogo(String? url, {int width = 240}) async {
  if (url == null || url.trim().isEmpty) return null;
  final key = url.trim();
  if (_cache.containsKey(key)) return _cache[key];
  try {
    final resp = await Dio().get<List<int>>(
      key,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 6),
      ),
    );
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
    return _cache[key] = null;
  }
}
