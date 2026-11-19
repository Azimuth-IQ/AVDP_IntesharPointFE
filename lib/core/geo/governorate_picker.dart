import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/core/geo/governorates.dart';

String _locale(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

/// Single-select governorate dropdown that allows an explicit "no region lock"
/// (null) option — used when uploading vouchers (a null governorate = movable
/// anywhere).
class GovernorateDropdown extends StatelessWidget {
  final String? value; // governorate code, or null = not geo-locked
  final ValueChanged<String?> onChanged;
  final String? labelText;
  final String noneLabel; // label shown for the null option

  const GovernorateDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.noneLabel,
    this.labelText,
  });

  @override
  Widget build(BuildContext context) {
    final loc = _locale(context);
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: labelText),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(noneLabel)),
        ...kGovernorates.map(
          (g) => DropdownMenuItem<String?>(value: g.code, child: Text(g.label(loc))),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

/// PROD-015: where uploaded cards may be sold, as ONE dropdown — "كل المحافظات" first, then
/// Baghdad, then the other governorates ([kGovernorates] order, which starts with Baghdad). It
/// replaces a two-button choice followed by a second governorate list.
///
/// Nothing is pre-selected: an unanswered scope stays visibly unanswered (the import is blocked
/// until it is answered), because a silent "all governorates" would let every shop sell cards that
/// were meant for one region.
class SaleScopeDropdown extends StatelessWidget {
  /// The value standing for "all governorates" (region-free).
  static const all = '*';

  /// null = not answered yet; false = all governorates; true = [governorate] only.
  final bool? regionLocked;
  final String? governorate;
  final void Function(bool regionLocked, String? governorate) onChanged;
  final String? labelText;

  const SaleScopeDropdown({
    super.key,
    required this.regionLocked,
    required this.governorate,
    required this.onChanged,
    this.labelText,
  });

  /// The dropdown value for a scope, or null while unanswered.
  static String? valueFor(bool? regionLocked, String? governorate) =>
      regionLocked == null ? null : (regionLocked ? governorate : all);

  @override
  Widget build(BuildContext context) {
    final loc = _locale(context);
    final ar = loc == 'ar';
    final value = valueFor(regionLocked, governorate);
    return DropdownButtonFormField<String>(
      // The field keeps its own selection after the first build; keying it on the value makes a
      // reset from the page (e.g. after an upload) show up here too.
      key: ValueKey('sale-scope-$value'),
      initialValue: value,
      isExpanded: true,
      hint: Text(ar ? '— اختر نطاق البيع —' : '— Choose where these can be sold —'),
      decoration: InputDecoration(labelText: labelText),
      items: [
        DropdownMenuItem<String>(value: all, child: Text(ar ? 'كل المحافظات' : 'All governorates')),
        ...kGovernorates.map(
          (g) => DropdownMenuItem<String>(value: g.code, child: Text(g.label(loc))),
        ),
      ],
      onChanged: (v) {
        if (v == null) return;
        v == all ? onChanged(false, null) : onChanged(true, v);
      },
    );
  }
}

/// Multi-select governorate chips — used during agent onboarding to set the
/// governorates an entity operates in. When [allowedCodes] is non-null and
/// non-empty the choices are restricted to it (e.g. a Sub Agent may only cover
/// governorates within its parent Main Agent's coverage).
class GovernorateMultiSelect extends StatelessWidget {
  final Set<String> selected; // governorate codes
  final ValueChanged<Set<String>> onChanged;
  final Set<String>? allowedCodes;

  const GovernorateMultiSelect({
    super.key,
    required this.selected,
    required this.onChanged,
    this.allowedCodes,
  });

  @override
  Widget build(BuildContext context) {
    final loc = _locale(context);
    final options = (allowedCodes == null || allowedCodes!.isEmpty)
        ? kGovernorates
        : kGovernorates.where((g) => allowedCodes!.contains(g.code)).toList();
    return Wrap(
      spacing: IntesharSpacing.sm,
      runSpacing: IntesharSpacing.sm,
      children: options.map((g) {
        final on = selected.contains(g.code);
        return FilterChip(
          label: Text(g.label(loc)),
          selected: on,
          showCheckmark: true,
          selectedColor: context.tones.brand.withValues(alpha: 0.28),
          onSelected: (_) {
            final next = Set<String>.from(selected);
            if (on) {
              next.remove(g.code);
            } else {
              next.add(g.code);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }
}
