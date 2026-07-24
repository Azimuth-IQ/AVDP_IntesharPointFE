import 'package:flutter/material.dart';
import 'package:inteshar/app/theme.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';
import 'package:inteshar/l10n/app_localizations.dart';
import 'package:inteshar/shared/widgets/design_system.dart';

/// Role chip. Each role gets a distinct brand-aligned tint.
class RoleBadge extends StatelessWidget {
  final EntityType type;
  const RoleBadge({super.key, required this.type});

  static Color colorFor(BuildContext context, EntityType type) {
    return switch (type) {
      EntityType.INTESHAR => context.tones.brandInk, // brand amber
      EntityType.AGENT1   => const Color(0xFF2C3A55),    // ink blue
      EntityType.AGENT2   => IntesharColors.oxblood,
      EntityType.STORE    => IntesharColors.sage,
    };
  }

  static String _labelFor(AppLocalizations l, EntityType type) {
    return switch (type) {
      EntityType.INTESHAR => l.entityTypeInteshar,
      EntityType.AGENT1   => l.entityTypeAgent1,
      EntityType.AGENT2   => l.entityTypeAgent2,
      EntityType.STORE    => l.entityTypeStore,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return StampPill(label: _labelFor(l, type), color: colorFor(context, type));
  }
}
