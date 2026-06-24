// ignore_for_file: constant_identifier_names
import 'package:inteshar/features/entities/domain/entity_type.dart';

/// Fine-grained RBAC permissions an agency user may hold, mirroring the backend
/// `Auth/Models/Capability`. Each becomes a server authority (gates endpoints) and
/// is also used client-side to show/hide nav items and actions. The coarse
/// [UserRole] (ADMIN/USER) still applies on top.
enum Capability {
  /// Full control of the agency (the "شامل" admin); implies all others.
  AGENT_ADMIN,

  /// May create transactions / send vouchers (and balance) down the hierarchy.
  CREATE_TRANSACTIONS,

  /// May set/override card prices for self and sub-agents.
  MANAGE_PRICING,

  /// Read-only oversight: reports and activity monitoring.
  VIEW_REPORTS,

  /// May create and manage points of sale (stores) and transfers to them.
  MANAGE_POS,
}

extension CapabilityX on Capability {
  String get en => switch (this) {
        Capability.AGENT_ADMIN => 'Full admin',
        Capability.CREATE_TRANSACTIONS => 'Send vouchers',
        Capability.MANAGE_PRICING => 'Manage pricing',
        Capability.VIEW_REPORTS => 'View reports',
        Capability.MANAGE_POS => 'Manage POS',
      };

  String get ar => switch (this) {
        Capability.AGENT_ADMIN => 'مدير شامل',
        Capability.CREATE_TRANSACTIONS => 'إرسال الكروت',
        Capability.MANAGE_PRICING => 'إدارة الأسعار',
        Capability.VIEW_REPORTS => 'عرض التقارير',
        Capability.MANAGE_POS => 'إدارة نقاط البيع',
      };

  String label(String localeCode) =>
      localeCode.toLowerCase().startsWith('en') ? en : ar;
}

Capability? capabilityFromName(String? name) {
  if (name == null) return null;
  for (final c in Capability.values) {
    if (c.name == name) return c;
  }
  return null;
}

Set<Capability> capabilitiesFromJson(dynamic raw) {
  if (raw is! List) return <Capability>{};
  return raw
      .map((e) => capabilityFromName(e as String?))
      .whereType<Capability>()
      .toSet();
}

List<String> capabilitiesToJson(Set<Capability> caps) =>
    caps.map((c) => c.name).toList();

/// Whether [caps] (with [role]) grants an action requiring any of [required].
/// An ADMIN role or the AGENT_ADMIN capability satisfies everything.
bool hasAnyCapability(UserRole role, Set<Capability> caps, Set<Capability> required) {
  if (role == UserRole.ADMIN || caps.contains(Capability.AGENT_ADMIN)) return true;
  return required.any(caps.contains);
}

/// The four onboarding presets for a Main Agent's users (Excel "وكيل رئيسي" sheet):
/// one full admin + up to three specialized operators.
enum AgentUserPreset { admin, pricing, monitoring, pointsTransfer }

extension AgentUserPresetX on AgentUserPreset {
  UserRole get role =>
      this == AgentUserPreset.admin ? UserRole.ADMIN : UserRole.USER;

  Set<Capability> get capabilities => switch (this) {
        AgentUserPreset.admin => Capability.values.toSet(),
        AgentUserPreset.pricing => {
            Capability.MANAGE_PRICING,
            Capability.VIEW_REPORTS,
          },
        AgentUserPreset.monitoring => {Capability.VIEW_REPORTS},
        AgentUserPreset.pointsTransfer => {
            Capability.MANAGE_POS,
            Capability.CREATE_TRANSACTIONS,
            Capability.VIEW_REPORTS,
          },
      };

  String get en => switch (this) {
        AgentUserPreset.admin => 'Admin (full)',
        AgentUserPreset.pricing => 'Pricing',
        AgentUserPreset.monitoring => 'Monitoring',
        AgentUserPreset.pointsTransfer => 'Points & Transfer',
      };

  String get ar => switch (this) {
        AgentUserPreset.admin => 'مدير شامل',
        AgentUserPreset.pricing => 'الأسعار',
        AgentUserPreset.monitoring => 'المتابعة',
        AgentUserPreset.pointsTransfer => 'النقاط والتحويل',
      };

  String label(String localeCode) =>
      localeCode.toLowerCase().startsWith('en') ? en : ar;
}

/// Best-effort match of an existing capability set back to a named preset (for the
/// edit form). Returns null when the set doesn't match any preset exactly.
AgentUserPreset? presetForCapabilities(UserRole role, Set<Capability> caps) {
  for (final p in AgentUserPreset.values) {
    if (p.role == role && p.capabilities.length == caps.length &&
        p.capabilities.every(caps.contains)) {
      return p;
    }
  }
  return null;
}
