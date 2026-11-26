/// PROD-037: a telecom company's read-only view (Asiacell, Zain) and HQ's management
/// of those accounts. Wire shapes mirror the backend `Pricing/DTOs/Company*`.
library;

/// Who the signed-in company account is — the header of its one screen.
class CompanyPortalInfo {
  final String accountName;
  final String companyId;
  final String companyName;
  final String companyLogoUrl;

  const CompanyPortalInfo({
    this.accountName = '',
    this.companyId = '',
    this.companyName = '',
    this.companyLogoUrl = '',
  });

  factory CompanyPortalInfo.fromJson(Map<String, dynamic> j) => CompanyPortalInfo(
        accountName: (j['accountName'] ?? '').toString(),
        companyId: (j['companyId'] ?? '').toString(),
        companyName: (j['companyName'] ?? '').toString(),
        companyLogoUrl: (j['companyLogoUrl'] ?? '').toString(),
      );
}

/// Cards of one card type uploaded on one Baghdad day for one governorate.
/// [governorate] '' = region-free cards.
class CompanyUploadRow {
  final String day;
  final String governorate;
  final String category;
  final String sku;
  final int count;

  const CompanyUploadRow({
    required this.day,
    this.governorate = '',
    this.category = '',
    this.sku = '',
    this.count = 0,
  });

  factory CompanyUploadRow.fromJson(Map<String, dynamic> j) => CompanyUploadRow(
        day: (j['day'] ?? '').toString(),
        governorate: (j['governorate'] ?? '').toString(),
        category: (j['category'] ?? '').toString(),
        sku: (j['sku'] ?? '').toString(),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

/// One company account on HQ's list.
class CompanyAccount {
  final String id;
  final String name;
  final String companyId;
  final String companyName;
  final String phone;
  final bool active;
  final bool totpEnrolled;
  final bool mustChangePassword;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final String lastSeenIp;

  const CompanyAccount({
    required this.id,
    this.name = '',
    this.companyId = '',
    this.companyName = '',
    this.phone = '',
    this.active = true,
    this.totpEnrolled = false,
    this.mustChangePassword = false,
    this.createdAt,
    this.lastSeenAt,
    this.lastSeenIp = '',
  });

  factory CompanyAccount.fromJson(Map<String, dynamic> j) => CompanyAccount(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        companyId: (j['companyId'] ?? '').toString(),
        companyName: (j['companyName'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        active: j['active'] != false,
        totpEnrolled: j['totpEnrolled'] == true,
        mustChangePassword: j['mustChangePassword'] == true,
        createdAt: _time(j['createdAt']),
        lastSeenAt: _time(j['lastSeenAt']),
        lastSeenIp: (j['lastSeenIp'] ?? '').toString(),
      );
}

/// One request a company account made (HQ's activity view).
class CompanyActivity {
  final DateTime? at;
  final String method;
  final String path;
  final String query;
  final int? status;
  final String ip;
  final String platform;
  final String device;

  const CompanyActivity({
    this.at,
    this.method = '',
    this.path = '',
    this.query = '',
    this.status,
    this.ip = '',
    this.platform = '',
    this.device = '',
  });

  factory CompanyActivity.fromJson(Map<String, dynamic> j) => CompanyActivity(
        at: _time(j['at']),
        method: (j['method'] ?? '').toString(),
        path: (j['path'] ?? '').toString(),
        query: (j['query'] ?? '').toString(),
        status: (j['status'] as num?)?.toInt(),
        ip: (j['ip'] ?? '').toString(),
        platform: (j['platform'] ?? '').toString(),
        device: (j['device'] ?? '').toString(),
      );

  /// Refused by the server: the account tried something outside its one screen.
  bool get refused => (status ?? 0) == 403;

  /// What the request was, in the reader's words.
  String describe({required bool ar}) {
    final p = path;
    if (p.startsWith('/api/company-portal/uploads')) {
      return ar ? 'فتح تقرير الكروت المرفوعة' : 'Opened the uploads report';
    }
    if (p.startsWith('/api/company-portal/exported')) {
      return ar ? 'حفظ التقرير كملف Excel' : 'Saved the report as Excel';
    }
    if (p == '/api/entity/me') return ar ? 'دخول / فتح الصفحة' : 'Signed in / opened the page';
    if (p.startsWith('/api/company-portal/me')) return ar ? 'فتح الصفحة' : 'Opened the page';
    if (p.startsWith('/api/auth/logout')) return ar ? 'تسجيل خروج' : 'Signed out';
    if (refused) return ar ? 'محاولة مرفوضة: $method $p' : 'Refused attempt: $method $p';
    return '$method $p';
  }
}

DateTime? _time(dynamic v) {
  if (v == null) return null;
  if (v is num) return DateTime.fromMillisecondsSinceEpoch((v * 1000).round()).toLocal();
  return DateTime.tryParse(v.toString())?.toLocal();
}
