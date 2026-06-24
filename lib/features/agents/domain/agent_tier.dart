import 'package:inteshar/features/entities/domain/entity_type.dart';

/// The two admin-managed agent tiers. Drives the shared agents directory/form so
/// Main Agents (AGENT1) and Sub Agents (AGENT2) reuse one implementation with the
/// Excel-specified differences: a Sub Agent belongs to a Main Agent, has a single
/// user, and cannot set prices.
enum AgentTier { main, sub }

extension AgentTierX on AgentTier {
  EntityType get entityType =>
      this == AgentTier.main ? EntityType.AGENT1 : EntityType.AGENT2;

  String get typeName => entityType.name; // 'AGENT1' | 'AGENT2'

  /// Max users on the entity: a Main Agent has 1 admin + up to 3 operators; a Sub
  /// Agent has a single admin user. (Also enforced server-side in EntityHelper.)
  int get maxUsers => this == AgentTier.main ? 4 : 1;

  /// Sub Agents cannot price cards (Excel) — only Main Agents may hold MANAGE_PRICING.
  bool get allowPricing => this == AgentTier.main;

  /// A Sub Agent must be assigned to a parent Main Agent; a Main Agent's parent is HQ.
  bool get requiresParentPicker => this == AgentTier.sub;
}
