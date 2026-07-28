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

  /// Sage for a POS point, brand for an agent. Exposed so a test can assert the
  /// two tiers never collapse to the same colour.
  static Color tintFor(BuildContext context, EntityType type) =>
      type == EntityType.STORE
          ? IntesharColors.sage
          : Theme.of(context).colorScheme.primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = tintFor(context, row.type);
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: tint.withValues(alpha: 0.12),
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
          color: tint,
        ),
      ),
      title: Text(
        row.label,
        overflow: TextOverflow.ellipsis,
        style: IntesharType.sans(13,
            color: cs.onSurface, w: selected ? FontWeight.w800 : FontWeight.w600),
      ),
      // Name the tier outright — with both lists behind one segment it must be
      // unambiguous which kind of account you just picked. Localized: the raw
      // enum label is English, which read as "Store" on an Arabic screen.
      subtitle: Text(
        tierLabel(AppLocalizations.of(context)!, row.type),
        style: IntesharType.sans(11,
            color: selected ? tint : cs.onSurfaceVariant,
            w: selected ? FontWeight.w700 : FontWeight.w500),
      ),
      trailing: selected ? Icon(Icons.check_circle, size: 18, color: tint) : null,
      onTap: onTap,
    );
  }
}
