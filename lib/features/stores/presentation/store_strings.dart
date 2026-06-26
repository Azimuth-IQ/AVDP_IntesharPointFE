import 'package:flutter/widgets.dart';

/// Localized copy for the Stores / POS management feature (AR default / EN),
/// following the [AgentStrings] pattern — keeps page text out of the shared ARB.
class StoreStrings {
  final bool ar;
  const StoreStrings(this.ar);

  factory StoreStrings.of(BuildContext context) =>
      StoreStrings(Localizations.localeOf(context).languageCode == 'ar');

  String get pageEyebrow => ar ? 'الشبكة' : 'NETWORK';
  String get pageTitle => ar ? 'نقاط البيع' : 'Stores / POS';
  String get pageSubtitle => ar
      ? 'إدارة نقاط البيع: التفعيل والإيقاف، تصفير كلمة المرور، الرصيد والإحصاءات.'
      : 'Manage POS points: enable/disable, reset password, balance and stats.';
  String get addPos => ar ? 'إضافة نقطة' : 'Add POS';
  String get empty => ar ? 'لا توجد نقاط بيع' : 'No POS points yet';
  String get emptyHint => ar ? 'أضف أول نقطة بيع لهذه الشبكة.' : 'Add the first POS point for this network.';

  String get active => ar ? 'فعّالة' : 'Active';
  String get disabled => ar ? 'موقوفة' : 'Disabled';
  String get owner => ar ? 'صاحب المكتب' : 'Owner';
  String get phone => ar ? 'الهاتف' : 'Phone';
  String get noRegion => ar ? 'بدون محافظة' : 'No region';

  // Detail
  String get balance => ar ? 'الرصيد المتوفر' : 'Available balance';
  String get available => ar ? 'متوفرة' : 'Available';
  String get sold => ar ? 'مباعة' : 'Sold';
  String get lastSeen => ar ? 'آخر نشاط' : 'Last seen';
  String get never => ar ? 'لا يوجد' : 'Never';
  String get device => ar ? 'الجهاز' : 'Device';
  String get appVersion => ar ? 'إصدار التطبيق' : 'App version';

  // Actions
  String get activate => ar ? 'تفعيل' : 'Activate';
  String get deactivate => ar ? 'إيقاف' : 'Disable';
  String get resetPassword => ar ? 'تصفير كلمة المرور' : 'Reset password';
  String get transfer => ar ? 'تحويل رصيد' : 'Transfer balance';
  String get edit => ar ? 'تعديل' : 'Edit';
  String get delete => ar ? 'حذف' : 'Delete';
  String get cancel => ar ? 'إلغاء' : 'Cancel';
  String get save => ar ? 'حفظ' : 'Save';

  String get newPassword => ar ? 'كلمة المرور الجديدة' : 'New password';
  String get amount => ar ? 'المبلغ' : 'Amount';
  String get insufficientBalance => ar ? 'الرصيد غير كافٍ' : 'Insufficient balance';
  String get passwordReset => ar ? 'تم تصفير كلمة المرور' : 'Password reset';
  String get transferred => ar ? 'تم التحويل' : 'Transfer complete';
  String get activated => ar ? 'تم التفعيل' : 'Activated';
  String get deactivated => ar ? 'تم الإيقاف' : 'Disabled';
  String get deleted => ar ? 'تم الحذف' : 'Deleted';

  String deleteTitle(String name) => ar ? 'حذف "$name"؟' : 'Delete "$name"?';
  String get deleteBody => ar ? 'لا يمكن التراجع عن هذا الإجراء.' : 'This cannot be undone.';

  // Form
  String get formNewTitle => ar ? 'نقطة بيع جديدة' : 'New POS point';
  String get formEditTitle => ar ? 'تعديل نقطة البيع' : 'Edit POS point';
  String get parentAgent => ar ? 'الوكيل الأصل' : 'Parent agent';
  String get noParentAgents =>
      ar ? 'أنشئ وكيلاً أولاً قبل إضافة نقطة بيع.' : 'Create an agent first before adding a POS point.';
  String get shopName => ar ? 'الاسم التجاري (يظهر على الكارت)' : 'Shop name (shown on the card)';
  String get ownerName => ar ? 'اسم صاحب المكتب الثلاثي' : 'Owner full name';
  String get loginPhone => ar ? 'هاتف الدخول (اسم المستخدم)' : 'Login phone (username)';
  String get password => ar ? 'كلمة المرور' : 'Password';
  String get region => ar ? 'المحافظة (المخزن)' : 'Governorate (warehouse)';
  String get landmark => ar ? 'العنوان / أقرب نقطة دالة' : 'Address / nearest landmark';
  String get statusActive => ar ? 'الحالة: فعّالة' : 'Status: active';
  String get required => ar ? 'مطلوب' : 'Required';
  String get created => ar ? 'تمت الإضافة' : 'POS point added';
  String get updated => ar ? 'تم الحفظ' : 'Saved';
}
