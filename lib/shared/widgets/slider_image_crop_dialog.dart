import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:inteshar/app/theme.dart';

/// Spec cap for a POS home-slider image (also enforced server-side for the
/// `slider-image` storage kind).
const int kSliderImageMaxBytes = 1024 * 1024;

/// Slider images are downscaled to at most this width (16:9 → 1920×1080)
/// before JPEG encoding; at that size quality-stepping always lands under
/// [kSliderImageMaxBytes].
const int _kMaxWidth = 1920;

/// Crops [croppedBytes] output to a ≤1 MB JPEG: downscale to ≤1920 wide,
/// then step the quality down until the encoded size fits the cap.
///
/// Pure function over bytes — no I/O, no BuildContext.
Uint8List sliderJpegUnderCap(Uint8List croppedBytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(croppedBytes);
  } catch (_) {
    decoded = null; // normalized to the FormatException below
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) {
    throw const FormatException('Could not decode the cropped image');
  }
  if (decoded.width > _kMaxWidth) {
    decoded = img.copyResize(
      decoded,
      width: _kMaxWidth,
      interpolation: img.Interpolation.linear,
    );
  }
  for (final quality in const [90, 80, 70, 60, 50, 40]) {
    final out = img.encodeJpg(decoded, quality: quality);
    if (out.length <= kSliderImageMaxBytes) return Uint8List.fromList(out);
  }
  // A 1920-wide JPEG at quality 40 virtually never exceeds 1 MB; if some
  // pathological image does, half the resolution once and accept the result.
  decoded = img.copyResize(decoded, width: _kMaxWidth ~/ 2);
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 60));
}

/// Shows a modal 16:9 crop step for a freshly picked slider image.
///
/// Returns the cropped image re-encoded as a JPEG of at most 1 MB, or null
/// when the user cancels. The aspect ratio is locked to 16:9 per the POS
/// slider spec; the resulting bytes are ready for upload with the
/// `slider-image` storage kind.
Future<Uint8List?> showSliderImageCropDialog(
  BuildContext context,
  Uint8List original,
) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SliderCropDialog(original: original),
  );
}

class _SliderCropDialog extends StatefulWidget {
  const _SliderCropDialog({required this.original});

  final Uint8List original;

  @override
  State<_SliderCropDialog> createState() => _SliderCropDialogState();
}

class _SliderCropDialogState extends State<_SliderCropDialog> {
  final _controller = CropController();
  bool _processing = false;
  String? _error;

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        try {
          final jpeg = sliderJpegUnderCap(croppedImage);
          if (mounted) Navigator.of(context).pop(jpeg);
        } catch (e) {
          if (mounted) {
            setState(() {
              _processing = false;
              _error = e.toString();
            });
          }
        }
      case CropFailure(:final cause):
        if (mounted) {
          setState(() {
            _processing = false;
            _error = cause.toString();
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAr ? 'قصّ صورة الشريط (16:9)' : 'Crop slider image (16:9)',
                style: IntesharType.sans(
                  15,
                  color: cs.onSurface,
                  w: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isAr
                    ? 'اسحب وكبّر لضبط الإطار — تُحفظ الصورة أفقية بحجم ١ م.ب كحد أقصى.'
                    : 'Drag and zoom to frame the slide — saved landscape, 1 MB max.',
                style: IntesharType.sans(12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(IntesharRadii.sm),
                child: SizedBox(
                  height: 300,
                  child: Crop(
                    image: widget.original,
                    controller: _controller,
                    aspectRatio: 16 / 9,
                    baseColor: cs.surfaceContainerHighest,
                    onCropped: _onCropped,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: IntesharType.sans(12, color: cs.error)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _processing
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(isAr ? 'إلغاء' : 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _processing
                        ? null
                        : () {
                            setState(() {
                              _processing = true;
                              _error = null;
                            });
                            _controller.crop();
                          },
                    icon: _processing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.crop, size: 16),
                    label: Text(isAr ? 'قصّ واستخدام' : 'Crop & use'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
