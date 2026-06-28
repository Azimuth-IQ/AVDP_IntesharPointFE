/// An in-app notification broadcast by HQ to a specific audience.
///
/// [audienceType] is one of:
///   `ALL`    — every entity in the system.
///   `TIER`   — all entities of [audienceTier] (AGENT1 | AGENT2 | STORE | INTESHAR).
///   `ENTITY` — a single entity identified by [audienceEntityId].
///
/// [isRead] is resolved server-side for the current caller and is read-only on
/// the client. The client optimistically flips it to `true` after a successful
/// mark-read call.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String audienceType;       // ALL | TIER | ENTITY
  final String audienceTier;       // AGENT1 | AGENT2 | STORE — only when type == TIER
  final String audienceEntityId;   // only when type == ENTITY
  final String audienceEntityName; // denormalized; may be empty
  final String senderName;
  final DateTime? sentAt;
  final bool isRead;

  const AppNotification({
    this.id = '',
    this.title = '',
    this.body = '',
    this.audienceType = 'ALL',
    this.audienceTier = '',
    this.audienceEntityId = '',
    this.audienceEntityName = '',
    this.senderName = '',
    this.sentAt,
    this.isRead = false,
  });

  // Wire keys come from the backend NotificationRow: audience / tierType / entityId /
  // createdBy / createdAt / read (NOT audienceType/senderName/sentAt/isRead). The FE
  // field names differ from the wire keys, so the mapping is explicit here.
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        audienceType: j['audience'] as String? ?? 'ALL',
        audienceTier: j['tierType'] as String? ?? '',
        audienceEntityId: j['entityId'] as String? ?? '',
        // Backend does not denormalize an entity name; left empty for the UI.
        audienceEntityName: j['audienceEntityName'] as String? ?? '',
        senderName: j['createdBy'] as String? ?? '',
        sentAt: j['createdAt'] == null
            ? null
            : DateTime.tryParse(j['createdAt'] as String),
        isRead: j['read'] as bool? ?? false,
      );

  /// Mirrors the backend wire keys so `fromJson(toJson(x))` round-trips.
  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'title': title,
        'body': body,
        'audience': audienceType,
        if (audienceTier.isNotEmpty) 'tierType': audienceTier,
        if (audienceEntityId.isNotEmpty) 'entityId': audienceEntityId,
        if (senderName.isNotEmpty) 'createdBy': senderName,
        if (sentAt != null) 'createdAt': sentAt!.toIso8601String(),
        'read': isRead,
      };

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    String? audienceType,
    String? audienceTier,
    String? audienceEntityId,
    String? audienceEntityName,
    String? senderName,
    DateTime? sentAt,
    bool? isRead,
  }) =>
      AppNotification(
        id: id ?? this.id,
        title: title ?? this.title,
        body: body ?? this.body,
        audienceType: audienceType ?? this.audienceType,
        audienceTier: audienceTier ?? this.audienceTier,
        audienceEntityId: audienceEntityId ?? this.audienceEntityId,
        audienceEntityName: audienceEntityName ?? this.audienceEntityName,
        senderName: senderName ?? this.senderName,
        sentAt: sentAt ?? this.sentAt,
        isRead: isRead ?? this.isRead,
      );
}
