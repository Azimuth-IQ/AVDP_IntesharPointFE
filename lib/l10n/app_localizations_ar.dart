// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'إنتشار بوينت';

  @override
  String get navDashboard => 'لوحة التحكم';

  @override
  String get navHierarchy => 'الهيكل التنظيمي';

  @override
  String get navChildren => 'الفروع';

  @override
  String get navCatalog => 'الكتالوج';

  @override
  String get navInventory => 'المخزون';

  @override
  String get navBatchAdd => 'إضافة مجمّعة';

  @override
  String get navTransactions => 'المعاملات';

  @override
  String get navPos => 'نقطة البيع';

  @override
  String get loginTitle => 'تسجيل الدخول';

  @override
  String get loginPhone => 'رقم الهاتف';

  @override
  String get loginPassword => 'كلمة المرور';

  @override
  String get loginSignIn => 'دخول';

  @override
  String get loginServerUrl => 'عنوان الخادم';

  @override
  String get loginNoUsers =>
      'لا يوجد مستخدمون في قاعدة البيانات. شغّل أمر البذر في instructions.md §7 لإنشاء أول مدير.';

  @override
  String get loginSeedDemo => 'بيانات تجريبية';

  @override
  String get posHome => 'نقطة البيع';

  @override
  String get posPrintVoucher => 'طباعة القسيمة';

  @override
  String get posConnectPrinter => 'توصيل الطابعة';

  @override
  String get posPrinterConnected => 'الطابعة متصلة';

  @override
  String posAvailable(int count) {
    return '$count متاح';
  }

  @override
  String get posSerial => 'الرقم التسلسلي';

  @override
  String get posPin => 'الرقم السري';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get aboutTitle => 'حول التطبيق';

  @override
  String get aboutVersion => 'الإصدار 1.0.0';

  @override
  String get aboutSupportedPrinters => 'الطابعات المدعومة';

  @override
  String get aboutPrinterNote =>
      'جميع الطرازات تطبع على ورق 58 مم ESC/POS عبر البلوتوث.';

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get emptyListHint => 'لا يوجد شيء هنا بعد.';
}
