// Tests for [AppNotification.fromJson] / [toJson] / [copyWith] and the
// reconciled [Endpoints] constants that map to backend notification + settings
// paths.
//
// IMPORTANT: the wire keys are the backend NotificationRow field names
// (audience / tierType / entityId / createdBy / createdAt / read) — NOT the FE
// field names (audienceType / senderName / sentAt / isRead). These tests pin
// that mapping so the inbox can never silently drift back to the wrong keys.
//
// All tests are pure (no network, no widgets, no mocks).

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/notifications/domain/app_notification.dart';
import 'package:inteshar/core/api/endpoints.dart';

void main() {
  // ─── AppNotification.fromJson ──────────────────────────────────────────────

  group('AppNotification.fromJson — ALL audience', () {
    const json = {
      'id': 'notif-001',
      'title': 'System maintenance',
      'body': 'Scheduled downtime Saturday',
      'audience': 'ALL',
      'createdBy': 'Inteshar HQ',
      'createdAt': '2026-06-28T10:00:00.000Z',
      'read': false,
    };

    test('parses id, title, body', () {
      final n = AppNotification.fromJson(json);
      expect(n.id, 'notif-001');
      expect(n.title, 'System maintenance');
      expect(n.body, 'Scheduled downtime Saturday');
    });

    test('parses audience (wire key) into audienceType', () {
      final n = AppNotification.fromJson(json);
      expect(n.audienceType, 'ALL');
    });

    test('audienceTier defaults to empty string when absent', () {
      expect(AppNotification.fromJson(json).audienceTier, '');
    });

    test('audienceEntityId defaults to empty string when absent', () {
      expect(AppNotification.fromJson(json).audienceEntityId, '');
    });

    test('parses createdBy (wire key) into senderName', () {
      expect(AppNotification.fromJson(json).senderName, 'Inteshar HQ');
    });

    test('parses createdAt (wire key) into sentAt', () {
      final n = AppNotification.fromJson(json);
      expect(n.sentAt, isNotNull);
      expect(n.sentAt!.year, 2026);
      expect(n.sentAt!.month, 6);
      expect(n.sentAt!.day, 28);
    });

    test('read false → isRead false', () {
      expect(AppNotification.fromJson(json).isRead, isFalse);
    });
  });

  group('AppNotification.fromJson — TIER audience', () {
    const json = {
      'id': 'notif-002',
      'title': 'Price update for stores',
      'body': 'New pricing effective Monday',
      'audience': 'TIER',
      'tierType': 'STORE',
      'createdBy': 'Agent Baghdad',
      'createdAt': null,
      'read': true,
    };

    test('parses audience TIER', () {
      expect(AppNotification.fromJson(json).audienceType, 'TIER');
    });

    test('parses tierType STORE into audienceTier', () {
      expect(AppNotification.fromJson(json).audienceTier, 'STORE');
    });

    test('sentAt is null when createdAt is null', () {
      expect(AppNotification.fromJson(json).sentAt, isNull);
    });

    test('read true → isRead true', () {
      expect(AppNotification.fromJson(json).isRead, isTrue);
    });

    test('audienceEntityId still empty for TIER notification', () {
      expect(AppNotification.fromJson(json).audienceEntityId, '');
    });
  });

  group('AppNotification.fromJson — ENTITY audience', () {
    const json = {
      'id': 'notif-003',
      'title': 'Your account was updated',
      'body': 'Details changed by HQ',
      'audience': 'ENTITY',
      'entityId': 'agent1-baghdad',
      'createdBy': 'Inteshar HQ',
      'createdAt': '2026-06-25T08:30:00.000',
      'read': false,
    };

    test('parses audience ENTITY', () {
      expect(AppNotification.fromJson(json).audienceType, 'ENTITY');
    });

    test('parses entityId into audienceEntityId', () {
      expect(AppNotification.fromJson(json).audienceEntityId, 'agent1-baghdad');
    });

    test('audienceEntityName is empty (backend does not denormalize it)', () {
      expect(AppNotification.fromJson(json).audienceEntityName, '');
    });

    test('parses createdAt without trailing Z (local ISO string)', () {
      final n = AppNotification.fromJson(json);
      expect(n.sentAt, isNotNull);
      expect(n.sentAt!.hour, 8);
      expect(n.sentAt!.minute, 30);
    });

    test('audienceTier empty for ENTITY notification', () {
      expect(AppNotification.fromJson(json).audienceTier, '');
    });
  });

  group('AppNotification.fromJson — wire-key discipline (F4 regression)', () {
    test('the FE field names are NOT wire keys — they are ignored on parse', () {
      // A payload using the OLD/wrong keys must NOT populate the fields; the model
      // reads only the backend keys. This is the exact bug F4 fixed.
      final n = AppNotification.fromJson({
        'audienceType': 'TIER', // wrong key — ignored
        'senderName': 'Nope', // wrong key — ignored
        'isRead': true, // wrong key — ignored
      });
      expect(n.audienceType, 'ALL'); // default, because 'audience' was absent
      expect(n.senderName, ''); // default, because 'createdBy' was absent
      expect(n.isRead, isFalse); // default, because 'read' was absent
    });
  });

  group('AppNotification.fromJson — missing / null fields use defaults', () {
    test('empty map yields safe defaults', () {
      final n = AppNotification.fromJson({});
      expect(n.id, '');
      expect(n.title, '');
      expect(n.body, '');
      expect(n.audienceType, 'ALL');
      expect(n.audienceTier, '');
      expect(n.audienceEntityId, '');
      expect(n.audienceEntityName, '');
      expect(n.senderName, '');
      expect(n.sentAt, isNull);
      expect(n.isRead, isFalse);
    });

    test('explicit null createdAt field → null DateTime', () {
      expect(AppNotification.fromJson({'createdAt': null}).sentAt, isNull);
    });

    test('malformed createdAt string → null (DateTime.tryParse guard)', () {
      expect(AppNotification.fromJson({'createdAt': 'not-a-date'}).sentAt, isNull);
    });
  });

  // ─── AppNotification.toJson (mirrors the wire keys) ────────────────────────

  group('AppNotification.toJson', () {
    test('omits id when empty', () {
      const n = AppNotification(title: 'Hi', body: 'Hello', audienceType: 'ALL');
      expect(n.toJson().containsKey('id'), isFalse);
    });

    test('includes id when non-empty', () {
      const n = AppNotification(id: 'x1', title: 'Hi', body: 'B', audienceType: 'ALL');
      expect(n.toJson()['id'], 'x1');
    });

    test('omits tierType when empty', () {
      const n = AppNotification(audienceType: 'ALL');
      expect(n.toJson().containsKey('tierType'), isFalse);
    });

    test('includes tierType when non-empty', () {
      const n = AppNotification(audienceType: 'TIER', audienceTier: 'AGENT1');
      expect(n.toJson()['tierType'], 'AGENT1');
    });

    test('omits entityId when empty', () {
      const n = AppNotification(audienceType: 'ALL');
      expect(n.toJson().containsKey('entityId'), isFalse);
    });

    test('includes entityId when non-empty', () {
      const n = AppNotification(audienceType: 'ENTITY', audienceEntityId: 'store-42');
      expect(n.toJson()['entityId'], 'store-42');
    });

    test('always emits title, body, and audience (wire key for audienceType)', () {
      const n = AppNotification(
          title: 'T', body: 'B', audienceType: 'TIER', audienceTier: 'STORE');
      final j = n.toJson();
      expect(j['title'], 'T');
      expect(j['body'], 'B');
      expect(j['audience'], 'TIER');
    });
  });

  // ─── round-trip ──────────────────────────────────────────────────────────

  group('AppNotification round-trip fromJson → toJson', () {
    test('TIER notification survives a round-trip', () {
      const original = {
        'id': 'rt-1',
        'title': 'Round-trip',
        'body': 'Test',
        'audience': 'TIER',
        'tierType': 'AGENT2',
      };
      final reEncoded = AppNotification.fromJson(original).toJson();
      expect(reEncoded['id'], 'rt-1');
      expect(reEncoded['audience'], 'TIER');
      expect(reEncoded['tierType'], 'AGENT2');
    });

    test('ENTITY notification survives a round-trip', () {
      const original = {
        'id': 'rt-2',
        'title': 'Entity note',
        'body': 'For one store',
        'audience': 'ENTITY',
        'entityId': 'store-7',
      };
      final reEncoded = AppNotification.fromJson(original).toJson();
      expect(reEncoded['entityId'], 'store-7');
    });
  });

  // ─── copyWith ─────────────────────────────────────────────────────────────

  group('AppNotification.copyWith', () {
    const base = AppNotification(id: 'n1', title: 'Old title', isRead: false);

    test('flipping isRead true (optimistic mark-read)', () {
      final updated = base.copyWith(isRead: true);
      expect(updated.isRead, isTrue);
      expect(updated.id, 'n1');
      expect(updated.title, 'Old title');
    });

    test('updating title leaves other fields unchanged', () {
      final updated = base.copyWith(title: 'New title');
      expect(updated.title, 'New title');
      expect(updated.isRead, isFalse);
      expect(updated.id, 'n1');
    });

    test('original is not mutated', () {
      base.copyWith(isRead: true, title: 'X');
      expect(base.isRead, isFalse);
      expect(base.title, 'Old title');
    });
  });

  // ─── Endpoints constants ──────────────────────────────────────────────────

  group('Endpoints — reconciled backend paths', () {
    test('notifications inbox/send base path', () {
      expect(Endpoints.notifications, '/api/notifications');
    });

    test('notificationsSend shares the same base path as the inbox', () {
      expect(Endpoints.notificationsSend, '/api/notifications');
    });

    test('settingsWorkingHours global toggle path', () {
      expect(Endpoints.settingsWorkingHours, '/api/settings/auth.workinghours.enabled');
    });

    test('settingsWorkingHoursEntity per-entity patch path', () {
      expect(Endpoints.settingsWorkingHoursEntity, '/api/entity/workingHours');
    });

    test('productBatchDelete path', () {
      expect(Endpoints.productBatchDelete, '/api/inventory/batch');
    });

    test('productBatchPause path (also handles resume via ?paused=)', () {
      expect(Endpoints.productBatchPause, '/api/inventory/batch/pause');
    });
  });
}
