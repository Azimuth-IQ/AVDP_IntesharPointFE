/// One operational / audit event from `GET /api/logs`. Mirrors the backend
/// `OperationLog` document (Logging slice). Bodies are never stored server-side,
/// so this only ever carries request metadata — never PINs, passwords, or tokens.
///
/// `source` is `server` (request log) or `client` (a crash / network failure the
/// app self-reported). `level` is `INFO | WARN | ERROR`.
class OperationLog {
  final String id;
  final DateTime? timestamp;
  final String source; // server | client
  final String level; // INFO | WARN | ERROR
  final String clientPlatform; // web | android | ios | …
  final String surface; // hq | agent1 | agent2 | store | pos
  final String deviceModel;
  final String osVersion;
  final String appVersion;
  final String entityId;
  final String userPhone;
  final String userRole;
  final String ip;
  final String method;
  final String path;
  final String queryString;
  final String action;
  final int? httpStatus;
  final bool success;
  final int? durationMs;
  final String errorType;
  final String errorMessage;
  final String stackTrace;
  final String userAgent;
  final String correlationId;

  const OperationLog({
    this.id = '',
    this.timestamp,
    this.source = '',
    this.level = 'INFO',
    this.clientPlatform = '',
    this.surface = '',
    this.deviceModel = '',
    this.osVersion = '',
    this.appVersion = '',
    this.entityId = '',
    this.userPhone = '',
    this.userRole = '',
    this.ip = '',
    this.method = '',
    this.path = '',
    this.queryString = '',
    this.action = '',
    this.httpStatus,
    this.success = false,
    this.durationMs,
    this.errorType = '',
    this.errorMessage = '',
    this.stackTrace = '',
    this.userAgent = '',
    this.correlationId = '',
  });

  bool get isError => level.toUpperCase() == 'ERROR';
  bool get isWarn => level.toUpperCase() == 'WARN';

  factory OperationLog.fromJson(Map<String, dynamic> j) => OperationLog(
        id: j['id'] as String? ?? '',
        timestamp: _parseInstant(j['timestamp']),
        source: j['source'] as String? ?? '',
        level: (j['level'] as String? ?? 'INFO').toUpperCase(),
        clientPlatform: j['clientPlatform'] as String? ?? '',
        surface: j['surface'] as String? ?? '',
        deviceModel: j['deviceModel'] as String? ?? '',
        osVersion: j['osVersion'] as String? ?? '',
        appVersion: j['appVersion'] as String? ?? '',
        entityId: j['entityId'] as String? ?? '',
        userPhone: j['userPhone'] as String? ?? '',
        userRole: j['userRole'] as String? ?? '',
        ip: j['ip'] as String? ?? '',
        method: j['method'] as String? ?? '',
        path: j['path'] as String? ?? '',
        queryString: j['queryString'] as String? ?? '',
        action: j['action'] as String? ?? '',
        httpStatus: (j['httpStatus'] as num?)?.toInt(),
        success: j['success'] as bool? ?? false,
        durationMs: (j['durationMs'] as num?)?.toInt(),
        errorType: j['errorType'] as String? ?? '',
        errorMessage: j['errorMessage'] as String? ?? '',
        stackTrace: j['stackTrace'] as String? ?? '',
        userAgent: j['userAgent'] as String? ?? '',
        correlationId: j['correlationId'] as String? ?? '',
      );

  /// The backend serialises `Instant` as an ISO-8601 string (Spring Boot's
  /// default); fall back to epoch millis if a numeric timestamp ever appears.
  static DateTime? _parseInstant(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    if (v is num) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true).toLocal();
    }
    return null;
  }
}
