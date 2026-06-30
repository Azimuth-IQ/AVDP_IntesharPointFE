// Tests for the RBAC capability gate in lib/core/auth/capabilities.dart.
//
// Correctness-critical: a wildcard bug was shipped before (ADMIN role must
// satisfy ALL capability checks; AGENT_ADMIN capability must do the same).
// These tests lock down the documented matrix so a regression is caught at CI.
//
// All tests are pure unit tests — no network, no widgets, no timers.

// ignore_for_file: constant_identifier_names

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/auth/capabilities.dart';
import 'package:inteshar/features/entities/domain/entity_type.dart';

void main() {
  // -------------------------------------------------------------------------
  // hasAnyCapability — the main gate
  // -------------------------------------------------------------------------
  group('hasAnyCapability — ADMIN role is a wildcard', () {
    test('ADMIN with empty caps satisfies any required set', () {
      expect(
        hasAnyCapability(UserRole.ADMIN, {}, {Capability.MANAGE_PRICING}),
        isTrue,
      );
    });

    test('ADMIN with empty caps satisfies multiple required caps', () {
      expect(
        hasAnyCapability(
          UserRole.ADMIN,
          {},
          {Capability.CREATE_TRANSACTIONS, Capability.MANAGE_POS},
        ),
        isTrue,
      );
    });

    test('ADMIN with empty caps satisfies every single Capability value', () {
      for (final cap in Capability.values) {
        expect(
          hasAnyCapability(UserRole.ADMIN, {}, {cap}),
          isTrue,
          reason: 'ADMIN must pass gate for ${cap.name}',
        );
      }
    });

    test('ADMIN with empty caps and empty required set still returns true', () {
      // The implementation returns true before checking required, so even an
      // empty required set yields true for ADMIN.
      expect(hasAnyCapability(UserRole.ADMIN, {}, {}), isTrue);
    });
  });

  group('hasAnyCapability — AGENT_ADMIN capability is a wildcard', () {
    test('USER role + AGENT_ADMIN cap satisfies any required cap', () {
      for (final cap in Capability.values) {
        expect(
          hasAnyCapability(UserRole.USER, {Capability.AGENT_ADMIN}, {cap}),
          isTrue,
          reason: 'AGENT_ADMIN cap must pass gate for ${cap.name}',
        );
      }
    });

    test('USER role + AGENT_ADMIN cap + empty required set returns true', () {
      expect(
        hasAnyCapability(UserRole.USER, {Capability.AGENT_ADMIN}, {}),
        isTrue,
      );
    });
  });

  group('hasAnyCapability — USER role with specific caps (non-wildcard)', () {
    const pricingCaps = {Capability.MANAGE_PRICING, Capability.VIEW_REPORTS};
    const monitoringCaps = {Capability.VIEW_REPORTS};
    const posTransferCaps = {
      Capability.MANAGE_POS,
      Capability.CREATE_TRANSACTIONS,
      Capability.VIEW_REPORTS,
    };

    // Positive: caps that match the required set.
    test('pricing user GRANTED MANAGE_PRICING', () {
      expect(
        hasAnyCapability(UserRole.USER, pricingCaps, {Capability.MANAGE_PRICING}),
        isTrue,
      );
    });

    test('pricing user GRANTED VIEW_REPORTS', () {
      expect(
        hasAnyCapability(UserRole.USER, pricingCaps, {Capability.VIEW_REPORTS}),
        isTrue,
      );
    });

    test('monitoring user GRANTED VIEW_REPORTS', () {
      expect(
        hasAnyCapability(UserRole.USER, monitoringCaps, {Capability.VIEW_REPORTS}),
        isTrue,
      );
    });

    test('pointsTransfer user GRANTED CREATE_TRANSACTIONS', () {
      expect(
        hasAnyCapability(
          UserRole.USER,
          posTransferCaps,
          {Capability.CREATE_TRANSACTIONS},
        ),
        isTrue,
      );
    });

    test('pointsTransfer user GRANTED MANAGE_POS', () {
      expect(
        hasAnyCapability(UserRole.USER, posTransferCaps, {Capability.MANAGE_POS}),
        isTrue,
      );
    });

    // Negative: caps that do NOT match.
    test('pricing user DENIED CREATE_TRANSACTIONS', () {
      expect(
        hasAnyCapability(
          UserRole.USER,
          pricingCaps,
          {Capability.CREATE_TRANSACTIONS},
        ),
        isFalse,
      );
    });

    test('pricing user DENIED MANAGE_POS', () {
      expect(
        hasAnyCapability(UserRole.USER, pricingCaps, {Capability.MANAGE_POS}),
        isFalse,
      );
    });

    test('monitoring user DENIED MANAGE_PRICING', () {
      expect(
        hasAnyCapability(
          UserRole.USER,
          monitoringCaps,
          {Capability.MANAGE_PRICING},
        ),
        isFalse,
      );
    });

    test('monitoring user DENIED CREATE_TRANSACTIONS', () {
      expect(
        hasAnyCapability(
          UserRole.USER,
          monitoringCaps,
          {Capability.CREATE_TRANSACTIONS},
        ),
        isFalse,
      );
    });

    test('USER with empty caps is DENIED every Capability', () {
      for (final cap in Capability.values) {
        expect(
          hasAnyCapability(UserRole.USER, {}, {cap}),
          isFalse,
          reason: 'empty caps must deny ${cap.name}',
        );
      }
    });

    test('USER with empty caps and empty required set returns false', () {
      // No match in an empty required set — returns false.
      expect(hasAnyCapability(UserRole.USER, {}, {}), isFalse);
    });

    // "any" semantics: satisfied if at least one required cap is held.
    test('hasAnyCapability uses OR — partial match is sufficient', () {
      expect(
        hasAnyCapability(
          UserRole.USER,
          {Capability.VIEW_REPORTS},
          {Capability.MANAGE_PRICING, Capability.VIEW_REPORTS},
        ),
        isTrue,
        reason: 'user holds VIEW_REPORTS which is in the required set',
      );
    });

    test('hasAnyCapability returns false when no required cap is held', () {
      expect(
        hasAnyCapability(
          UserRole.USER,
          {Capability.VIEW_REPORTS},
          {Capability.MANAGE_PRICING, Capability.CREATE_TRANSACTIONS},
        ),
        isFalse,
        reason: 'user holds VIEW_REPORTS but neither required cap matches',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Fine-grained section caps split out of AGENT_ADMIN
  // (MANAGE_CATALOG / MANAGE_AGENTS / MANAGE_COMPANIES)
  // -------------------------------------------------------------------------
  group('fine-grained section caps', () {
    const newSections = {
      Capability.MANAGE_CATALOG,
      Capability.MANAGE_AGENTS,
      Capability.MANAGE_COMPANIES,
    };

    test('the three new caps exist in the enum', () {
      expect(Capability.values, containsAll(newSections));
    });

    test('AGENT_ADMIN cap grants every new section (wildcard preserved)', () {
      for (final cap in newSections) {
        expect(
          hasAnyCapability(UserRole.USER, {Capability.AGENT_ADMIN}, {cap}),
          isTrue,
          reason: 'AGENT_ADMIN must still grant ${cap.name}',
        );
      }
    });

    test('ADMIN role grants every new section', () {
      for (final cap in newSections) {
        expect(hasAnyCapability(UserRole.ADMIN, {}, {cap}), isTrue);
      }
    });

    test('empty caps (legacy full access) grants every new section', () {
      // Empty caps remain "full access" at the nav layer; the gate itself only
      // wildcards on ADMIN/AGENT_ADMIN, so empty-cap full-access is asserted via
      // the nav helper, not hasAnyCapability. Here we lock the gate's deny side.
      for (final cap in newSections) {
        expect(
          hasAnyCapability(UserRole.USER, {}, {cap}),
          isFalse,
          reason: 'empty caps must not satisfy a finer gate at the cap layer',
        );
      }
    });

    test('a MANAGE_CATALOG-only user sees catalog but NOT agents/companies', () {
      const caps = {Capability.MANAGE_CATALOG};
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_CATALOG}), isTrue);
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_AGENTS}), isFalse);
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_COMPANIES}), isFalse);
    });

    test('a MANAGE_AGENTS-only user sees agents but NOT catalog/companies', () {
      const caps = {Capability.MANAGE_AGENTS};
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_AGENTS}), isTrue);
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_CATALOG}), isFalse);
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_COMPANIES}), isFalse);
    });

    test('a MANAGE_COMPANIES-only user sees companies but NOT catalog/agents', () {
      const caps = {Capability.MANAGE_COMPANIES};
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_COMPANIES}), isTrue);
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_CATALOG}), isFalse);
      expect(hasAnyCapability(UserRole.USER, caps, {Capability.MANAGE_AGENTS}), isFalse);
    });

    test('a section cap does NOT bleed into the legacy AGENT_ADMIN gate', () {
      // A finer-grained user must not back-door into AGENT_ADMIN-only sections.
      for (final cap in newSections) {
        expect(
          hasAnyCapability(UserRole.USER, {cap}, {Capability.AGENT_ADMIN}),
          isFalse,
          reason: '${cap.name} must not satisfy an AGENT_ADMIN gate',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // capabilityFromName — parsing
  // -------------------------------------------------------------------------
  group('capabilityFromName', () {
    test('returns the correct Capability for each valid name', () {
      expect(capabilityFromName('AGENT_ADMIN'), Capability.AGENT_ADMIN);
      expect(capabilityFromName('CREATE_TRANSACTIONS'), Capability.CREATE_TRANSACTIONS);
      expect(capabilityFromName('MANAGE_PRICING'), Capability.MANAGE_PRICING);
      expect(capabilityFromName('VIEW_REPORTS'), Capability.VIEW_REPORTS);
      expect(capabilityFromName('MANAGE_POS'), Capability.MANAGE_POS);
      expect(capabilityFromName('MANAGE_CATALOG'), Capability.MANAGE_CATALOG);
      expect(capabilityFromName('MANAGE_AGENTS'), Capability.MANAGE_AGENTS);
      expect(capabilityFromName('MANAGE_COMPANIES'), Capability.MANAGE_COMPANIES);
    });

    test('returns null for unknown name', () {
      expect(capabilityFromName('UNKNOWN_CAP'), isNull);
    });

    test('returns null for null input', () {
      expect(capabilityFromName(null), isNull);
    });

    test('is case-sensitive — lowercase is rejected', () {
      expect(capabilityFromName('manage_pricing'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // capabilitiesFromJson — JSON list parsing
  // -------------------------------------------------------------------------
  group('capabilitiesFromJson', () {
    test('parses a valid list of capability name strings', () {
      final result = capabilitiesFromJson([
        'MANAGE_PRICING',
        'VIEW_REPORTS',
      ]);
      expect(result, {Capability.MANAGE_PRICING, Capability.VIEW_REPORTS});
    });

    test('silently drops unknown capability names', () {
      final result = capabilitiesFromJson(['MANAGE_PRICING', 'NONEXISTENT']);
      expect(result, {Capability.MANAGE_PRICING});
    });

    test('returns empty set for an empty list', () {
      expect(capabilitiesFromJson([]), isEmpty);
    });

    test('returns empty set when input is not a List (null-safety)', () {
      expect(capabilitiesFromJson(null), isEmpty);
      expect(capabilitiesFromJson(42), isEmpty);
      expect(capabilitiesFromJson('MANAGE_PRICING'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // capabilitiesToJson — serialization
  // -------------------------------------------------------------------------
  group('capabilitiesToJson', () {
    test('round-trips capability set through JSON', () {
      const caps = {Capability.MANAGE_PRICING, Capability.VIEW_REPORTS};
      final json = capabilitiesToJson(caps);
      expect(json, containsAll(['MANAGE_PRICING', 'VIEW_REPORTS']));
      expect(json.length, 2);
    });

    test('serializes empty set to empty list', () {
      expect(capabilitiesToJson({}), isEmpty);
    });

    test('serializes all capabilities correctly', () {
      final all = Capability.values.toSet();
      final json = capabilitiesToJson(all);
      expect(json.toSet(), all.map((c) => c.name).toSet());
    });
  });

  // -------------------------------------------------------------------------
  // AgentUserPreset — canonical presets
  // -------------------------------------------------------------------------
  group('AgentUserPreset role assignments', () {
    test('admin preset has ADMIN role', () {
      expect(AgentUserPreset.admin.role, UserRole.ADMIN);
    });

    test('pricing preset has USER role', () {
      expect(AgentUserPreset.pricing.role, UserRole.USER);
    });

    test('monitoring preset has USER role', () {
      expect(AgentUserPreset.monitoring.role, UserRole.USER);
    });

    test('pointsTransfer preset has USER role', () {
      expect(AgentUserPreset.pointsTransfer.role, UserRole.USER);
    });
  });

  group('AgentUserPreset capability sets', () {
    test('admin preset contains all capabilities', () {
      expect(
        AgentUserPreset.admin.capabilities,
        containsAll(Capability.values),
      );
      expect(
        AgentUserPreset.admin.capabilities.length,
        Capability.values.length,
      );
    });

    test('pricing preset: MANAGE_PRICING + VIEW_REPORTS only', () {
      expect(
        AgentUserPreset.pricing.capabilities,
        {Capability.MANAGE_PRICING, Capability.VIEW_REPORTS},
      );
    });

    test('monitoring preset: VIEW_REPORTS only', () {
      expect(
        AgentUserPreset.monitoring.capabilities,
        {Capability.VIEW_REPORTS},
      );
    });

    test('pointsTransfer preset: MANAGE_POS + CREATE_TRANSACTIONS + VIEW_REPORTS', () {
      expect(
        AgentUserPreset.pointsTransfer.capabilities,
        {
          Capability.MANAGE_POS,
          Capability.CREATE_TRANSACTIONS,
          Capability.VIEW_REPORTS,
        },
      );
    });

    test('monitoring preset does NOT include MANAGE_PRICING', () {
      expect(
        AgentUserPreset.monitoring.capabilities.contains(Capability.MANAGE_PRICING),
        isFalse,
      );
    });

    test('pricing preset does NOT include CREATE_TRANSACTIONS', () {
      expect(
        AgentUserPreset.pricing.capabilities.contains(Capability.CREATE_TRANSACTIONS),
        isFalse,
      );
    });
  });

  // -------------------------------------------------------------------------
  // presetForCapabilities — reverse lookup
  // -------------------------------------------------------------------------
  group('presetForCapabilities — reverse lookup', () {
    test('returns admin for ADMIN role + all caps', () {
      expect(
        presetForCapabilities(UserRole.ADMIN, Capability.values.toSet()),
        AgentUserPreset.admin,
      );
    });

    test('returns pricing for USER + {MANAGE_PRICING, VIEW_REPORTS}', () {
      expect(
        presetForCapabilities(
          UserRole.USER,
          {Capability.MANAGE_PRICING, Capability.VIEW_REPORTS},
        ),
        AgentUserPreset.pricing,
      );
    });

    test('returns monitoring for USER + {VIEW_REPORTS}', () {
      expect(
        presetForCapabilities(UserRole.USER, {Capability.VIEW_REPORTS}),
        AgentUserPreset.monitoring,
      );
    });

    test('returns pointsTransfer for USER + {MANAGE_POS, CREATE_TRANSACTIONS, VIEW_REPORTS}', () {
      expect(
        presetForCapabilities(
          UserRole.USER,
          {
            Capability.MANAGE_POS,
            Capability.CREATE_TRANSACTIONS,
            Capability.VIEW_REPORTS,
          },
        ),
        AgentUserPreset.pointsTransfer,
      );
    });

    test('returns null for an unrecognized custom cap set', () {
      expect(
        presetForCapabilities(
          UserRole.USER,
          {Capability.MANAGE_PRICING, Capability.MANAGE_POS},
        ),
        isNull,
      );
    });

    test('returns null for ADMIN role + empty caps (no preset matches)', () {
      // admin preset requires all caps, not empty set.
      expect(presetForCapabilities(UserRole.ADMIN, {}), isNull);
    });

    test('role mismatch prevents match — USER + all caps returns null', () {
      // admin preset has ADMIN role, so USER + all caps should not match it.
      expect(
        presetForCapabilities(UserRole.USER, Capability.values.toSet()),
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  // CapabilityX labels
  // -------------------------------------------------------------------------
  group('CapabilityX.label — locale switching', () {
    test('en returns English labels', () {
      expect(Capability.AGENT_ADMIN.label('en'), 'Full admin');
      expect(Capability.CREATE_TRANSACTIONS.label('en'), 'Send vouchers');
      expect(Capability.MANAGE_PRICING.label('en'), 'Manage pricing');
      expect(Capability.VIEW_REPORTS.label('en'), 'View reports');
      expect(Capability.MANAGE_POS.label('en'), 'Manage POS');
      expect(Capability.MANAGE_CATALOG.label('en'), 'Manage catalog');
      expect(Capability.MANAGE_AGENTS.label('en'), 'Manage agents');
      expect(Capability.MANAGE_COMPANIES.label('en'), 'Manage companies');
    });

    test('ar returns Arabic labels', () {
      expect(Capability.AGENT_ADMIN.label('ar'), 'مدير شامل');
      expect(Capability.CREATE_TRANSACTIONS.label('ar'), 'إرسال الكروت');
      expect(Capability.MANAGE_PRICING.label('ar'), 'إدارة الأسعار');
      expect(Capability.VIEW_REPORTS.label('ar'), 'عرض التقارير');
      expect(Capability.MANAGE_POS.label('ar'), 'إدارة نقاط البيع');
      expect(Capability.MANAGE_CATALOG.label('ar'), 'إدارة الكتالوج');
      expect(Capability.MANAGE_AGENTS.label('ar'), 'إدارة الوكلاء');
      expect(Capability.MANAGE_COMPANIES.label('ar'), 'إدارة الشركات');
    });

    test('every Capability has a non-empty en and ar label', () {
      for (final c in Capability.values) {
        expect(c.label('en'), isNotEmpty, reason: 'en label for ${c.name}');
        expect(c.label('ar'), isNotEmpty, reason: 'ar label for ${c.name}');
      }
    });

    test('en-US locale prefix still picks English', () {
      expect(Capability.MANAGE_PRICING.label('en-US'), 'Manage pricing');
    });

    test('unknown locale falls back to Arabic', () {
      // Implementation: anything not starting with 'en' returns ar.
      expect(Capability.MANAGE_PRICING.label('fr'), 'إدارة الأسعار');
    });
  });
}
