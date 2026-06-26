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
  String get navTemplates => 'القوالب';

  @override
  String get navMore => 'المزيد';

  @override
  String get updateAvailableTitle => 'تحديث متوفّر';

  @override
  String get updateBody => 'إصدار أحدث من إنتشار بوينت جاهز للتثبيت.';

  @override
  String get updateRequiredTitle => 'التحديث مطلوب';

  @override
  String get updateRequiredBody => 'يجب تثبيت التحديث المطلوب قبل المتابعة.';

  @override
  String get updateWhatsNew => 'الجديد في هذا الإصدار';

  @override
  String get updateNow => 'تحديث الآن';

  @override
  String get updateLater => 'لاحقاً';

  @override
  String get updateDownloading => 'جارٍ التنزيل…';

  @override
  String get updateOpenInstaller => 'فتح المُثبِّت…';

  @override
  String get updateRetry => 'إعادة المحاولة';

  @override
  String get updatePermissionBody =>
      'فعّل «تثبيت تطبيقات غير معروفة» لإنتشار بوينت، ثم اضغط تحديث مرة أخرى.';

  @override
  String get updatePermissionOpenSettings => 'فتح الإعدادات';

  @override
  String updateVersion(String version) {
    return 'الإصدار $version';
  }

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
  String get posReveal => 'إظهار الرمز';

  @override
  String get posRevealing => 'جارٍ الإظهار…';

  @override
  String get posRevealWarning =>
      'إظهار الرمز يكشف الكود ويحدّد القسيمة كمُستخدَمة — لا يمكن التراجع.';

  @override
  String get posPinHidden => 'مخفي حتى الإظهار';

  @override
  String get posDone => 'تم';

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

  @override
  String get languageLabel => 'اللغة';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonSeedSuccess => 'تم إدخال بيانات التجربة بنجاح!';

  @override
  String commonUpdateFailed(String error) {
    return 'فشل التحديث: $error';
  }

  @override
  String commonDeleteFailed(String error) {
    return 'فشل الحذف: $error';
  }

  @override
  String get loginWelcomeBack => 'مرحباً بعودتك';

  @override
  String get loginSubtitle =>
      'سجّل دخولك للمتابعة. استخدم رقم الهاتف وكلمة المرور الصادرَين من المدير.';

  @override
  String get loginFieldRequired => 'هذا الحقل مطلوب';

  @override
  String get loginServerEndpoint => 'نقطة اتصال الخادم';

  @override
  String get loginBaseUrlLabel => 'عنوان الخادم الأساسي';

  @override
  String get loginSaveEndpoint => 'حفظ العنوان';

  @override
  String get loginAuthDeclined => 'فشل تسجيل الدخول';

  @override
  String get loginNoUsersTitle => 'لا يوجد مستخدمون مسجّلون';

  @override
  String get loginNoUsersDefault =>
      'الافتراضي: هاتف 07701234567 · كلمة المرور \"password\"';

  @override
  String get loginBrandTagline =>
      'اضغط، اشحن، وانطلق. أدِر مملكة القسائم من شاشة واحدة.';

  @override
  String get loginBrandTaglineShort => 'اضغط، اشحن، وانطلق.';

  @override
  String get splashTagline => 'توزيع القسائم بكل سهولة.';

  @override
  String get dashboardWelcomeBack => 'أهلًا بعودتك،';

  @override
  String get dashboardQuickActions => 'الإجراءات السريعة';

  @override
  String get dashboardOperatingNotes => 'ملاحظات التشغيل';

  @override
  String get dashboardChildrenNote => 'الجهات الفرعية المباشرة';

  @override
  String get dashboardProducts => 'المنتجات';

  @override
  String get dashboardProductsNote => 'المرتبطة بهذه الجهة';

  @override
  String get dashboardActionHierarchyDesc => 'إدارة سلسلة التوزيع';

  @override
  String get dashboardActionCatalogDesc => 'تحديد القسائم والأسعار';

  @override
  String get dashboardActionTemplatesDesc =>
      'صمّم إيصال الطباعة الحراري ورمز QR لكل منتج.';

  @override
  String get dashboardActionInventoryHqDesc => 'استعراض المخزون المطبوع';

  @override
  String get dashboardActionBatchAddDesc => 'إصدار دفعة جديدة من القسائم';

  @override
  String get dashboardActionTransactionsDesc => 'نقل المخزون بين الجهات';

  @override
  String get dashboardActionChildrenAgent1Desc => 'إدارة الموزعين والمتاجر';

  @override
  String get dashboardActionInventoryAgentDesc =>
      'فحص القسائم المتوفرة في المخزون';

  @override
  String get dashboardActionTransactionsAgentDesc => 'إصدار المخزون واستلامه';

  @override
  String get dashboardActionChildrenAgent2Desc => 'إدارة المتاجر المخصصة';

  @override
  String get dashboardActionInventoryStoreDesc =>
      'عرض مخزون المنفذ بصورة سريعة';

  @override
  String get dashboardActionTransactionsStoreDesc =>
      'الإيصالات الواردة من الجهة العليا';

  @override
  String get dashboardOpenPos => 'تشغيل نقطة البيع';

  @override
  String get dashboardActionOpenPosDesc => 'الطباعة عند منفذ البيع';

  @override
  String get dashboardNoteHq1 =>
      'أصدر قسائم جديدة وأرسلها عبر الإضافة الجماعية — يتحكم الكتالوج في كل قسيمة مطبوعة.';

  @override
  String get dashboardNoteHq2 =>
      'تؤثر تغييرات التسلسل الهرمي في مسار المخزون؛ راجع السلسلة قبل إصدار أي معاملة.';

  @override
  String get dashboardNoteHq3 => 'اضغط مطولًا على الشعار لفتح تشخيصات الخادم.';

  @override
  String get dashboardNoteAgent1 =>
      'أرسل المخزون إلى الجهات الفرعية قبل أن تطلبه — الطباعة عند الطلب تفشل حين تكون الرفوف فارغة.';

  @override
  String get dashboardNoteAgent2 =>
      'يستعلم الخادم عن المعاملات كل ثانية؛ امنح ما يصل إلى ثلاثين ثانية لاكتمال المعالجة.';

  @override
  String get dashboardNoteStore1 =>
      'افتح نقطة البيع لتشغيل المنفذ. تُسجَّل كل قسيمة مطبوعة بحالة «مطبوعة» على الخادم.';

  @override
  String get dashboardNoteStore2 =>
      'لا يمكن التراجع عن حالة «مطبوعة» إلا من قِبَل المسؤول.';

  @override
  String get healthDiagnosticsTitle => 'التشخيصات';

  @override
  String get healthRefresh => 'تحديث';

  @override
  String get healthConnectionSection => 'الاتصال';

  @override
  String get healthBaseUrl => 'رابط الخادم';

  @override
  String get healthJwt => 'رمز JWT';

  @override
  String get healthChecksSection => 'الحالة الصحية للنظام';

  @override
  String get healthNoResults => 'لا توجد نتائج بعد.';

  @override
  String get healthFailed => 'فشل';

  @override
  String get entityTypeInteshar => 'منصة انتشار';

  @override
  String get entityTypeAgent1 => 'الوكيل الرئيسي';

  @override
  String get entityTypeAgent2 => 'الوكيل الفرعي';

  @override
  String get entityTypeStore => 'متجر';

  @override
  String get entityTypeUser => 'مستخدم';

  @override
  String get entityTreeSubtitle =>
      'عرض شامل للجهات التابعة لك وفق ترتيب العرض على المستويات.';

  @override
  String get entityTreeLevels => 'مستويات';

  @override
  String get entityTreeEntities => 'جهات';

  @override
  String get entityTreeNoChildren => 'لا توجد فروع مسجّلة بعد.';

  @override
  String get entityTreeRefresh => 'تحديث';

  @override
  String get entityTreeRoot => 'الجذر';

  @override
  String entityTreeLevel(String level) {
    return 'المستوى $level';
  }

  @override
  String entityTreeEntityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جهة',
      few: '$count جهات',
      two: 'جهتان',
      one: 'جهة واحدة',
    );
    return '$_temp0';
  }

  @override
  String entityTreeChildrenCount(int count) {
    return '$count فرع';
  }

  @override
  String entityTreeProductsCount(int count) {
    return '$count منتج';
  }

  @override
  String get entityTreeActions => 'الإجراءات';

  @override
  String get entityTreeEdit => 'تعديل';

  @override
  String get entityTreeManageUsers => 'إدارة المستخدمين';

  @override
  String get entityTreeAddChild => 'إضافة فرع';

  @override
  String get entityTreeDelete => 'حذف';

  @override
  String get entityTreeIdent => 'المعرّف';

  @override
  String get entityTreeParentLabel => 'الجهة الأم';

  @override
  String entityTreeAmendTitle(String typeName) {
    return 'تعديل $typeName';
  }

  @override
  String entityTreeAddChildTitle(String typeName) {
    return 'إضافة $typeName';
  }

  @override
  String get entityTreeDeleteTitle => 'حذف الجهة';

  @override
  String entityTreeDeleteConfirm(String name) {
    return 'هل تريد حذف \"$name\"؟ لا يمكن التراجع عن هذا الإجراء.';
  }

  @override
  String get entityTreeCancel => 'إلغاء';

  @override
  String get entityTreeDeleteFailed => 'فشل الحذف. يرجى المحاولة مرة أخرى.';

  @override
  String get entityTreeSectionLabel => 'تعديل الهيكل التنظيمي';

  @override
  String get entityTreeFieldName => 'الاسم *';

  @override
  String get entityTreeFieldSlogan => 'الشعار';

  @override
  String get entityTreeFieldDescription => 'الوصف';

  @override
  String get entityTreeSave => 'حفظ';

  @override
  String get entityTreeErrorSaving => 'حدث خطأ أثناء الحفظ.';

  @override
  String get entityTreeColEntity => 'الجهة';

  @override
  String get entityTreeColChildren => 'الفروع';

  @override
  String get entityTreeColVouchers => 'القسائم';

  @override
  String get entityFieldLogoUrl => 'رابط الشعار';

  @override
  String get entityFieldPrimaryColor => 'اللون الأساسي (hex)';

  @override
  String get entityFieldSecondaryColor => 'اللون الثانوي (hex)';

  @override
  String get entityFieldLowStockThreshold => 'حد تنبيه نقص المخزون';

  @override
  String get entityFieldLowStockThresholdHelp =>
      'يُعلَّم المنتج كمنخفض عندما تقل وحداته المتاحة عن هذا الحد. اتركه فارغًا لاستخدام الافتراضي.';

  @override
  String get manageUsersSectionLabel => 'سجل المستخدمين';

  @override
  String get manageUsersTitle => 'إدارة المستخدمين';

  @override
  String get manageUsersEmpty =>
      'لا يوجد مستخدمون مسجّلون. أضف مستخدماً أدناه.';

  @override
  String get manageUsersNewUser => 'مستخدم جديد';

  @override
  String get manageUsersPhone => 'الهاتف *';

  @override
  String get manageUsersPassword => 'كلمة المرور *';

  @override
  String get manageUsersRole => 'الدور';

  @override
  String get manageUsersRegisterButton => 'تسجيل مستخدم';

  @override
  String get manageUsersSave => 'حفظ السجل';

  @override
  String get manageUsersPhoneRequired => 'رقم الهاتف مطلوب';

  @override
  String get manageUsersPasswordRequired => 'كلمة المرور مطلوبة';

  @override
  String get manageUsersPhoneDuplicate => 'يوجد مستخدم بهذا الرقم مسبقاً';

  @override
  String get manageUsersAtLeastOne => 'يجب تسجيل مستخدم واحد على الأقل';

  @override
  String get manageUsersErrorSaving => 'حدث خطأ أثناء الحفظ.';

  @override
  String get batchAddEyebrow => 'المخزون';

  @override
  String get batchAddTitle => 'إضافة قسائم';

  @override
  String get batchAddSubtitle =>
      'أضف قسيمة واحدة يدوياً، أو استورد دفعة عبر قالب XLSX.';

  @override
  String get batchAddTabSingle => 'فردي';

  @override
  String get batchAddTabCsvXlsx => 'CSV / XLSX';

  @override
  String get batchAddDenomination => 'الفئة';

  @override
  String get batchAddProductDefinition => 'تعريف المنتج';

  @override
  String batchAddImportedProducts(int count) {
    return 'تم استيراد $count منتج بنجاح!';
  }

  @override
  String get batchAddCsvFormat => 'تنسيق الملف';

  @override
  String get batchAddRequiredColumns => 'الأعمدة المطلوبة';

  @override
  String get batchAddDownloadTemplate => 'تنزيل قالب XLSX';

  @override
  String get batchAddTemplateSaved => 'تم حفظ القالب.';

  @override
  String get batchAddPickFile => 'اختر ملف CSV / XLSX';

  @override
  String get batchAddErrorReadBytes => 'تعذّرت قراءة بيانات الملف.';

  @override
  String get batchAddXlsxBadHeader =>
      'يجب أن يحتوي ملف XLSX على عمودَي \'serialNumber\' و \'pin\' في الترويسة.';

  @override
  String batchAddDuplicateRow(int index, String serial) {
    return 'الصف $index: الرقم التسلسلي \'$serial\' موجود مسبقاً في مخزون هذه الجهة.';
  }

  @override
  String get batchAddPreview => 'معاينة';

  @override
  String batchAddRowCount(int count) {
    return '$count صف';
  }

  @override
  String get batchAddColSerial => 'الرقم التسلسلي';

  @override
  String get batchAddColPin => 'الرقم السري';

  @override
  String batchAddMoreRows(int count) {
    return '+ $count صف إضافي';
  }

  @override
  String batchAddProgressImported(int done, int total) {
    return 'تم استيراد $done / $total';
  }

  @override
  String batchAddImportRows(int count) {
    return 'استيراد $count صف';
  }

  @override
  String batchAddFailedAtRow(int index, String error) {
    return 'فشل عند الصف $index: $error';
  }

  @override
  String get batchAddPrinting => 'جارٍ الطباعة';

  @override
  String get addVoucherDenomination => 'الفئة';

  @override
  String get addVoucherSerial => 'الرقم التسلسلي';

  @override
  String get addVoucherPin => 'الرمز السري';

  @override
  String get addVoucherSave => 'حفظ القسيمة';

  @override
  String get addVoucherSerialRequired => 'الرقم التسلسلي مطلوب';

  @override
  String get addVoucherPinRequired => 'الرمز السري مطلوب';

  @override
  String addVoucherDuplicateSerial(String serial) {
    return 'الرقم التسلسلي \'$serial\' موجود مسبقاً في مخزون هذه الجهة.';
  }

  @override
  String get addVoucherSaved => 'تم حفظ القسيمة.';

  @override
  String get defsFormTitleNew => 'تعريف منتج جديد';

  @override
  String get defsFormTitleEdit => 'تعديل تعريف المنتج';

  @override
  String get defsDeleteTitle => 'حذف تعريف المنتج';

  @override
  String defsDeleteConfirm(String name) {
    return 'هل تريد حذف \"$name\"؟ قد يؤثر ذلك على المنتجات الحالية.';
  }

  @override
  String get defsCancel => 'إلغاء';

  @override
  String get defsDelete => 'حذف';

  @override
  String get defsSubtitle => 'السجل الرئيسي لفئات القسائم الصادرة عن إنتشار.';

  @override
  String get defsTitlesLabel => 'عنوان';

  @override
  String get defsSearchHint => 'بحث بالاسم أو رمز المنتج أو الوصف…';

  @override
  String get defsEmptyFirst => 'لا توجد تعريفات منتجات بعد. أضف الفئة الأولى.';

  @override
  String defsEmptySearch(String query) {
    return 'لا توجد نتائج لـ \"$query\".';
  }

  @override
  String get defsAddFirst => 'إضافة أول تعريف';

  @override
  String get defsNewDenomination => 'فئة جديدة';

  @override
  String get defsPrice => 'السعر';

  @override
  String get defsEdit => 'تعديل';

  @override
  String get defsMintLabel => 'إنشاء فئة جديدة';

  @override
  String get defsAmendLabel => 'تعديل فئة موجودة';

  @override
  String get defsFieldName => 'الاسم *';

  @override
  String get defsFieldSku => 'رمز المنتج * (مثال: AC5)';

  @override
  String get defsFieldPrice => 'السعر الافتراضي (IQD) *';

  @override
  String get defsFieldDescription => 'الوصف';

  @override
  String get defsFieldId => 'المعرّف (يُنشأ تلقائياً)';

  @override
  String get defsSave => 'حفظ';

  @override
  String get inventoryEyebrow => 'العداد';

  @override
  String get inventorySubtitle =>
      'القسائم المملوكة حالياً لهذه الجهة — ابحث بالاسم أو رمز المنتج أو الرقم التسلسلي.';

  @override
  String get inventoryByGovernorate => 'حسب المحافظة';

  @override
  String get inventoryUntagged => 'بدون محافظة';

  @override
  String get inventoryLow => 'منخفض';

  @override
  String get inventoryStatusAvailable => 'متاح';

  @override
  String get inventoryStatusPrinted => 'مُستخدَم';

  @override
  String get inventoryStatusDamaged => 'تالف';

  @override
  String get inventoryStatusSentForPrinting => 'قيد الطباعة';

  @override
  String get inventoryStatusFailedPrinting => 'فشلت الطباعة';

  @override
  String get inventorySearchHint =>
      'بحث بالاسم أو رمز المنتج أو الرقم التسلسلي…';

  @override
  String get inventoryFilterAll => 'الكل';

  @override
  String get inventoryEmptyFirst => 'لا توجد منتجات مملوكة لهذه الجهة بعد.';

  @override
  String get inventoryEmptyFiltered =>
      'لا توجد منتجات تطابق معايير التصفية الحالية.';

  @override
  String get inventoryRefresh => 'تحديث';

  @override
  String inventoryUnitCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count وحدة',
      few: '$count وحدات',
      two: 'وحدتان',
      one: 'وحدة واحدة',
    );
    return '$_temp0';
  }

  @override
  String inventoryAvailableCount(int count) {
    return '$count متاح';
  }

  @override
  String inventoryPrintedCount(int count) {
    return '$count مُستخدَم';
  }

  @override
  String inventoryDamagedCount(int count) {
    return '$count تالف';
  }

  @override
  String get inventorySnLabel => 'ر.ت';

  @override
  String get inventoryChangeStatus => 'تغيير الحالة';

  @override
  String inventoryMarkStatus(String status) {
    return 'تعيين كـ $status';
  }

  @override
  String get inventoryValueLabel => 'قيمة المخزون';

  @override
  String get inventoryValueUnits => 'وحدة متاحة';

  @override
  String get inventoryLoadMore => 'تحميل المزيد';

  @override
  String inventoryShowingCount(int shown, int total) {
    return 'عرض $shown من $total';
  }

  @override
  String get inventoryNoCodes => 'لا توجد رموز للعرض.';

  @override
  String get inventoryLoadCodesFailed => 'تعذّر تحميل الرموز.';

  @override
  String get posHomeLiveCounter => 'العداد المباشر';

  @override
  String get posHomeSetupPrinter => 'إعداد الطابعة';

  @override
  String get posHomePickDenomination => 'اختر الفئة';

  @override
  String get posHomeCounterSubtitle => 'اطبع عند المنفذ من المخزون المتاح.';

  @override
  String get posHomeSearchHint => 'ابحث بالاسم أو رمز المنتج…';

  @override
  String get posHomeInStock => 'في المخزون';

  @override
  String get posHomeNoVouchers => 'لا توجد قسائم متاحة في المنفذ.';

  @override
  String posHomeNoMatches(String query) {
    return 'لا توجد نتائج لـ \"$query\".';
  }

  @override
  String get posHomePrint => 'طباعة';

  @override
  String get posHomeSell => 'بيع';

  @override
  String get posHomeScratchNote => 'اكشط الرمز عند نقطة الاستبدال فقط.';

  @override
  String get posHomePrinterNotConnected => 'الطابعة غير متصلة';

  @override
  String get posHomeCancel => 'إلغاء';

  @override
  String get posHomePrinting => 'جارٍ الطباعة…';

  @override
  String posHomeUpdateError(String error) {
    return 'تعذّر تحديث الحالة: $error';
  }

  @override
  String posHomePrintFailed(String error) {
    return 'فشلت الطباعة: $error';
  }

  @override
  String get printerPickerTitle => 'إعداد الطابعة';

  @override
  String get printerPickerConnectedManual => 'تم الاتصال عبر العنوان اليدوي';

  @override
  String printerPickerConnectionFailed(String error) {
    return 'فشل الاتصال: $error';
  }

  @override
  String printerPickerConnectedTo(String name) {
    return 'تم الاتصال بـ $name';
  }

  @override
  String get printerPickerTestPrintSent => 'تم إرسال الطباعة التجريبية!';

  @override
  String printerPickerPrintError(String error) {
    return 'خطأ في الطباعة: $error';
  }

  @override
  String get printerPickerConnected => 'متصل';

  @override
  String get printerPickerTestPrint => 'طباعة تجريبية';

  @override
  String get printerPickerDisconnect => 'قطع الاتصال';

  @override
  String get printerPickerManualAddress => 'العنوان اليدوي';

  @override
  String get printerPickerManualHint =>
      'استخدم هذا الخيار عندما لا تظهر الطابعة في قائمة البحث.';

  @override
  String get printerPickerEnterMac => 'أدخل عنوان MAC';

  @override
  String get printerPickerMacFormat => 'الصيغة: XX:XX:XX:XX:XX:XX';

  @override
  String get printerPickerMacLabel => 'عنوان MAC للبلوتوث';

  @override
  String get printerPickerPair => 'اقتران';

  @override
  String get printerPickerNearbyDevices => 'الأجهزة المجاورة';

  @override
  String get printerPickerRescan => 'إعادة البحث';

  @override
  String get printerPickerNoDevices =>
      'لم يتم العثور على أجهزة. تأكد من تشغيل البلوتوث وتشغيل الطابعة.';

  @override
  String get printerPickerUnknown => 'غير معروف';

  @override
  String get newTxnTitle => 'معاملة جديدة';

  @override
  String get newTxnIssueStock => 'إصدار مخزون';

  @override
  String get newTxnIssueStockHint =>
      'اختر الجهة المستلمة، حدد الفئات، ثم أرسل الطلب. يقوم الخادم بالاستعلام كل ثانية؛ انتظر حتى 30 ثانية لاستقرار دفتر الحسابات.';

  @override
  String get newTxnManifestLines => 'بنود البيان';

  @override
  String get newTxnAddLine => 'إضافة بند';

  @override
  String get newTxnGrandTotal => 'الإجمالي الكلي';

  @override
  String newTxnUnitsCount(int count) {
    return '$count وحدة';
  }

  @override
  String get newTxnSource => 'المصدر';

  @override
  String get newTxnDestination => 'الجهة المستلمة';

  @override
  String get newTxnNoChildren => 'لا توجد جهات فرعية';

  @override
  String get newTxnNoChildrenHint =>
      'أضف جهة فرعية من شاشة التسلسل الهرمي أولاً';

  @override
  String get newTxnChooseEntity => 'اختر الجهة';

  @override
  String get newTxnProduct => 'المنتج';

  @override
  String get newTxnQty => 'الكمية';

  @override
  String get newTxnUnitPrice => 'سعر الوحدة (د.ع.)';

  @override
  String get newTxnLineTotal => 'إجمالي البند';

  @override
  String get newTxnPosting => 'جارٍ الإرسال…';

  @override
  String get newTxnSubmit => 'إرسال المعاملة';

  @override
  String get newTxnPostedToLedger => 'تم الترحيل إلى دفتر الحسابات';

  @override
  String get newTxnDeclined => 'تم رفض المعاملة';

  @override
  String get newTxnResultPosted => 'مُرحَّلة';

  @override
  String get newTxnResultDeclined => 'مرفوضة';

  @override
  String newTxnRef(String id) {
    return 'المرجع · $id';
  }

  @override
  String get newTxnReturnToTransactions => 'العودة إلى المعاملات';

  @override
  String get txnsSubtitle =>
      'حركات المخزون من وإلى هذه الجهة، مرتبة من الأحدث إلى الأقدم.';

  @override
  String get txnsTallyOut => 'صادر';

  @override
  String get txnsTallyIn => 'وارد';

  @override
  String get txnsTallyDone => 'مكتمل';

  @override
  String get txnsEmpty =>
      'لا توجد معاملات في دفتر الحسابات لهذه الجهة حتى الآن.';

  @override
  String get txnsCreateAction => 'إنشاء معاملة';

  @override
  String get txnsDirectionTo => 'إلى';

  @override
  String get txnsDirectionFrom => 'من';

  @override
  String txnsUnitLineSummary(int units, int lines) {
    return '$units وحدة · $lines بند';
  }

  @override
  String get txnsViewDetails => 'عرض التفاصيل';

  @override
  String get txnsDetailTitle => 'تفاصيل المعاملة';

  @override
  String get txnsFrom => 'من';

  @override
  String get txnsTo => 'إلى';

  @override
  String get txnsMetaReference => 'المرجع';

  @override
  String get txnsMetaIssued => 'تاريخ الإصدار';

  @override
  String get txnsMetaNote => 'ملاحظة';

  @override
  String get txnsLineItems => 'البنود';

  @override
  String get txnsColSku => 'رمز المنتج';

  @override
  String get txnsColQty => 'الكمية';

  @override
  String get txnsColUnit => 'سعر الوحدة';

  @override
  String get txnsColTotal => 'الإجمالي';

  @override
  String get txnStatusPending => 'قيد الانتظار';

  @override
  String get txnStatusProcessing => 'قيد المعالجة';

  @override
  String get txnStatusComplete => 'مكتملة';

  @override
  String get txnStatusFailed => 'فشلت';

  @override
  String get appShellActiveEntity => 'الجهة الحالية';

  @override
  String get emptyStateTitle => 'لا يوجد شيء هنا بعد';

  @override
  String get errorStateErrorLabel => 'خطأ';

  @override
  String get errorStateTitle => 'حدث خطأ أثناء تنفيذ هذا الطلب.';

  @override
  String get vtTitle => 'قوالب القسائم';

  @override
  String get vtSubtitle =>
      'صمّم القسيمة المطبوعة لكل منتج — الترويسة والحقول ورمز QR قابل للمسح.';

  @override
  String get vtSelectPrompt => 'اختر منتجًا لتعديل قالبه';

  @override
  String get vtHeaderText => 'نص الترويسة';

  @override
  String get vtFields => 'الحقول';

  @override
  String get vtShowProductName => 'إظهار اسم المنتج';

  @override
  String get vtShowSerial => 'إظهار الرقم التسلسلي';

  @override
  String get vtShowPin => 'إظهار الرمز السري';

  @override
  String get vtShowPrice => 'إظهار السعر';

  @override
  String get vtQrSection => 'رمز QR';

  @override
  String get vtQrEnabled => 'تفعيل رمز QR';

  @override
  String get vtQrSource => 'محتوى الرمز';

  @override
  String get vtQrSourcePin => 'الرمز السري';

  @override
  String get vtQrSourceSerial => 'التسلسلي';

  @override
  String get vtQrPrefix => 'بادئة الرمز';

  @override
  String get vtQrSuffix => 'لاحقة الرمز';

  @override
  String get vtQrExample => 'يُمسح كـ';

  @override
  String get vtRedeemInstructions => 'تعليمات الاستخدام';

  @override
  String get vtFooterText => 'نص التذييل';

  @override
  String get vtPreview => 'معاينة حية';

  @override
  String get vtSave => 'حفظ القالب';

  @override
  String get vtSaved => 'تم حفظ القالب';

  @override
  String get vtSaveFailed => 'تعذّر حفظ القالب';

  @override
  String get vtEmpty => 'لا توجد منتجات بعد — أنشئ منتجًا في الكتالوج أولًا.';

  @override
  String get dashKpiStock => 'القسائم في المخزون';

  @override
  String get dashKpiTransactions => 'المعاملات';

  @override
  String get dashKpiLowStock => 'منتجات منخفضة المخزون';

  @override
  String get dashPlatformOverview => 'نظرة عامة على المنصة';

  @override
  String get dashKpiDirectChildren => 'فروع مباشرة';

  @override
  String dashKpiSkusCount(int count) {
    return '$count منتج';
  }

  @override
  String get dashKpiThisAccount => 'هذا الحساب';

  @override
  String get dashKpiAllHealthy => 'كل شيء بخير';

  @override
  String get dashKpiNeedsAttention => 'يحتاج إلى مراجعة';

  @override
  String get dashRecentTransactions => 'آخر المعاملات';

  @override
  String get dashLowStock => 'مخزون منخفض';

  @override
  String get dashViewAll => 'عرض الكل';

  @override
  String get dashColRoute => 'المسار';

  @override
  String get dashColSku => 'المنتج';

  @override
  String get dashColQty => 'الكمية';

  @override
  String get dashColStatus => 'الحالة';

  @override
  String get dashColAmount => 'المبلغ';

  @override
  String get dashUnitsLeft => 'متبقٍ';

  @override
  String get dashAllHealthy => 'مستويات المخزون جيدة';

  @override
  String get dashNoTransactions => 'لا توجد معاملات بعد';

  @override
  String get navSystemActivity => 'نشاط النظام';

  @override
  String get sysActSubtitle =>
      'تدفّق تشغيلي مباشر عبر المنصة — الأحداث والمعاملات والكيانات والمستخدمون.';

  @override
  String get sysActActivity => 'النشاط';

  @override
  String get sysActEntities => 'الكيانات';

  @override
  String get sysActUsers => 'المستخدمون';

  @override
  String get sysActStores => 'المتاجر';

  @override
  String get sysActFailed => 'فاشلة';

  @override
  String get sysActLevelInfo => 'معلومات';

  @override
  String get sysActLevelWarn => 'تحذيرات';

  @override
  String get sysActLevelError => 'أخطاء';

  @override
  String get sysActFailuresOnly => 'الإخفاقات فقط';

  @override
  String get sysActSearchPath => 'تصفية حسب المسار…';

  @override
  String get sysActSearchEntities => 'ابحث في الكيانات…';

  @override
  String get sysActSearchUsers => 'ابحث برقم الهاتف…';

  @override
  String get sysActNoEvents => 'لا توجد أحداث نشاط تطابق هذه المرشّحات.';

  @override
  String get sysActNoEntities => 'لا توجد كيانات.';

  @override
  String get sysActNoUsers => 'لا يوجد مستخدمون.';

  @override
  String get sysActAdminOnly =>
      'تعذّر تفويض هذا الطلب. قد تكون جلستك قد انتهت، أو لا يملك هذا الحساب صلاحية المسؤول.';

  @override
  String get sysActReauth => 'تسجيل الدخول من جديد';

  @override
  String sysActUsersCount(int count) {
    return '$count مستخدم';
  }

  @override
  String get sysActRoleAdmin => 'مسؤول';

  @override
  String get sysActSourceServer => 'الخادم';

  @override
  String get sysActSourceClient => 'العميل';

  @override
  String get sysActDetailTitle => 'تفاصيل الحدث';

  @override
  String get sysActFieldTime => 'الوقت';

  @override
  String get sysActFieldSource => 'المصدر';

  @override
  String get sysActFieldLevel => 'المستوى';

  @override
  String get sysActFieldMethod => 'الطريقة';

  @override
  String get sysActFieldPath => 'المسار';

  @override
  String get sysActFieldAction => 'الإجراء';

  @override
  String get sysActFieldUser => 'المستخدم';

  @override
  String get sysActFieldEntity => 'الكيان';

  @override
  String get sysActFieldPlatform => 'المنصة';

  @override
  String get sysActFieldSurface => 'الواجهة';

  @override
  String get sysActFieldDevice => 'الجهاز';

  @override
  String get sysActFieldAppVersion => 'إصدار التطبيق';

  @override
  String get sysActFieldDuration => 'المدة';

  @override
  String get sysActFieldIp => 'عنوان IP';

  @override
  String get sysActFieldCorrelation => 'معرّف الارتباط';

  @override
  String get sysActFieldError => 'الخطأ';

  @override
  String get sysActFieldStack => 'أثر التتبع';

  @override
  String sysActDurationMs(int ms) {
    return '$ms مللي ثانية';
  }

  @override
  String get navMainAgents => 'الوكلاء الرئيسيون';

  @override
  String get navSubAgents => 'الوكلاء الفرعيون';

  @override
  String get navCompanies => 'الشركات';

  @override
  String get navStores => 'نقاط البيع';

  @override
  String get navPrices => 'الأسعار';

  @override
  String get batchAddGovernorate => 'المحافظة (تقييد المنطقة)';

  @override
  String get batchAddNotGeoLocked => 'غير مقيّد بمحافظة';

  @override
  String get newTxnNoRegionRestriction => 'بدون تقييد محافظة';

  @override
  String newTxnDeliverableHint(String coverage) {
    return 'سيتم تسليم الكروت الخاصة بـ $coverage فقط (بالإضافة إلى الكروت غير المقيّدة بمحافظة).';
  }
}
