import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
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
  }
}
