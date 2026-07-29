/// Canonical, fixed list of Iraq's 18 governorates — the single source of truth for
/// every governorate dropdown / multi-select in the app. Vouchers and entities
/// reference these by [code]; labels are localized (Arabic by default, English when
/// the active locale is English). Mirrors the backend `Core/Constants/Governorates`.
class Governorate {
  final String code;
  final String ar;
  final String en;
  const Governorate(this.code, this.ar, this.en);

  /// Label for a BCP-47 locale code (e.g. 'ar', 'en'). Defaults to Arabic.
  String label(String localeCode) =>
      localeCode.toLowerCase().startsWith('en') ? en : ar;
}

const List<Governorate> kGovernorates = [
  Governorate('BAGHDAD', 'بغداد', 'Baghdad'),
  Governorate('BASRA', 'البصرة', 'Basra'),
  Governorate('NINEVEH', 'نينوى', 'Nineveh'),
  Governorate('ERBIL', 'أربيل', 'Erbil'),
  Governorate('SULAYMANIYAH', 'السليمانية', 'Sulaymaniyah'),
  Governorate('DUHOK', 'دهوك', 'Duhok'),
  Governorate('KIRKUK', 'كركوك', 'Kirkuk'),
  Governorate('NAJAF', 'النجف', 'Najaf'),
  Governorate('KARBALA', 'كربلاء', 'Karbala'),
  Governorate('BABYLON', 'بابل', 'Babylon'),
  Governorate('WASIT', 'واسط', 'Wasit'),
  Governorate('DIYALA', 'ديالى', 'Diyala'),
  Governorate('SALAHADDIN', 'صلاح الدين', 'Salah al-Din'),
  Governorate('ANBAR', 'الأنبار', 'Anbar'),
  Governorate('MUTHANNA', 'المثنى', 'Muthanna'),
  Governorate('QADISIYYAH', 'القادسية', 'Qadisiyyah'),
  Governorate('MAYSAN', 'ميسان', 'Maysan'),
  Governorate('DHIQAR', 'ذي قار', 'Dhi Qar'),
];

/// Lookup a governorate by code, or null if the code is unknown/absent.
Governorate? governorateByCode(String? code) {
  if (code == null) return null;
  for (final g in kGovernorates) {
    if (g.code == code) return g;
  }
  return null;
}

/// Localized label for a code; falls back to the raw code if unrecognized.
String governorateLabel(String code, String localeCode) =>
    governorateByCode(code)?.label(localeCode) ?? code;

/// Reverse of [governorateLabel]: resolves a code OR either language's name back
/// to the stored code. Returns null when [value] matches nothing.
///
/// B-114: the prices sheet exports a READABLE governorate, so the re-upload path
/// has to accept what it exported. Matching the code too keeps older sheets
/// (which carried raw codes) working.
String? governorateFromAnything(String? value) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return null;
  final lower = v.toLowerCase();
  for (final g in kGovernorates) {
    if (g.code.toLowerCase() == lower ||
        g.en.toLowerCase() == lower ||
        g.ar == v) {
      return g.code;
    }
  }
  return null;
}
