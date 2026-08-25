import 'package:inteshar/features/system_activity/domain/operation_log.dart';

/// Turns a logged request into a sentence a human reads (B-108, B-110).
///
/// The activity feed used to print the raw route — an admin saw
/// `POST /api/auth/login` sitting next to a phone number and had to know the API
/// to read their own audit trail. The technical fields are not lost: method,
/// path, action and the rest still show in the row's tap-through detail sheet.
/// This is the headline only.
///
/// B-110: the dictionary covers **every** route the backend exposes — 121
/// distinct paths, GENERATED from the controllers, not guessed. The first pass
/// covered ~40 hand-picked ones and the feed still read as "Request", because
/// those were nearly all writes while READS dominate the log.
///
/// The count was long recorded as 123; that was two parse errors, not two
/// routes — the old snapshot matched inside comments and counted the two
/// disabled `/product/{update,delete}` mappings. `tool/gen_backend_routes.dart`
/// strips comments and is now the single source for both the fixture and the
/// drift test, so this cannot silently rot again.
class LogPhrase {
  /// The human headline, e.g. "Login request" / "طلب تسجيل دخول".
  final String title;

  /// Who it concerns, when known, e.g. "by phone 0770…" / "بالهاتف 0770…".
  final String? by;

  const LogPhrase(this.title, {this.by});

  String get line => by == null || by!.isEmpty ? title : '$title · $by';
}

/// Normalises a logged path so query strings, trailing slashes and casing don't
/// defeat matching. Lowercased — every key below must be lowercase too.
String _norm(String path) {
  var p = path.trim();
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  if (p.endsWith('/') && p.length > 1) p = p.substring(0, p.length - 1);
  return p.toLowerCase();
}

/// Route → (en, ar). Matched by exact-or-endsWith in insertion order, so the
/// MORE SPECIFIC key must come first: `/product/draw/recover-batch` before
/// `/product/draw/recover` before `/product/draw`.
const Map<String, (String, String)> _routes = {
  // ── auth ────────────────────────────────────────────────────────────────
  '/auth/login': ('Login request', 'طلب تسجيل دخول'),
  '/auth/logout': ('Signed out', 'تسجيل خروج'),
  '/auth/change-password': ('Password change', 'تغيير كلمة المرور'),
  '/auth/forgot-password': ('Password help requested', 'طلب مساعدة بكلمة المرور'),
  '/auth/set-pin': ('POS PIN set', 'تعيين الرمز السري'),
  '/auth/verify-pin': ('POS unlock attempt', 'محاولة فتح نقطة البيع'),

  // ── selling (the events that matter most in an audit) ────────────────────
  '/product/sendforprinting': ('Voucher sold', 'بيع كرت'),
  '/product/draw-bulk': ('Bulk voucher sale', 'بيع عدة كروت'),
  '/product/draw/recover-batch': ('Bulk sale recovery', 'استرجاع بيع متعدد'),
  '/product/draw/recover': ('Sale recovery', 'استرجاع عملية بيع'),
  '/product/draw': ('Voucher drawn', 'سحب كرت'),
  '/product/bulk-quote': ('Bulk sale quote', 'تسعير بيع متعدد'),
  '/product/confirmprint': ('Print confirmed', 'تأكيد الطباعة'),
  '/product/print-operations/summary': ('Sales totals', 'إجماليات المبيعات'),
  '/product/print-operations': ('Print history', 'سجل الطباعة'),

  // ── stock ───────────────────────────────────────────────────────────────
  '/product/batch': ('Voucher batch uploaded', 'رفع دفعة كروت'),
  '/product/create': ('Vouchers uploaded', 'رفع كروت'),
  '/product/setstatus': ('Voucher status corrected', 'تصحيح حالة كرت'),
  '/product/setpin': ('Voucher code corrected', 'تعديل رمز كرت'),
  '/product/update': ('Voucher updated', 'تعديل كرت'),
  '/product/delete': ('Voucher deleted', 'حذف كرت'),
  '/product/sellable': ('Sellable stock', 'المخزون القابل للبيع'),
  '/product/summarybyentity': ('Stock summary', 'ملخص المخزون'),
  '/product/readbyentityandsku': ('Stock by category', 'المخزون حسب الفئة'),
  '/product/readbyentityvalue': ('Stock value', 'قيمة المخزون'),
  '/product/readfullinventoryvalue': ('Inventory value', 'قيمة المخزون الكلية'),
  '/product/readbyentity': ('Stock list', 'قائمة المخزون'),
  '/product/read': ('Voucher lookup', 'استعلام كرت'),
  '/inventory/batch/export': ('Batch exported', 'تصدير دفعة'),
  '/inventory/batch/pause': ('Batch paused', 'إيقاف دفعة'),
  '/inventory/withdraw': ('Stock withdrawn from an agent', 'سحب كروت من مخزن وكيل'),
  // C-19. Order matters — the match is a substring test, so `/inventory/retire`
  // would swallow both of the longer keys if it came first.
  '/inventory/transfer': ('Stock moved between agents', 'تحويل كروت بين الوكلاء'),
  '/inventory/retire/restore': ('Retired stock restored', 'إرجاع كروت مسحوبة نهائياً'),
  '/inventory/retired': ('Retired stock list', 'قائمة الكروت المسحوبة نهائياً'),
  '/inventory/retire': ('Stock retired permanently', 'إخراج كروت من السستم نهائياً'),
  '/inventory/batch/withdraw': ('Batch withdrawn', 'سحب دفعة'),
  '/inventory/batches': ('Batch list', 'قائمة الدفعات'),
  '/inventory/batch': ('Batch deleted', 'حذف دفعة'),

  // ── categories (product definitions) ─────────────────────────────────────
  '/definition/create': ('Category created', 'إنشاء فئة'),
  '/definition/update': ('Category updated', 'تعديل فئة'),
  '/definition/delete': ('Category deleted', 'حذف فئة'),
  '/definition/restrictions': ('Category restrictions', 'قيود الفئات'),
  '/definition/restrict': ('Category restricted', 'تقييد فئة'),
  '/definition/readall': ('Category list', 'قائمة الفئات'),
  '/definition/read': ('Category lookup', 'استعلام فئة'),

  // ── money ───────────────────────────────────────────────────────────────
  '/balance/reclaim': ('Balance taken back', 'استرجاع رصيد'),
  '/balance/grant': ('Balance transfer', 'تحويل رصيد'),
  '/balance/grants': ('Transfer history', 'سجل التحويلات'),
  '/balance': ('Balance check', 'استعلام رصيد'),
  '/pricing/set-bulk': ('Prices uploaded', 'رفع الأسعار'),
  '/pricing/set': ('Price set', 'تعديل سعر'),
  '/pricing/catalog': ('Price list', 'قائمة الأسعار'),
  '/pricing/unpriced-agents': ('Unpriced agents check', 'فحص الوكلاء بلا أسعار'),

  // ── POS quota / network ─────────────────────────────────────────────────
  '/pos-quota/network/summary': ('POS network summary', 'ملخص شبكة نقاط البيع'),
  '/pos-quota/network': ('POS network', 'شبكة نقاط البيع'),
  '/pos-quota/reclaim': ('POS points taken back', 'استرجاع نقاط بيع'),
  '/pos-quota/grants': ('POS slot history', 'سجل حصص نقاط البيع'),
  '/pos-quota/grant': ('POS slots granted', 'منح حصص نقاط بيع'),
  '/pos-quota': ('POS quota', 'حصة نقاط البيع'),

  // ── POS points ──────────────────────────────────────────────────────────
  '/pos-users/onboard': ('POS point created', 'إنشاء نقطة بيع'),
  '/pos-users/archived': ('Archived POS points', 'قائمة نقاط البيع المؤرشفة'),
  '/pos-users/export': ('POS data exported', 'تصدير بيانات نقطة بيع'),
  '/pos-users/purge': ('POS point deleted permanently', 'حذف نهائي لنقطة بيع'),
  '/pos-users/restore': ('POS point restored', 'إعادة تفعيل نقطة بيع'),
  '/pos-users/revoke': ('POS point archived', 'أرشفة نقطة بيع'),
  '/pos-users/reset-password': ('POS password reset', 'إعادة تعيين كلمة مرور نقطة بيع'),
  '/pos-users/reset-pin': ('POS PIN reset', 'إعادة تعيين رمز نقطة بيع'),
  '/pos-users/reset-totp': ('POS 2FA reset', 'إعادة تعيين تحقق نقطة بيع'),
  '/pos-users/update': ('POS point updated', 'تعديل نقطة بيع'),
  '/pos-users/list/page': ('POS points list', 'قائمة نقاط البيع'),
  '/pos-users/list': ('POS points list', 'قائمة نقاط البيع'),
  '/pos/confirm-location': ('POS location confirmed', 'تأكيد موقع نقطة البيع'),
  '/pos/statement/page': ('POS statement page', 'صفحة كشف حساب نقطة البيع'),
  '/pos/statement': ('POS statement', 'كشف حساب نقطة البيع'),

  // ── accounts ────────────────────────────────────────────────────────────
  '/entity/users/resettotp': ('2FA reset', 'إعادة تعيين التحقق بخطوتين'),
  '/entity/users/add': ('User added', 'إضافة مستخدم'),
  // UX-156: /remove keeps its path but no longer destroys the account — it
  // archives it. The sentence has to say what actually happened, or the audit
  // trail reads as a delete that never occurred.
  '/entity/users/archived': ('Archived users', 'قائمة المستخدمين المؤرشفين'),
  '/entity/users/restore': ('User restored', 'إعادة تفعيل مستخدم'),
  '/entity/users/remove': ('User archived', 'أرشفة مستخدم'),
  '/entity/users/update': ('User updated', 'تعديل مستخدم'),
  '/entity/users': ('User list', 'قائمة المستخدمين'),
  '/entity/create': ('Account created', 'إنشاء حساب'),
  '/entity/update': ('Account updated', 'تعديل حساب'),
  '/entity/dependents': ('Checked what an account holds', 'فحص الحسابات التابعة'),
  '/entity/delete': ('Account deleted', 'حذف حساب'),
  '/entity/setactive': ('Account enabled or disabled', 'تفعيل أو إيقاف حساب'),
  '/entity/resetpassword': ('Password reset', 'إعادة تعيين كلمة المرور'),
  '/entity/workinghours': ('Working hours changed', 'تعديل ساعات العمل'),
  '/entity/branding': ('Branding loaded', 'تحميل الهوية'),
  '/entity/children': ('Sub-accounts list', 'قائمة الحسابات الفرعية'),
  '/entity/chain': ('Parent accounts', 'الحسابات الأعلى'),
  '/entity/readwithchildren': ('Account tree', 'شجرة الحسابات'),
  '/entity/getwithchildren': ('Account tree', 'شجرة الحسابات'),
  '/entity/readall': ('Account list', 'قائمة الحسابات'),
  '/entity/search': ('Account search', 'بحث في الحسابات'),
  '/entity/summary': ('Accounts overview', 'نظرة عامة على الحسابات'),
  '/entity/posstats': ('POS statistics', 'إحصائيات نقاط البيع'),
  '/entity/me': ('Session loaded', 'تحميل الجلسة'),
  '/entity/read': ('Account lookup', 'استعلام حساب'),

  // ── companies ───────────────────────────────────────────────────────────
  '/company/create': ('Company created', 'إنشاء شركة'),
  '/company/update': ('Company updated', 'تعديل شركة'),
  '/company/delete': ('Company deleted', 'حذف شركة'),
  '/company/restrictions': ('Company restrictions', 'قيود الشركات'),
  '/company/restrict': ('Company restricted', 'تقييد شركة'),
  '/company/readall': ('Company list', 'قائمة الشركات'),
  '/company/read': ('Company lookup', 'استعلام شركة'),

  // ── transfers (legacy transaction flow) ──────────────────────────────────
  '/transactions/create': ('Transfer created', 'إنشاء تحويل'),
  '/transactions/update': ('Transfer updated', 'تعديل تحويل'),
  '/transactions/delete': ('Transfer deleted', 'حذف تحويل'),
  '/transactions/feed': ('Transfers feed', 'تدفق التحويلات'),
  '/transactions/recent': ('Recent transfers', 'أحدث التحويلات'),
  '/transactions/page': ('Transfers list', 'قائمة التحويلات'),
  '/transactions/readall': ('Transfers list', 'قائمة التحويلات'),
  '/transactions/read': ('Transfer lookup', 'استعلام تحويل'),

  // ── messaging ───────────────────────────────────────────────────────────
  '/chat/send': ('Message sent', 'إرسال رسالة'),
  '/chat/read': ('Messages read', 'قراءة الرسائل'),
  '/chat/messages': ('Conversation opened', 'فتح المحادثة'),
  '/chat/threads': ('Conversations list', 'قائمة المحادثات'),
  '/notifications': ('Notification sent', 'إرسال إشعار'),

  // ── reports ─────────────────────────────────────────────────────────────
  '/reports/balances': ('Balances report', 'تقرير الأرصدة'),
  '/reports/sales': ('Sales report', 'تقرير المبيعات'),
  '/reports/transfers': ('Transfers report', 'تقرير التحويلات'),
  '/reports/uploads': ('Uploads report', 'تقرير الكروت المرفوعة'),

  // ── oversight / platform ────────────────────────────────────────────────
  '/admin/overview': ('Oversight dashboard', 'لوحة المتابعة'),
  '/admin/users': ('User directory', 'دليل المستخدمين'),
  '/logs/client': ('App error reported', 'تقرير خطأ من التطبيق'),
  '/logs/read': ('Activity entry opened', 'فتح سجل نشاط'),
  '/logs': ('Activity log', 'سجل النشاط'),
  '/slider/reorder': ('Slider reordered', 'ترتيب الشرائح'),
  '/slider': ('Slider', 'الشرائح'),
  '/storage/upload': ('File uploaded', 'رفع ملف'),

  // ── app updates ─────────────────────────────────────────────────────────
  '/app/upload-apk': ('App file uploaded', 'رفع ملف التطبيق'),
  '/app/release': ('App release published', 'نشر إصدار جديد'),
  '/app/download': ('App downloaded', 'تنزيل التطبيق'),
  '/app/check': ('Update check', 'فحص التحديثات'),
  '/app/latest': ('Update check', 'فحص التحديثات'),
};

/// Routes carrying an id in the middle, which `endsWith` can't match.
const List<(String prefix, String suffix, String en, String ar)> _patterns = [
  ('/notifications/', '/read', 'Notification read', 'قراءة إشعار'),
];

/// Path-prefix families where the tail varies (a settings key, a slider id).
const List<(String prefix, String en, String ar)> _prefixes = [
  ('/settings/', 'Platform setting changed', 'تعديل إعداد النظام'),
  ('/health/', 'Health check', 'فحص النظام'),
  ('/slider/', 'Slider updated', 'تعديل الشرائح'),
];

/// Fallback — a translated "request", never a URL.
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
    return LogPhrase(action.isNotEmpty ? action : pick(_fallback), by: by);
  }

  final p = path.startsWith('/api') ? path.substring(4) : path;

  for (final e in _routes.entries) {
    if (p == e.key || p.endsWith(e.key)) return LogPhrase(pick(e.value), by: by);
  }
  for (final (prefix, suffix, en, arT) in _patterns) {
    if (p.contains(prefix) && p.endsWith(suffix)) {
      return LogPhrase(ar ? arT : en, by: by);
    }
  }
  for (final (prefix, en, arT) in _prefixes) {
    if (p.contains(prefix)) return LogPhrase(ar ? arT : en, by: by);
  }
  return LogPhrase(pick(_fallback), by: by);
}
