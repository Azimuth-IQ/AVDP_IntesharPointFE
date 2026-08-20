import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:inteshar/app/theme.dart';

/// Parse a `#RRGGBB` hex string to a [Color] (null on failure / wrong length).
Color? colorFromHex(String raw) {
  final clean = raw.trim().replaceAll('#', '');
  if (clean.length != 6) return null;
  final v = int.tryParse(clean, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

/// A [Color] back to an uppercase `#RRGGBB` string (alpha dropped).
String hexFromColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// A brand-colour field: the manual `#RRGGBB` text input PLUS a tappable swatch
/// that opens a colour WHEEL. Picking from the wheel writes the hex back into
/// [controller]; the swatch always mirrors the current text — the two stay in sync,
/// and the user can still type a hex by hand.
class ColorHexField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  const ColorHexField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
  });

  Future<void> _openWheel(BuildContext context) async {
    final start = colorFromHex(controller.text) ?? const Color(0xFFE2AD25);
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) {
        var temp = start;
        return AlertDialog(
          title: Text(label),
          content: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (ctx, setLocal) => HueRingPicker(
                pickerColor: temp,
                onColorChanged: (c) => setLocal(() => temp = c),
                enableAlpha: false,
                displayThumbColor: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, temp),
              child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
            ),
          ],
        );
      },
    );
    if (picked != null) controller.text = hexFromColor(picked);
  }

  /// Live read-out of what this brand does to a CTA label (UX-143).
  ///
  /// Whoever picks the colour is the only person who can see the damage before
  /// it ships: the choice re-tints every button in that agent's whole subtree,
  /// and a mid-tone brand can leave the label at ~2.8:1 with nothing on screen
  /// to say so. Always rendered (a placeholder when the hex is incomplete) so
  /// two fields sitting side by side keep the same height.
  Widget _preview(BuildContext context, ColorScheme cs) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final color = colorFromHex(controller.text);
    if (color == null) {
      return Text(
        '#RRGGBB',
        style: IntesharType.sans(11.5, color: cs.onSurfaceVariant),
      );
    }
    final onBrand = legibleOn(color);
    final ratio = contrastRatio(onBrand, color);
    // AA for the 15px w800 CTA label; below it the button is a guess, not a read.
    final ok = ratio >= 4.5;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isAr ? 'زر' : 'Button',
            style: IntesharType.sans(11.5, color: onBrand, w: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${ratio.toStringAsFixed(1)}:1 · '
            '${ok ? (isAr ? 'مقروء' : 'legible') : (isAr ? 'تباين ضعيف' : 'low contrast')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IntesharType.sans(
              11.5,
              color: ok ? cs.onSurfaceVariant : cs.error,
              w: ok ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final field = TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        // Tappable swatch → colour wheel. Rebuilds with the text so it mirrors
        // both manual edits and wheel picks.
        suffixIcon: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final color = colorFromHex(controller.text);
            return InkWell(
              onTap: () => _openWheel(context),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color ?? Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: cs.outline),
                  ),
                  child: color == null
                      ? Icon(Icons.colorize, size: 14, color: cs.onSurfaceVariant)
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => _preview(context, cs),
        ),
      ],
    );
  }
}
