import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/entities/domain/entity_summary_row.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';

/// One selectable recipient in the new-transfer dialog (B-105, B-109).
///
/// A POS point is a different KIND of recipient from a sub-agent: money sent
/// there is spent at a counter, not passed further down the tree. The rows used
/// to differ only by a small grey icon, which read as one undifferentiated list,
/// so the tier now carries its own colour, a tinted badge and an explicit label.
///
/// The tier tint is BRAND vs INK — see [tintFor] for why it is no longer sage.
/// Colour is never the only carrier: the glyph (storefront vs building), the
/// spelled-out tier name and the selection check all stand on their own.
///
/// Extracted from the dialog so the distinction is testable rather than assumed
/// — the dialog itself needs a signed-in agent to reach.
class RecipientTile extends StatelessWidget {
  final EntitySummaryRow row;
  final bool selected;
  final VoidCallback onTap;

  const RecipientTile({
    super.key,
    required this.row,
    required this.selected,
    required this.onTap,
  });

  bool get isPos => row.type == EntityType.STORE;

  /// Localized tier name. Exposed for the test, which must be able to assert the
  /// row says what KIND of account it is in the user's own language.
  static String tierLabel(AppLocalizations l, EntityType t) => switch (t) {
        EntityType.INTESHAR => l.entityTypeInteshar,
        EntityType.AGENT1 => l.entityTypeAgent1,
        EntityType.AGENT2 => l.entityTypeAgent2,
        EntityType.STORE => l.entityTypeStore,
      };

  /// Brand for an agent, structural ink for a POS point.
  ///
  /// This used to be sage — but sage is this app's SEMANTIC "credit / money-in /
  /// available" colour in ~40 places, including the `+` amounts in this page's
  /// own grant ledger and the "after receiving" figure in the very dialog these
  /// rows live in. A green shop row therefore said "positive" where it only
  /// meant "shop". Ink is the palette's other structural anchor (it is
  /// `ColorScheme.tertiary` and the fill of every primary button), carries no
  /// money meaning, and — unlike sage — separates from brand gold on LUMINANCE
  /// (~8.5:1) rather than hue (gold vs sage is ~1.7:1, i.e. the two collapse for
  /// a red-green-deficient operator). Read from the scheme, not the constant, so
  /// it flips to bone in dark mode instead of vanishing into the charcoal.
  ///
  /// Exposed so a test can assert the two tiers never collapse to the same
  /// colour, and never collide with the money-in green.
  static Color tintFor(BuildContext context, EntityType type) {
    final cs = Theme.of(context).colorScheme;
    return type == EntityType.STORE ? cs.onSurface : cs.primary;
  }

  /// The same tier signal, but legible as a GLYPH or LABEL on a pale surface.
  ///
  /// [tintFor] is a fill colour: raw brand gold only ever appears here as a
  /// 12–20% wash. Drawn at full strength as a 16px icon or 11px text it lands at
  /// ~1.9:1 on its own badge, which is the B-078 failure the theme's `brandInk`
  /// exists to prevent. Ink needs no such correction, so a POS point is its own
  /// ink in both roles.
  static Color inkFor(BuildContext context, EntityType type) =>
      type == EntityType.STORE
          ? Theme.of(context).colorScheme.onSurface
          : context.tones.brandInk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = tintFor(context, row.type);
    final ink = inkFor(context, row.type);
    return ListTile(
      dense: true,
      selected: selected,
      // Selection is a STATE, not a tier — one brand wash for both lists. Tinting
      // it per tier would have washed a picked POS row light grey, which reads as
      // "disabled" on the one row the operator just chose to send money to.
      selectedTileColor: cs.primary.withValues(alpha: 0.12),
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: selected ? 0.20 : 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPos ? Icons.storefront_outlined : Icons.apartment_outlined,
          size: 16,
          color: ink,
        ),
      ),
      title: Text(
        row.label,
        overflow: TextOverflow.ellipsis,
        style: IntesharType.sans(14,
            color: cs.onSurface, w: selected ? FontWeight.w800 : FontWeight.w600),
      ),
      // Name the tier outright — with both lists behind one segment it must be
      // unambiguous which kind of account you just picked. Localized: the raw
      // enum label is English, which read as "Store" on an Arabic screen.
      subtitle: Text(
        tierLabel(AppLocalizations.of(context)!, row.type),
        style: IntesharType.sans(11,
            color: selected ? ink : cs.onSurfaceVariant,
            w: selected ? FontWeight.w700 : FontWeight.w500),
      ),
      // Ink, not the tier tint: a gold check on a gold-washed selected row is
      // ~1.9:1 against its own background. The check is the ONLY non-colour cue
      // that this row is the one being paid, so it gets maximum contrast.
      trailing: selected
          ? Icon(Icons.check_circle, size: 18, color: cs.onSurface)
          : null,
      onTap: onTap,
    );
  }
}
