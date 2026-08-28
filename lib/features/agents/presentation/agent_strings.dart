import 'package:flutter/widgets.dart';
import 'package:inteshar/features/agents/domain/agent_tier.dart';

/// Self-contained Arabic/English strings for the agent-management feature, shared
/// by the Main Agents and Sub Agents pages (the wording branches on [AgentTier]).
/// Kept local rather than in the shared ARBs to avoid ballooning the app-wide
/// localization surface for two admin screens.
class AgentStrings {
  final bool ar;
  final AgentTier tier;
  const AgentStrings(this.ar, this.tier);

  factory AgentStrings.of(BuildContext context, AgentTier tier) =>
      AgentStrings(Localizations.localeOf(context).languageCode == 'ar', tier);

  String pick(String en, String arText) => ar ? arText : en;
  bool get _sub => tier == AgentTier.sub;

  // ── List page ──
  String get navTitle => _sub ? pick('Sub Agents', 'الوكلاء الفرعيون') : pick('Main Agents', 'الوكلاء الرئيسيون');
  String get pageTitle => navTitle;
  String get pageEyebrow => pick('Administration', 'الإدارة');
  String get pageSubtitle => _sub
      ? pick('Create and manage sub agents under main agents', 'إنشاء وإدارة الوكلاء الفرعيين التابعين للوكلاء الرئيسيين')
      : pick('Create and manage main distributors', 'إنشاء وإدارة الوكلاء الرئيسيين');
  String get searchHint => pick('Search by name or ID', 'بحث بالاسم أو المعرف');
  String get newAgent => _sub ? pick('New Sub Agent', 'وكيل فرعي جديد') : pick('New Main Agent', 'وكيل رئيسي جديد');
  String get empty => _sub ? pick('No sub agents yet', 'لا يوجد وكلاء فرعيون بعد') : pick('No main agents yet', 'لا يوجد وكلاء رئيسيون بعد');
  String get emptyHint => _sub
      ? pick('Onboard a sub agent under a main agent.', 'أضف وكيلاً فرعياً تابعاً لوكيل رئيسي.')
      : pick('Onboard your first main distributor.', 'ابدأ بإضافة أول وكيل رئيسي.');
  String get loadMore => pick('Load more', 'تحميل المزيد');
  String get coverage => pick('Coverage', 'التغطية');
  String get noRegions => pick('No governorates', 'لا توجد محافظات');
  String usersCount(int n) => pick('$n users', '$n مستخدم');
  String childrenCount(int n) => _sub
      ? pick('$n points of sale', '$n نقطة بيع')
      : pick('$n sub-agents', '$n وكيل فرعي');
  String get edit => pick('Edit', 'تعديل');
  String get delete => pick('Delete', 'حذف');

  // ── Readiness (UX-02) ──
  // Creating an agent used to pop straight back to this list with nothing to say
  // that the new account has no cards, no POS points and no prices — four
  // unlinked screens and no completion state anywhere, so the remaining steps
  // were learned from a support ticket weeks later.
  String get setupTitle => pick('Setup', 'التهيئة');
  String get setupCards => pick('Cards', 'الكروت');
  String get setupCardsNone => pick('No cards yet', 'لا توجد كروت');
  String setupCardsSome(int n) => pick('$n cards', '$n كرت');
  String get setupSlots => pick('POS points', 'نقاط البيع');
  String get setupSlotsNone => pick('No POS points', 'لا توجد نقاط بيع');
  /// `available` is what is still FREE to open a shop with; `total` is what the
  /// agent was ever given. Points already passed down to sub-agents are in
  /// neither — saying "used" would have folded them in and overstated capacity.
  String setupSlotsSome(int available, int total) =>
      pick('$available free of $total', '$available متاحة من $total');
  String get setupPrices => pick('Prices', 'الأسعار');
  String setupPricesMissing(int n) => pick('$n unpriced', '$n بدون سعر');
  // NOT "everything is priced": the server only reports agents HOLDING stock in
  // an unpriced category, so absence from that list means exactly this much.
  String get setupPricesOk =>
      pick('No unpriced stock', 'لا يوجد مخزون بدون سعر');
  String get setupProducts => visibleProducts;
  String get setupProductsAction => pick('Choose', 'اختيار');
  String get setupUnknown => pick('Not checked', 'غير معروف');

  /// UX-103: which voucher SKUs this agent (and its subtree) may see and sell.
  /// It is a commercial control, and until now its only entry point in the whole
  /// app was one item on a hierarchy-tree row menu — no nav, no page, no search.
  String get visibleProducts => pick('Visible products', 'المنتجات المتاحة');
  // The delete-dialog strings that used to live here are gone with the dialog:
  // deleting an agent goes through the shared clear-out sheet, which carries its
  // own wording (and, unlike the dialog, an authenticator code).
  String get cancel => pick('Cancel', 'إلغاء');

  // ── Form ──
  String get createTitle => newAgent;
  String get editTitle => _sub ? pick('Edit Sub Agent', 'تعديل الوكيل الفرعي') : pick('Edit Main Agent', 'تعديل الوكيل الرئيسي');
  String get stepDetails => pick('Details', 'البيانات');
  String get stepUsers => _sub ? pick('User', 'المستخدم') : pick('Users', 'المستخدمون');
  String get next => pick('Next', 'التالي');
  String get back => pick('Back', 'السابق');
  String get save => pick('Save', 'حفظ');
  String get create => pick('Create', 'إنشاء');

  // Parent (sub only)
  String get sectionParent => pick('Parent main agent', 'الوكيل الرئيسي التابع له');
  String get fieldParent => pick('Belongs to', 'تابع لـ');
  String get parentHint => pick(
      'Select the main agent this sub agent reports to — its coverage limits the governorates below.',
      'اختر الوكيل الرئيسي الذي يتبعه هذا الوكيل الفرعي — تغطيته تحدد المحافظات أدناه.');
  String get errParentRequired => pick('Select a parent main agent', 'اختر الوكيل الرئيسي التابع له');
  /// Placeholder in the parent field before anything is picked (UX-14). It must
  /// read as unanswered — the old dropdown showed nothing at all there.
  String get parentNotChosen => pick('Not chosen yet', 'لم يُختر بعد');
  String get noMainAgents => pick('No main agents exist yet — create one first.', 'لا يوجد وكلاء رئيسيون — أنشئ واحداً أولاً.');

  String get sectionIdentity => pick('Identity', 'الهوية');
  String get fieldName => pick('Commercial name', 'الاسم التجاري');
  String get fieldSlogan => pick('Slogan (optional)', 'الشعار النصي (اختياري)');
  String get fieldDescription => pick('Description (optional)', 'الوصف (اختياري)');

  // ── Operational limits (UX-03) ──
  // These five used to live ONLY in the hierarchy tree's own edit sheet, which
  // never mentioned this form and vice versa. An admin editing "the agent" from
  // the Main/Sub Agent pages — the natural place — could not reach the low-stock
  // threshold or the bulk limit, and had no way to learn they existed.
  String get sectionLimits => pick('Operational limits', 'حدود التشغيل');
  String get limitsHint => pick(
      'Stock alerts and how much this agent may sell in one bulk request.',
      'تنبيهات المخزون ومقدار ما يمكن لهذا الوكيل بيعه في عملية جملة واحدة.');
  String get fieldLowStock => pick('Low-stock alert level', 'حد تنبيه نفاد المخزون');
  String lowStockHint(int fallback) => pick(
      'Alert when a product drops below this many cards. Blank uses $fallback.',
      'ينبّه عندما ينخفض المنتج عن هذا العدد من الكروت. الفراغ يعني $fallback.');
  String get fieldBulkLimit =>
      pick('Bulk sale limit (cards per sale)', 'حد البيع بالجملة (بطاقات/عملية)');
  String get bulkLimitHint => pick(
      'Blank inherits from the parent. 1 disables bulk selling.',
      'اتركه فارغًا للتوريث. 1 يعطّل البيع بالجملة.');
  String get bulkUnlockLabel =>
      pick('Let this agent edit the limit', 'السماح للوكيل بتعديل الحد');
  String get bulkUnlockHint => pick(
      'When off, only HQ sets the limit for this account and everything under it.',
      'عند التعطيل، الإدارة وحدها تحدد الحد لهذا الحساب وكل ما تحته.');
  String get errNumberInvalid => pick('Enter a valid whole number', 'أدخل رقمًا صحيحًا');
  // These label upload fields — a thumbnail with an Upload button, no text box
  // anywhere. "URL" told the operator to paste something they were never given.
  String get fieldLogo => pick('Logo (optional)', 'الشعار (اختياري)');
  // B-127: a sub agent covers ONE governorate; a main agent may span several.
  // The label has to say which, or the single-choice behaviour reads as a bug.
  String get sectionGovernorates => _sub
      ? pick('Governorate', 'المحافظة')
      : pick('Governorates (coverage)', 'المحافظات (التغطية)');
  String get governoratesHint => _sub
      ? pick('A sub agent covers a single governorate — choosing another replaces it.',
          'الوكيل الفرعي يغطي محافظة واحدة — اختيار محافظة أخرى يستبدلها.')
      : pick('Select every governorate this agent operates in.', 'اختر كل محافظة يعمل بها هذا الوكيل.');
  String get sectionOwner => pick('Owner & contact', 'المالك والتواصل');
  String get fieldOwnerName => pick('Owner full name', 'اسم المالك الثلاثي');
  String get fieldDocuments => pick('Identity documents', 'صور المستمسكات');

  /// Onboarding stalls here more than anywhere else, so it says what to attach
  /// rather than leaving the operator to guess from an empty grid.
  String get documentsHint => pick(
      'Attach a photo of each document — national ID or passport, residence card, '
          'and the business licence if there is one.',
      'أرفق صورة لكل مستمسك — البطاقة الوطنية أو الجواز، بطاقة السكن، وإجازة الممارسة إن وُجدت.');
  String get fieldLandmark => pick('Nearest landmark', 'أقرب نقطة دالة');
  String get fieldLat => pick('Latitude', 'خط العرض');
  String get fieldLng => pick('Longitude', 'خط الطول');
  String get pickOnMap => pick('Pick on map', 'اختر على الخريطة');
  String get fieldPhone => pick('Contact phone', 'هاتف التواصل');
  String get fieldEmail => pick('Contact email', 'البريد الإلكتروني');
  String get sectionBranding => pick('Branding (optional)', 'الهوية البصرية (اختياري)');
  String get brandingHint => pick(
      'Your logo, colours and background apply across the app and the POS for everyone under you.',
      'يُطبَّق شعارك وألوانك والخلفية على كامل التطبيق ونقاط البيع لكل من تحتك.');
  String get fieldPrimary => pick('Main color (hex)', 'اللون الرئيسي (hex)');
  String get fieldSecondary => pick('Accent color (hex)', 'لون التمييز (hex)');
  String get fieldBackground => pick('Background image (optional)', 'صورة الخلفية (اختياري)');

  String get usersSubtitle => _sub
      ? pick('A single admin user. Sub agents cannot set card prices.', 'مستخدم مدير واحد. لا يمكن للوكلاء الفرعيين تسعير الكروت.')
      : pick('One admin over the agency, plus up to three flagged users.', 'مدير واحد على الوكالة، مع ثلاثة مستخدمين بصلاحيات محددة كحد أقصى.');
  String get addUser => pick('Add user', 'إضافة مستخدم');
  String userN(int i) => pick('User $i', 'المستخدم $i');
  String get adminUserLabel => pick('Admin user', 'المستخدم المدير');
  String get fieldUserPhone => pick('Phone (login)', 'الهاتف (الدخول)');
  String get fieldUserPassword => pick('Password', 'كلمة المرور');
  String get fieldUserPasswordKeep => pick('Password (blank = keep)', 'كلمة المرور (فارغ = إبقاء)');
  String get fieldPreset => pick('Role / permissions', 'الدور / الصلاحيات');
  String get removeUser => pick('Remove', 'إزالة');

  // ── Validation / results ──
  String get errNameRequired => pick('Commercial name is required', 'الاسم التجاري مطلوب');
  String get errGovRequired => pick('Select at least one governorate', 'اختر محافظة واحدة على الأقل');
  String get errEmailInvalid => pick('Enter a valid email address', 'أدخل بريدًا إلكترونيًا صحيحًا');
  String get errGeoInvalid => pick('Latitude must be -90..90 and longitude -180..180', 'خط العرض بين -90 و90 وخط الطول بين -180 و180');
  String get errUsersRequired => pick('Add at least one user', 'أضف مستخدماً واحداً على الأقل');
  String get errOneAdmin => pick('Exactly one admin user is required', 'مطلوب مستخدم مدير واحد بالضبط');
  String get errMaxUsers => _sub
      ? pick('A sub agent has a single user', 'الوكيل الفرعي يملك مستخدماً واحداً فقط')
      : pick('A main agent may have at most 4 users', 'الوكيل الرئيسي يمكن أن يملك 4 مستخدمين كحد أقصى');
  String get errUserPhone => pick('Each user needs a phone number', 'كل مستخدم يحتاج رقم هاتف');
  String get errUserPassword => pick('New users need a password', 'المستخدمون الجدد يحتاجون كلمة مرور');
  String get created => _sub ? pick('Sub agent created', 'تم إنشاء الوكيل الفرعي') : pick('Main agent created', 'تم إنشاء الوكيل الرئيسي');
  String get saved => pick('Changes saved', 'تم حفظ التغييرات');
}
