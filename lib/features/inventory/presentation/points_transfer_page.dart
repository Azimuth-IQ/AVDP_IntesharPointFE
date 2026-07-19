import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:inteshar/core/api/error_mapper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/api/api_client.dart';
import 'package:inteshar/core/geo/governorates.dart';
import 'package:inteshar/features/auth/application/auth_controller.dart';
import 'package:inteshar/features/entities/data/entity_repository.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/shared/widgets/entity_search_picker.dart';
import 'package:inteshar/features/inventory/data/product_repository.dart';
import 'package:inteshar/features/inventory/domain/sku_summary.dart';
import 'package:inteshar/shared/widgets/brand_cta.dart';
import 'package:inteshar/shared/widgets/design_system.dart';
import 'package:inteshar/shared/widgets/responsive.dart';
import 'package:inteshar/shared/widgets/role_badge.dart';

/// HQ-only stock reallocation. Picks a SOURCE entity and a DESTINATION entity,
/// a SKU + governorate bucket, and moves up to a chosen quantity of the source's
/// AVAILABLE, non-expired vouchers down (or, in "Withdraw" mode, back up) the
/// hierarchy via `POST /api/inventory/agent-transfer`. The reverse is the same
/// call with source/destination swapped, so "Withdraw" just flips the effective
/// direction. The available count for the chosen (SKU × governorate) bucket is
/// read from the existing `summaryByEntity` aggregation and caps the quantity.
class PointsTransferPage extends ConsumerStatefulWidget {
  const PointsTransferPage({super.key});

  @override
  ConsumerState<PointsTransferPage> createState() => _PointsTransferPageState();
}

class _PointsTransferPageState extends ConsumerState<PointsTransferPage> {
  EntitySummaryRow? _source;
  EntitySummaryRow? _destination;

  /// When true, stock flows DESTINATION → SOURCE (reclaim/reverse). The API call
  /// is the same endpoint with the source/destination ids swapped.
  bool _withdraw = false;

  /// Per-SKU summary of whichever entity is the EFFECTIVE source of the move.
  List<SkuSummary> _sourceSummary = [];
  String? _sku;
  String _gov = ''; // governorate code; '' = the untagged / region-free bucket
  int _qty = 1;

  bool _loadingSummary = false;
  bool _submitting = false;
  String? _error;
  int? _movedResult;

  /// The entity stock actually leaves: the destination in withdraw mode.
  EntitySummaryRow? get _effectiveSource => _withdraw ? _destination : _source;

  /// The entity stock actually arrives at: the source in withdraw mode.
  EntitySummaryRow? get _effectiveDest => _withdraw ? _source : _destination;

  @override
  void initState() {
    super.initState();
    // Default the source to the signed-in entity; the destination is picked via
    // server search (B-023: no more downloading every entity to preselect one).
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is AuthAuthenticated) {
      final me = auth.entity;
      _source = EntitySummaryRow(
        id: me.id,
        name: me.meta.name,
        type: me.type,
      );
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    await _loadSummary();
  }

  /// Loads the EFFECTIVE source's per-SKU summary and reconciles the current
  /// (SKU × governorate) selection against it.
  Future<void> _loadSummary() async {
    final src = _effectiveSource;
    if (src == null) {
      setState(() {
        _sourceSummary = [];
        _sku = null;
        _gov = '';
        _qty = 1;
      });
      return;
    }
    setState(() => _loadingSummary = true);
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final summary = await repo.summaryByEntity(src.id);
      if (!mounted) return;
      setState(() {
        _sourceSummary = summary;
        _reconcileSelection();
        _loadingSummary = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, context);
          _sourceSummary = [];
          _sku = null;
          _gov = '';
          _loadingSummary = false;
        });
      }
    }
  }

  // ── Selection helpers ───────────────────────────────────────────────────────

  SkuSummary? get _currentSku {
    for (final s in _sourceSummary) {
      if (s.sku == _sku) return s;
    }
    return null;
  }

  /// Governorate buckets to offer for [s]. Synthesizes a single untagged bucket
  /// from the SKU-level counts when the backend returns no breakdown.
  List<GovBucket> _govBuckets(SkuSummary s) {
    if (s.governorates.isNotEmpty) return s.governorates;
    return [GovBucket(total: s.total, available: s.available)];
  }

  /// Available units in the chosen (SKU × governorate) bucket.
  int get _available {
    final s = _currentSku;
    if (s == null) return 0;
    for (final b in _govBuckets(s)) {
      if (b.governorate == _gov) return b.available;
    }
    return 0;
  }

  /// Keeps the current SKU/governorate when still present after a reload; else
  /// falls back to the first bucket with stock. Clamps the quantity.
  void _reconcileSelection() {
    if (_sourceSummary.isEmpty) {
      _sku = null;
      _gov = '';
      _qty = 1;
      return;
    }
    var cur = _currentSku;
    if (cur == null) {
      cur = _sourceSummary.firstWhere(
        (s) => s.available > 0,
        orElse: () => _sourceSummary.first,
      );
      _sku = cur.sku;
    }
    final buckets = _govBuckets(cur);
    if (!buckets.any((b) => b.governorate == _gov)) {
      final firstAvail = buckets.firstWhere(
        (b) => b.available > 0,
        orElse: () => buckets.first,
      );
      _gov = firstAvail.governorate;
    }
    if (_qty > _available) _qty = _available > 0 ? _available : 1;
  }

  Future<void> _pickSource() async {
    final picked = await showEntitySearchPicker(
      context,
      repository: EntityRepository(ref.read(apiClientProvider)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _source = picked;
      _movedResult = null;
    });
    _loadSummary();
  }

  Future<void> _pickDestination() async {
    final picked = await showEntitySearchPicker(
      context,
      repository: EntityRepository(ref.read(apiClientProvider)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _destination = picked;
      _movedResult = null;
    });
    _loadSummary();
  }

  void _onModeChanged(bool withdraw) {
    if (withdraw == _withdraw) return;
    setState(() {
      _withdraw = withdraw;
      _movedResult = null;
    });
    _loadSummary();
  }

  void _onSkuChanged(String? sku) {
    if (sku == null) return;
    setState(() {
      _sku = sku;
      _movedResult = null;
      final s = _currentSku;
      if (s != null) {
        final buckets = _govBuckets(s);
        final firstAvail = buckets.firstWhere(
          (b) => b.available > 0,
          orElse: () => buckets.first,
        );
        _gov = firstAvail.governorate;
      }
      _qty = _available > 0 ? 1 : 0;
    });
  }

  void _onGovChanged(String? gov) {
    setState(() {
      _gov = gov ?? '';
      _movedResult = null;
      _qty = _available > 0 ? 1 : 0;
    });
  }

  bool get _canSubmit =>
      !_submitting &&
      _effectiveSource != null &&
      _effectiveDest != null &&
      _effectiveSource!.id != _effectiveDest!.id &&
      _sku != null &&
      _qty > 0 &&
      _qty <= _available;

  Future<void> _submit() async {
    final src = _effectiveSource;
    final dst = _effectiveDest;
    if (!_canSubmit || src == null || dst == null || _sku == null) return;
    setState(() {
      _submitting = true;
      _error = null;
      _movedResult = null;
    });
    try {
      final repo = ProductRepository(ref.read(apiClientProvider));
      final moved = await repo.agentTransfer(
        sourceId: src.id,
        destinationId: dst.id,
        sku: _sku!,
        governorate: _gov.isEmpty ? null : _gov,
        amount: _qty,
      );
      if (!mounted) return;
      setState(() {
        _movedResult = moved;
        _submitting = false;
      });
      // Refresh the source pool so the available count reflects the move.
      await _loadSummary();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e, context);
          _submitting = false;
        });
      }
    }
  }

  bool get _isAr => Localizations.localeOf(context).languageCode == 'ar';

  @override
  Widget build(BuildContext context) {
    final isAr = _isAr;
    return MaxWidthBox(
      maxWidth: 820,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          PageHeader(
            eyebrow: isAr ? 'المخزون' : 'Inventory',
            title: isAr ? 'إعادة توزيع المخزون' : 'Stock Reallocation',
            subtitle: isAr
                ? 'انقل الكروت المتاحة بين الجهات، أو اعكس تحويلًا سابقًا (سحب).'
                : 'Move available vouchers between entities, or reverse a transfer (withdraw).',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ModeToggle(withdraw: _withdraw, onChanged: _onModeChanged),
                const SizedBox(height: 16),
                _RouteRow(
                  source: _source,
                  destination: _destination,
                  withdraw: _withdraw,
                  onSourceTap: _pickSource,
                  onDestinationTap: _pickDestination,
                ),
                const SizedBox(height: 20),
                SectionLabel(isAr ? 'المنتج والمنطقة' : 'Product & region'),
                _buildSkuGovPickers(),
                const SizedBox(height: 16),
                _buildQuantity(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _Banner(
                    icon: Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    text: _error!,
                  ),
                ],
                if (_movedResult != null) ...[
                  const SizedBox(height: 16),
                  _Banner(
                    icon: _movedResult! > 0
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: _movedResult! > 0
                        ? IntesharColors.sage
                        : IntesharColors.saffronDeep,
                    text: _movedResult! > 0
                        ? (isAr
                              ? 'تم نقل $_movedResult كرت بنجاح.'
                              : 'Moved $_movedResult voucher(s) successfully.')
                        : (isAr
                              ? 'لم يتم نقل أي كرت — لا يوجد مخزون مطابق متاح.'
                              : 'Nothing moved — no matching available stock.'),
                  ),
                ],
                const SizedBox(height: 22),
                BrandCTAButton(
                  label: _submitting
                      ? (isAr ? 'جارٍ النقل…' : 'Moving…')
                      : _withdraw
                      ? (isAr ? 'سحب المخزون' : 'Withdraw stock')
                      : (isAr ? 'نقل المخزون' : 'Transfer stock'),
                  leading: _submitting
                      ? null
                      : (_withdraw ? Icons.move_up : Icons.move_down),
                  loading: _submitting,
                  onPressed: _canSubmit ? _submit : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkuGovPickers() {
    final cs = Theme.of(context).colorScheme;
    final isAr = _isAr;
    if (_loadingSummary) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_sourceSummary.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          isAr
              ? 'لا يوجد مخزون لدى الجهة المصدر المحددة.'
              : 'The selected source holds no inventory.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    final loc = Localizations.localeOf(context).languageCode;
    final skuItems = _sourceSummary
        .map(
          (s) => DropdownMenuItem(
            value: s.sku,
            child: Text(
              '${s.name.isEmpty ? s.sku : s.name} (${s.sku}) · ${s.available}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    final current = _currentSku;
    final buckets = current != null ? _govBuckets(current) : <GovBucket>[];
    final govValue = buckets.any((b) => b.governorate == _gov)
        ? _gov
        : (buckets.isNotEmpty ? buckets.first.governorate : '');
    final govItems = buckets
        .map(
          (b) => DropdownMenuItem(
            value: b.governorate,
            child: Text(
              '${b.governorate.isEmpty ? (isAr ? 'غير محدد' : 'Untagged') : governorateLabel(b.governorate, loc)} · ${b.available}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList();

    return LayoutBuilder(
      builder: (ctx, c) {
        final stacked = c.maxWidth < 520;
        final skuField = DropdownButtonFormField<String>(
          initialValue: _sku,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: isAr ? 'المنتج (SKU)' : 'Product (SKU)',
            isDense: true,
          ),
          items: skuItems,
          onChanged: _onSkuChanged,
        );
        final govField = DropdownButtonFormField<String>(
          initialValue: govValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: isAr ? 'المحافظة' : 'Governorate',
            isDense: true,
          ),
          items: govItems,
          onChanged: govItems.isEmpty ? null : _onGovChanged,
        );
        if (stacked) {
          return Column(
            children: [skuField, const SizedBox(height: 12), govField],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: skuField),
            const SizedBox(width: 12),
            Expanded(child: govField),
          ],
        );
      },
    );
  }

  Widget _buildQuantity() {
    final cs = Theme.of(context).colorScheme;
    final isAr = _isAr;
    final available = _available;
    final over = _qty > available;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: TextFormField(
            // Re-seed the field whenever the bucket (or direction) changes.
            key: ValueKey('qty-${_effectiveSource?.id}-$_sku-$_gov-$_withdraw'),
            initialValue: _qty.toString(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: IntesharType.mono(14, color: cs.onSurface),
            decoration: InputDecoration(
              labelText: isAr ? 'الكمية' : 'Quantity',
              isDense: true,
              helperText: isAr ? 'المتاح: $available' : '$available available',
              helperMaxLines: 1,
              errorText: over
                  ? (isAr
                        ? 'المتاح فقط $available'
                        : 'Only $available available')
                  : null,
              errorMaxLines: 2,
            ),
            onChanged: (v) => setState(() {
              _qty = int.tryParse(v) ?? 0;
              _movedResult = null;
            }),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(IntesharRadii.sm),
            ),
            child: Row(
              children: [
                Icon(
                  _withdraw ? Icons.move_up : Icons.move_down,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _directionSentence(),
                    style: IntesharType.sans(12.5, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _directionSentence() {
    final isAr = _isAr;
    final from = _effectiveSource;
    final to = _effectiveDest;
    if (from == null || to == null) {
      return isAr ? 'اختر الجهتين.' : 'Pick both entities.';
    }
    if (from.id == to.id) {
      return isAr
          ? 'يجب أن تختلف الجهة المصدر عن الوجهة.'
          : 'Source and destination must differ.';
    }
    return isAr
        ? 'من ${from.label} إلى ${to.label}'
        : 'From ${from.label} to ${to.label}';
  }
}

// ── Mode toggle (Transfer / Withdraw) ─────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final bool withdraw;
  final ValueChanged<bool> onChanged;
  const _ModeToggle({required this.withdraw, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: false,
          icon: const Icon(Icons.move_down, size: 18),
          label: Text(isAr ? 'نقل' : 'Transfer'),
        ),
        ButtonSegment(
          value: true,
          icon: const Icon(Icons.move_up, size: 18),
          label: Text(isAr ? 'سحب' : 'Withdraw'),
        ),
      ],
      selected: {withdraw},
      onSelectionChanged: (sel) => onChanged(sel.first),
    );
  }
}

// ── Source / Destination route row ────────────────────────────────────────────

class _RouteRow extends StatelessWidget {
  final EntitySummaryRow? source;
  final EntitySummaryRow? destination;
  final bool withdraw;
  final VoidCallback onSourceTap;
  final VoidCallback onDestinationTap;
  const _RouteRow({
    required this.source,
    required this.destination,
    required this.withdraw,
    required this.onSourceTap,
    required this.onDestinationTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return LayoutBuilder(
      builder: (ctx, c) {
        final stacked = c.maxWidth < 560;
        final src = _EntityPicker(
          eyebrow: isAr ? 'المصدر' : 'Source',
          // In withdraw mode the source RECEIVES (stock returns to it).
          accent: withdraw ? IntesharColors.sage : cs.error,
          value: source,
          onTap: onSourceTap,
        );
        final dst = _EntityPicker(
          eyebrow: isAr ? 'الوجهة' : 'Destination',
          // In withdraw mode the destination is where stock LEAVES.
          accent: withdraw ? cs.error : IntesharColors.sage,
          value: destination,
          onTap: onDestinationTap,
        );
        // Arrow points to where stock ends up: source→dest normally, dest→source
        // (i.e. pointing back at the source) in withdraw mode.
        final arrow = Icon(
          withdraw ? Icons.west : Icons.east,
          color: cs.onSurfaceVariant,
        );
        if (stacked) {
          return Column(
            children: [
              src,
              const SizedBox(height: 10),
              Center(
                child: Icon(
                  withdraw ? Icons.north : Icons.south,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              dst,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: src),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: arrow,
            ),
            Expanded(child: dst),
          ],
        );
      },
    );
  }
}

class _EntityPicker extends StatelessWidget {
  final String eyebrow;
  final Color accent;
  final EntitySummaryRow? value;
  final VoidCallback onTap;
  const _EntityPicker({
    required this.eyebrow,
    required this.accent,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return InkCard(
      ruleColor: accent,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: IntesharType.overline(color: accent),
              ),
              const Spacer(),
              if (value != null) RoleBadge(type: value!.type),
            ],
          ),
          const SizedBox(height: 10),
          // Server-searched selection (B-023): tapping opens the type-to-search
          // picker instead of a dropdown fed by downloading every entity.
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(IntesharRadii.sm),
            child: InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                suffixIcon: const Icon(Icons.search, size: 18),
              ),
              child: Text(
                value == null
                    ? (isAr ? 'اختر جهة…' : 'Pick an entity…')
                    : '${value!.label} · ${value!.type.label}',
                overflow: TextOverflow.ellipsis,
                style: value == null
                    ? IntesharType.sans(13.5, color: cs.onSurfaceVariant)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            value?.id ?? '—',
            style: IntesharType.mono(
              11,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Banner ────────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Banner({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(IntesharRadii.sm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: cs.onSurface)),
          ),
        ],
      ),
    );
  }
}
