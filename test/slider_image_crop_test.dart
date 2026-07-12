import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:inteshar/shared/widgets/slider_image_crop_dialog.dart';

void main() {
  test('sliderJpegUnderCap downscales oversize images to 1920 wide', () {
    final big = img.Image(width: 3840, height: 2160); // 4K 16:9
    final out = sliderJpegUnderCap(Uint8List.fromList(img.encodePng(big)));

    expect(out.length, lessThanOrEqualTo(kSliderImageMaxBytes));
    final decoded = img.decodeJpg(out);
    expect(decoded, isNotNull);
    expect(decoded!.width, 1920);
    expect(decoded.height, 1080);
  });

  test('sliderJpegUnderCap keeps small images at native resolution', () {
    final small = img.Image(width: 1280, height: 720);
    final out = sliderJpegUnderCap(Uint8List.fromList(img.encodePng(small)));

    expect(out.length, lessThanOrEqualTo(kSliderImageMaxBytes));
    final decoded = img.decodeJpg(out);
    expect(decoded, isNotNull);
    expect(decoded!.width, 1280);
    expect(decoded.height, 720);
  });

  test('sliderJpegUnderCap throws FormatException on undecodable bytes', () {
    expect(() => sliderJpegUnderCap(Uint8List(0)), throwsFormatException);
  });
}
