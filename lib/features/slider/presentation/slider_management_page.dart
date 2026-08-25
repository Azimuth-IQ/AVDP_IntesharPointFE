import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:inteshar/core/geo/governorate_picker.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/core/upload/upload_repository.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/slider/data/slider_repository.dart';
import 'package:inteshar/features/slider/domain/pos_slider.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/shared/widgets/error_state.dart';
import 'package:inteshar/shared/widgets/slider_image_crop_dialog.dart';

String _t(BuildContext c, String ar, String en) =>
    Localizations.localeOf(c).languageCode == 'ar' ? ar : en;

/// EntityType names that can be targeted, with bilingual labels.
const List<(String, String, String)> _tierOptions = [
  ('INTESHAR', 'المركز', 'HQ'),
  ('AGENT1', 'وكيل رئيسي', 'Main agent'),
  ('AGENT2', 'وكيل فرعي', 'Sub-agent'),
  ('STORE', 'متجر', 'Store'),
];

/// HQ-only standalone screen to manage POS-home slider images + targeting (B-022).
class SliderManagementPage extends ConsumerStatefulWidget {
  const SliderManagementPage({super.key});

  @override
  ConsumerState<SliderManagementPage> createState() => _SliderManagementPageState();
}

class _SliderManagementPageState extends ConsumerState<SliderManagementPage> {
  List<PosSlider>? _sliders;
  Object? _error;
  bool _loading = true;

  SliderRepository get _repo => SliderRepository(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.list();
      if (mounted) setState(() => _sliders = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditor({PosSlider? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SliderEditorSheet(existing: existing, nextOrder: _sliders?.length ?? 0),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleActive(PosSlider s) async {
    setState(() => _sliders = [
          for (final x in _sliders!) x.id == s.id ? x.copyWith(active: !x.active) : x
        ]);
    try {
      await _repo.update(s.id, s.copyWith(active: !s.active));
    } catch (e) {
      if (mounted) _snack(friendlyError(e, context));
      _load();
    }
  }

  Future<void> _delete(PosSlider s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(ctx, 'حذف الصورة؟', 'Delete slide?')),
        content: Text(_t(ctx, 'لا يمكن التراجع.', "This can't be undone.")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t(ctx, 'حذف', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(s.id);
      await _load();
    } catch (e) {
      if (mounted) _snack(friendlyError(e, context));
    }
  }

  Future<void> _move(int from, int to) async {
    final list = [..._sliders!];
    if (to < 0 || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    setState(() => _sliders = list);
    try {
      await _repo.reorder([for (final s in list) s.id]);
    } catch (e) {
      if (mounted) _snack(friendlyError(e, context));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        PageHeader(
          eyebrow: _t(context, 'نقاط البيع', 'POS'),
          title: _t(context, 'شريط الصور', 'Home slider'),
          subtitle: _t(context,
              'الصور التي تظهر على الشاشة الرئيسية لنقاط البيع، مع الاستهداف.',
              'Images shown on the POS home screen, with targeting.'),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(_t(context, 'إضافة صورة', 'Add slide')),
          ),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          ErrorState(error: _error!, onRetry: _load)
        else if ((_sliders ?? const []).isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
              child: Text(
                _t(context, 'لا توجد صور بعد — أضف واحدة.', 'No slides yet — add one.'),
                style: IntesharType.sans(13, color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          for (int i = 0; i < _sliders!.length; i++)
            _SliderRow(
              key: ValueKey(_sliders![i].id),
              slider: _sliders![i],
              audienceSummary: _audienceSummary(context, _sliders![i]),
              onToggle: () => _toggleActive(_sliders![i]),
              onEdit: () => _openEditor(existing: _sliders![i]),
              onDelete: () => _delete(_sliders![i]),
              onUp: i > 0 ? () => _move(i, i - 1) : null,
              onDown: i < _sliders!.length - 1 ? () => _move(i, i + 1) : null,
            ),
      ],
    );
  }

  String _audienceSummary(BuildContext c, PosSlider s) {
    final loc = Localizations.localeOf(c).languageCode;
    switch (s.audience) {
      case 'TIER':
        final labels = s.tierTypes.map((t) {
          final o = _tierOptions.where((x) => x.$1 == t);
          return o.isEmpty ? t : (loc == 'ar' ? o.first.$2 : o.first.$3);
        }).join('، ');
        return _t(c, 'الفئات: $labels', 'Tiers: $labels');
      case 'ENTITY':
        return _t(c, '${s.entityIds.length} جهة', '${s.entityIds.length} entities');
      case 'GOVERNORATE':
        final labels = s.governorates.map((g) => governorateLabel(g, loc)).join('، ');
        return _t(c, 'المحافظات: $labels', 'Governorates: $labels');
      default:
        return _t(c, 'كل نقاط البيع', 'All POS');
    }
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    super.key,
    required this.slider,
    required this.audienceSummary,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onUp,
    required this.onDown,
  });

  final PosSlider slider;
  final String audienceSummary;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(IntesharRadii.md),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final thumb = Opacity(
          opacity: slider.active ? 1 : 0.4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(IntesharRadii.sm),
            child: Image.network(
              slider.imageUrl,
              // UX-150: a slide has no name — the picture IS the slide, so an
              // unlabelled thumbnail leaves a screen-reader user with four
              // identical rows. The audience line is what distinguishes them.
              semanticLabel: audienceSummary,
              width: 84,
              height: 47, // ~16:9
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 84,
                height: 47,
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.broken_image_outlined, size: 20, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        );

        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(audienceSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: IntesharType.sans(12.5, color: cs.onSurface, w: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(slider.active ? _t(context, 'مُفعّلة', 'Active') : _t(context, 'مخفية', 'Hidden'),
                style: IntesharType.sans(11, color: cs.onSurfaceVariant)),
          ],
        );

        // UX-119: four adjacent icon buttons — one of them delete — used
        // `visualDensity: compact`, which drops the padded target from 48dp to
        // 40dp. At that size, on a row this dense, "move down" and "delete" are
        // two taps apart and one of them cannot be undone. Full-size targets
        // restored, plus tooltips so four bare glyphs are distinguishable.
        final actions = [
          // UX-150: the switch was the one control in this row of five with no
          // name at all — the four icon buttons at least got tooltips.
          Tooltip(
            message: slider.active
                ? _t(context, 'إخفاء الصورة', 'Hide slide')
                : _t(context, 'إظهار الصورة', 'Show slide'),
            child: Switch(value: slider.active, onChanged: (_) => onToggle()),
          ),
          IconButton(
              tooltip: _t(context, 'تحريك لأعلى', 'Move up'),
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: onUp),
          IconButton(
              tooltip: _t(context, 'تحريك لأسفل', 'Move down'),
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: onDown),
          IconButton(
              tooltip: _t(context, 'تعديل', 'Edit'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit),
          IconButton(
              tooltip: _t(context, 'حذف', 'Delete'),
              icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
              onPressed: onDelete),
        ];

        // The five controls need ~250dp at full size. Below that the row would
        // squeeze the summary text to nothing, so the actions move to their own
        // line rather than the targets shrinking back again.
        if (constraints.maxWidth < 420) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [thumb, const SizedBox(width: 12), Expanded(child: info)]),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ],
          );
        }
        return Row(
          children: [thumb, const SizedBox(width: 12), Expanded(child: info), ...actions],
        );
      }),
    );
  }
}

enum _Aud { all, tier, entity, governorate }

class _SliderEditorSheet extends ConsumerStatefulWidget {
  const _SliderEditorSheet({required this.existing, required this.nextOrder});
  final PosSlider? existing;
  final int nextOrder;

  @override
  ConsumerState<_SliderEditorSheet> createState() => _SliderEditorSheetState();
}

class _SliderEditorSheetState extends ConsumerState<_SliderEditorSheet> {
  String _imageUrl = '';
  bool _active = true;
  _Aud _aud = _Aud.all;
  final Set<String> _tiers = {};
  final Set<String> _entityIds = {};
  Set<String> _govs = {};

  bool _uploading = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _imageUrl = e.imageUrl;
      _active = e.active;
      _aud = switch (e.audience) {
        'TIER' => _Aud.tier,
        'ENTITY' => _Aud.entity,
        'GOVERNORATE' => _Aud.governorate,
        _ => _Aud.all,
      };
      _tiers.addAll(e.tierTypes);
      _entityIds.addAll(e.entityIds);
      _govs = e.governorates.toSet();
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() => _error = null);
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    } catch (e) {
      setState(() => _error = 'Could not open file picker: $e');
      return;
    }
    if (res == null || res.files.isEmpty) return;
    final bytes = res.files.first.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read file bytes');
      return;
    }
    if (!mounted) return;
    final cropped = await showSliderImageCropDialog(context, bytes);
    if (cropped == null) return; // cancelled
    setState(() => _uploading = true);
    try {
      final url = await UploadRepository(ref.read(apiClientProvider))
          .uploadFile(cropped, 'slide.jpg', 'slider-image');
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, context));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String? _validate() {
    if (_imageUrl.isEmpty) return _t(context, 'أضف صورة أولاً', 'Add an image first');
    switch (_aud) {
      case _Aud.tier:
        if (_tiers.isEmpty) return _t(context, 'اختر فئة واحدة على الأقل', 'Pick at least one tier');
      case _Aud.entity:
        if (_entityIds.isEmpty) return _t(context, 'اختر جهة واحدة على الأقل', 'Pick at least one entity');
      case _Aud.governorate:
        if (_govs.isEmpty) return _t(context, 'اختر محافظة واحدة على الأقل', 'Pick at least one governorate');
      case _Aud.all:
        break;
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final audience = switch (_aud) {
      _Aud.tier => 'TIER',
      _Aud.entity => 'ENTITY',
      _Aud.governorate => 'GOVERNORATE',
      _Aud.all => 'ALL',
    };
    final draft = PosSlider(
      id: widget.existing?.id ?? '',
      imageUrl: _imageUrl,
      active: _active,
      order: widget.existing?.order ?? widget.nextOrder,
      audience: audience,
      tierTypes: _aud == _Aud.tier ? _tiers.toList() : const [],
      entityIds: _aud == _Aud.entity ? _entityIds.toList() : const [],
      governorates: _aud == _Aud.governorate ? _govs.toList() : const [],
    );
    try {
      final repo = SliderRepository(ref.read(apiClientProvider));
      if (_isEdit) {
        await repo.update(widget.existing!.id, draft);
      } else {
        await repo.create(draft);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyError(e, context);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasImg = _imageUrl.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(_isEdit ? _t(context, 'تعديل الصورة', 'Edit slide') : _t(context, 'إضافة صورة', 'Add slide'),
                style: IntesharType.sans(16, color: cs.onSurface, w: FontWeight.w800)),
            const SizedBox(height: 14),

            // Image (16:9 crop on upload)
            if (hasImg)
              ClipRRect(
                borderRadius: BorderRadius.circular(IntesharRadii.sm),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(_imageUrl,
                      // UX-150: the preview of the slide being edited.
                      semanticLabel: _t(context, 'معاينة الصورة', 'Slide preview'),
                      fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 10),
            if (_uploading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              OutlinedButton.icon(
                onPressed: _pickAndUpload,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(hasImg ? _t(context, 'تغيير الصورة', 'Change image') : _t(context, 'رفع صورة', 'Upload image')),
              ),
            const SizedBox(height: 14),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: Text(_t(context, 'مُفعّلة', 'Active'),
                  style: IntesharType.sans(13, color: cs.onSurface, w: FontWeight.w600)),
            ),
            const SizedBox(height: 8),

            Text(_t(context, 'العرض على', 'Show to'),
                style: IntesharType.sans(12, color: cs.onSurfaceVariant, w: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<_Aud>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _Aud.all, label: Text(_t(context, 'الكل', 'All'))),
                ButtonSegment(value: _Aud.tier, label: Text(_t(context, 'فئة', 'Tier'))),
                ButtonSegment(value: _Aud.entity, label: Text(_t(context, 'جهة', 'Entity'))),
                ButtonSegment(value: _Aud.governorate, label: Text(_t(context, 'محافظة', 'Governorate'))),
              ],
              selected: {_aud},
              onSelectionChanged: (sel) => setState(() => _aud = sel.first),
            ),
            if (_aud == _Aud.tier) _tierPicker(cs),
            if (_aud == _Aud.entity) _entityPicker(cs),
            if (_aud == _Aud.governorate) ...[
              const SizedBox(height: 12),
              GovernorateMultiSelect(
                selected: _govs,
                onChanged: (v) => setState(() => _govs = v),
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: IntesharType.sans(12.5, color: cs.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_t(context, 'حفظ', 'Save')),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _tierPicker(ColorScheme cs) {
    final loc = Localizations.localeOf(context).languageCode;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in _tierOptions)
            FilterChip(
              label: Text(loc == 'ar' ? o.$2 : o.$3),
              selected: _tiers.contains(o.$1),
              onSelected: (v) => setState(() => v ? _tiers.add(o.$1) : _tiers.remove(o.$1)),
            ),
        ],
      ),
    );
  }

  // Server-searched multi-select (B-023): the shared box replaces the old
  // download-every-entity checkbox list. Selection is an id set, so rows picked
  // under an earlier search stay selected while the visible page changes.
  Widget _entityPicker(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_entityIds.isNotEmpty) ...[
            Text(_t(context, 'المحدد: ${_entityIds.length}', 'Selected: ${_entityIds.length}'),
                style: IntesharType.sans(11.5, color: context.tones.brandInk, w: FontWeight.w700)),
            const SizedBox(height: 6),
          ],
          EntityMultiSearchList(
            repository: EntityRepository(ref.read(apiClientProvider)),
            selectedIds: _entityIds,
            onToggle: (id, sel) =>
                setState(() => sel ? _entityIds.add(id) : _entityIds.remove(id)),
          ),
        ],
      ),
    );
  }
}
