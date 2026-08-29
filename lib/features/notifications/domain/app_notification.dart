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
  final List<String> audienceTiers;     // multi-tier targeting (audience == TIER)
  final List<String> audienceEntityIds; // multi-entity targeting (audience == ENTITY)
  final bool posOnly;                    // narrowed to POS operators within the scope
  final String type;                     // B-060: NOTIFICATION | ALERT
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
    this.audienceTiers = const [],
    this.audienceEntityIds = const [],
    this.posOnly = false,
    this.type = 'NOTIFICATION',
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
        audienceTiers: (j['tierTypes'] as List<dynamic>?)?.cast<String>() ?? const [],
        audienceEntityIds: (j['entityIds'] as List<dynamic>?)?.cast<String>() ?? const [],
        posOnly: j['posOnly'] as bool? ?? false,
        type: j['type'] as String? ?? 'NOTIFICATION',
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
        'type': type,
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
    List<String>? audienceTiers,
    List<String>? audienceEntityIds,
    bool? posOnly,
    String? type,
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
        audienceTiers: audienceTiers ?? this.audienceTiers,
        audienceEntityIds: audienceEntityIds ?? this.audienceEntityIds,
        posOnly: posOnly ?? this.posOnly,
        type: type ?? this.type,
        senderName: senderName ?? this.senderName,
        sentAt: sentAt ?? this.sentAt,
        isRead: isRead ?? this.isRead,
      );
}

/// UX-88 — the delivery tally `POST /api/notifications` answers with.
///
/// A broadcast used to be confirmed with "Notification sent!", the same six
/// characters whether it went to one shop or to every account in the country.
/// Only the server knows the audience size (the client picks a *scope*), so the
/// create endpoint now returns `{notification, accounts, recipients}` and the
/// toast can name a number.
///
/// Both counts are **nullable on purpose**. The two repos deploy independently,
/// so a client can meet a backend that still answers with the bare notification;
/// [hasTally] is false there and the caller falls back to the audience-only
/// wording. Treating a missing tally as `0` would announce "no account can
/// receive it" over a broadcast that in fact went out fine.
class NotificationReach {
  /// Accounts (entities) whose inbox the notification landed in. Null = the
  /// server did not report a tally.
  final int? accounts;

  /// Individual logins that can open it — an account with three users counts
  /// once in [accounts] and three times here. Null = not reported.
  final int? recipients;

  const NotificationReach({this.accounts, this.recipients});

  bool get hasTally => accounts != null;

  factory NotificationReach.fromJson(Map<String, dynamic> j) => NotificationReach(
        accounts: (j['accounts'] as num?)?.toInt(),
        recipients: (j['recipients'] as num?)?.toInt(),
      );
}
