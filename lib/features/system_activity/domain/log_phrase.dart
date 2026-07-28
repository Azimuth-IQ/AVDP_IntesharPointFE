import 'package:inteshar/features/system_activity/domain/operation_log.dart';

/// Turns a logged request into a sentence a human reads (B-108).
///
/// The activity feed used to print the raw route — an admin saw
/// `POST /api/auth/login` sitting next to a phone number and had to know the API
/// to read their own audit trail. The technical fields are not lost: method,
/// path, action and the rest still show in the row's tap-through detail sheet.
/// This is the headline only.
///
/// Anything unrecognised — including automated/bot traffic — degrades to a
/// translated "request", never a URL.
class LogPhrase {
  /// The human headline, e.g. "Login request" / "طلب تسجيل دخول".
  final String title;

  /// Who it concerns, when known, e.g. "by phone 0770…" / "بالهاتف 0770…".
  final String? by;

  const LogPhrase(this.title, {this.by});

  String get line => by == null || by!.isEmpty ? title : '$title · $by';
}

/// Normalises a logged path so query strings and ids don't defeat matching.
String _norm(String path) {
  var p = path.trim();
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  if (p.endsWith('/') && p.length > 1) p = p.substring(0, p.length - 1);
  return p.toLowerCase();
}

/// Route → phrase. Ordered: the first key the path ENDS WITH (after /api) wins,
/// so `/api/inventory/product/create` matches before the `/product` family.
///
/// Keys are the API path with the `/api` prefix dropped.
const Map<String, (String en, String ar)> _routes = {
  // ── auth
  '/auth/login': ('Login request', 'طلب تسجيل دخول'),
  '/auth/logout': ('Signed out', 'تسجيل خروج'),
  '/auth/change-password': ('Password change', 'تغيير كلمة المرور'),
  '/auth/forgot-password': ('Password help requested', 'طلب مساعدة بكلمة المرور'),
  '/auth/set-pin': ('POS PIN set', 'تعيين الرمز السري'),
  '/auth/verify-pin': ('POS unlock attempt', 'محاولة فتح نقطة البيع'),

  // ── selling / inventory
  '/product/sendforprinting': ('Voucher sold', 'بيع كرت'),
  '/product/draw-bulk': ('Bulk voucher sale', 'بيع عدة كروت'),
  '/product/bulk-quote': ('Bulk sale quote', 'تسعير بيع متعدد'),
  '/product/create': ('Vouchers uploaded', 'رفع كروت'),
  '/product/summarybyentity': ('Stock summary', 'ملخص المخزون'),
  '/definition/create': ('Category created', 'إنشاء فئة'),
  '/definition/update': ('Category updated', 'تعديل فئة'),
  '/definition/delete': ('Category deleted', 'حذف فئة'),
  '/inventory/batch': ('Voucher batch', 'دفعة كروت'),

  // ── money
  '/balance/grant': ('Balance transfer', 'تحويل رصيد'),
  '/balance/grants': ('Transfer history', 'سجل التحويلات'),
  '/balance': ('Balance check', 'استعلام رصيد'),
  '/pricing/set': ('Price set', 'تعديل سعر'),
  '/pricing/set-bulk': ('Prices uploaded', 'رفع الأسعار'),
  '/pricing/catalog': ('Price list', 'قائمة الأسعار'),

  // ── accounts
  '/pos-users/onboard': ('POS point created', 'إنشاء نقطة بيع'),
  '/pos-users/revoke': ('POS point removed', 'حذف نقطة بيع'),
  '/pos-users/reset-password': ('POS password reset', 'إعادة تعيين كلمة مرور نقطة بيع'),
  '/pos-users/reset-pin': ('POS PIN reset', 'إعادة تعيين رمز نقطة بيع'),
  '/pos-users/reset-totp': ('POS 2FA reset', 'إعادة تعيين التحقق بخطوتين'),
  '/entity/create': ('Account created', 'إنشاء حساب'),
  '/entity/update': ('Account updated', 'تعديل حساب'),
  '/entity/delete': ('Account deleted', 'حذف حساب'),
  '/entity/setactive': ('Account enabled/disabled', 'تفعيل/إيقاف حساب'),
  '/entity/resetpassword': ('Password reset', 'إعادة تعيين كلمة المرور'),
  '/entity/users/add': ('User added', 'إضافة مستخدم'),
  '/entity/users/remove': ('User removed', 'حذف مستخدم'),

  // ── everything else people actually look at
  '/chat/send': ('Message sent', 'إرسال رسالة'),
  '/pos/confirm-location': ('POS location confirmed', 'تأكيد موقع نقطة البيع'),
  '/transactions/create': ('Transfer created', 'إنشاء تحويل'),
  '/storage/upload': ('File uploaded', 'رفع ملف'),
  '/logs/client': ('App error reported', 'تقرير خطأ من التطبيق'),
};

/// Report routes collapse to one phrase — which report is detail, not headline.
const _reportRoots = ['/reports/', '/admin/', '/health/'];
const _reportPhrase = ('Report viewed', 'عرض تقرير');
const _adminPhrase = ('Oversight feed', 'لوحة المتابعة');
const _healthPhrase = ('Health check', 'فحص النظام');

/// Fallback for anything unmatched, including automated traffic — a translated
/// "request", never a raw URL.
const _fallback = ('Request', 'طلب');

LogPhrase logPhrase(OperationLog log, {required bool ar}) {
  String pick((String, String) p) => ar ? p.$2 : p.$1;

  final by = log.userPhone.trim().isEmpty
      ? null
      : (ar ? 'بالهاتف ${log.userPhone}' : 'by phone ${log.userPhone}');

  final path = _norm(log.path);
  if (path.isEmpty) {
    // Client-side entries carry an action instead of a route.
    final action = log.action.trim();
    if (action.isNotEmpty) return LogPhrase(action, by: by);
    return LogPhrase(pick(_fallback), by: by);
  }

  final stripped = path.startsWith('/api') ? path.substring(4) : path;

  for (final e in _routes.entries) {
    if (stripped == e.key || stripped.endsWith(e.key)) {
      return LogPhrase(pick(e.value), by: by);
    }
  }
  for (final root in _reportRoots) {
    if (stripped.startsWith(root)) {
      return LogPhrase(
        pick(switch (root) {
          '/reports/' => _reportPhrase,
          '/admin/' => _adminPhrase,
          _ => _healthPhrase,
        }),
        by: by,
      );
    }
  }
  return LogPhrase(pick(_fallback), by: by);
}
