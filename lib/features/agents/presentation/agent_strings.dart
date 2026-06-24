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
  String get deleteTitle => _sub ? pick('Delete sub agent?', 'حذف الوكيل الفرعي؟') : pick('Delete main agent?', 'حذف الوكيل الرئيسي؟');
  String deleteBody(String name) => pick(
      'This removes "$name" and its account access. This cannot be undone.',
      'سيؤدي هذا إلى إزالة "$name" وصلاحيات الدخول. لا يمكن التراجع.');
  String get cancel => pick('Cancel', 'إلغاء');
  String get deleted => _sub ? pick('Sub agent deleted', 'تم حذف الوكيل الفرعي') : pick('Main agent deleted', 'تم حذف الوكيل الرئيسي');

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
  String get noMainAgents => pick('No main agents exist yet — create one first.', 'لا يوجد وكلاء رئيسيون — أنشئ واحداً أولاً.');

  String get sectionIdentity => pick('Identity', 'الهوية');
  String get fieldName => pick('Commercial name', 'الاسم التجاري');
  String get fieldLogo => pick('Logo URL (optional)', 'رابط الشعار (اختياري)');
  String get sectionGovernorates => pick('Governorates (coverage)', 'المحافظات (التغطية)');
  String get governoratesHint => _sub
      ? pick('Select the governorate(s) this sub agent operates in.', 'اختر محافظة (أو محافظات) عمل هذا الوكيل الفرعي.')
      : pick('Select every governorate this agent operates in.', 'اختر كل محافظة يعمل بها هذا الوكيل.');
  String get sectionOwner => pick('Owner & contact', 'المالك والتواصل');
  String get fieldOwnerName => pick('Owner full name', 'اسم المالك الثلاثي');
  String get fieldDocuments => pick('Document URLs (comma-separated)', 'روابط المستمسكات (مفصولة بفواصل)');
  String get fieldLandmark => pick('Nearest landmark', 'أقرب نقطة دالة');
  String get fieldLat => pick('Latitude', 'خط العرض');
  String get fieldLng => pick('Longitude', 'خط الطول');
  String get fieldPhone => pick('Contact phone', 'هاتف التواصل');
  String get fieldEmail => pick('Contact email', 'البريد الإلكتروني');
  String get sectionBranding => pick('Branding (optional)', 'الهوية البصرية (اختياري)');
  String get fieldPrimary => pick('Primary color (hex)', 'اللون الأساسي (hex)');
  String get fieldSecondary => pick('Secondary color (hex)', 'اللون الثانوي (hex)');

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
