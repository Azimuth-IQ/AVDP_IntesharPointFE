import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/upload/upload_repository.dart';

/// A form field that shows a network image preview alongside an Upload button.
///
/// Tapping **Upload** (or **Change** when an image is already set) opens the
/// platform file picker filtered to images, uploads the selection to
/// `POST /api/storage/upload` with the given [kind], and calls [onChanged]
/// with the returned URL on success.
///
/// While the upload is in progress a compact spinner replaces the button.
/// On failure an inline error message appears below the row.
///
/// Works on web (uses `withData: true` so no filesystem path is needed) and
/// on mobile / desktop.
class ImageUploadField extends ConsumerStatefulWidget {
  const ImageUploadField({
    super.key,
    required this.value,
    required this.kind,
    required this.onChanged,
    this.label,
  });

  /// Current image URL; when non-empty a thumbnail preview is shown.
  final String? value;

  /// Storage kind forwarded to the backend (`agent-branding`, `product-image`,
  /// `kyc-doc`).
  final String kind;

  /// Called with the new URL once the upload completes successfully.
  final ValueChanged<String> onChanged;

  /// Optional label rendered above the field row.
  final String? label;

  @override
  ConsumerState<ImageUploadField> createState() => _ImageUploadFieldState();
}

/// A form field managing a **list** of uploaded image URLs.
///
/// Shows a wrap of thumbnails — each with an ✕ badge that removes it from the
/// selection — plus an **Add image** button that opens the platform file
/// picker (multi-select), uploads each pick to `POST /api/storage/upload`
/// with the given [kind], and appends the returned URLs via [onChanged].
///
/// While an upload is in progress a compact spinner replaces the button.
/// On failure an inline error message appears below the grid.
class MultiImageUploadField extends ConsumerStatefulWidget {
  const MultiImageUploadField({
    super.key,
    required this.values,
    required this.kind,
    required this.onChanged,
    this.label,
  });

  /// Current image URLs, one thumbnail each.
  final List<String> values;

  /// Storage kind forwarded to the backend (`agent-branding`, `product-image`,
  /// `kyc-doc`).
  final String kind;

  /// Called with the full updated list after every add/remove.
  final ValueChanged<List<String>> onChanged;

  /// Optional label rendered above the field.
  final String? label;

  @override
  ConsumerState<MultiImageUploadField> createState() =>
      _MultiImageUploadFieldState();
}

class _MultiImageUploadFieldState extends ConsumerState<MultiImageUploadField> {
  bool _uploading = false;
  String? _error;

  Future<void> _add() async {
    setState(() => _error = null);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: true,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;

    setState(() => _uploading = true);
    final repo = UploadRepository(ref.read(apiClientProvider));
    var current = List<String>.from(widget.values);
    try {
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        final url = await repo.uploadFile(bytes, file.name, widget.kind);
        // Report after each file so a mid-batch failure keeps the successes.
        current = [...current, url];
        if (!mounted) return;
        widget.onChanged(current);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removeAt(int index) {
    final next = List<String>.from(widget.values)..removeAt(index);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: IntesharType.sans(
              12,
              color: cs.onSurfaceVariant,
              w: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (widget.values.isNotEmpty) ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < widget.values.length; i++)
                _Thumb(
                  url: widget.values[i],
                  onRemove: () => _removeAt(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (_uploading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
            label: Text(isAr ? 'إضافة صورة' : 'Add image'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: IntesharType.sans(12, color: cs.error),
          ),
        ],
      ],
    );
  }
}

/// One 72×72 thumbnail with an ✕ badge on its top end corner.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(IntesharRadii.sm),
          child: Image.network(
            url,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(IntesharRadii.sm),
              ),
              child: Icon(
                Icons.broken_image_outlined,
                size: 24,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: -6,
          end: -6,
          child: Material(
            color: cs.errorContainer,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: cs.onErrorContainer,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageUploadFieldState extends ConsumerState<ImageUploadField> {
  bool _uploading = false;
  String? _error;

  Future<void> _pick() async {
    setState(() => _error = null);

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) setState(() => _error = 'Could not read file bytes');
      return;
    }

    setState(() => _uploading = true);
    try {
      final repo = UploadRepository(ref.read(apiClientProvider));
      final url = await repo.uploadFile(bytes, file.name, widget.kind);
      if (mounted) {
        setState(() => _uploading = false);
        widget.onChanged(url);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = friendlyError(e, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImage = (widget.value ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: IntesharType.sans(
              12,
              color: cs.onSurfaceVariant,
              w: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(IntesharRadii.sm),
                child: Image.network(
                  widget.value!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(IntesharRadii.sm),
                    ),
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 22,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (_uploading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: Text(hasImage ? 'Change' : 'Upload'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(
            _error!,
            style: IntesharType.sans(12, color: cs.error),
          ),
        ],
      ],
    );
  }
}
