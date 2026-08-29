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
