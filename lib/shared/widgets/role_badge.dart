import 'package:flutter/material.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

class RoleBadge extends StatelessWidget {
  final EntityType type;
  const RoleBadge({super.key, required this.type});

  Color _color(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (type) {
      EntityType.INTESHAR => cs.primaryContainer,
      EntityType.AGENT1 => cs.secondaryContainer,
      EntityType.AGENT2 => cs.tertiaryContainer,
      EntityType.STORE => cs.surfaceContainerHighest,
    };
  }

  Color _fg(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (type) {
      EntityType.INTESHAR => cs.onPrimaryContainer,
      EntityType.AGENT1 => cs.onSecondaryContainer,
      EntityType.AGENT2 => cs.onTertiaryContainer,
      EntityType.STORE => cs.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          color: _fg(context),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
