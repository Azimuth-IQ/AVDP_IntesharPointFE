import 'package:shared_preferences/shared_preferences.dart';

class SessionStorage {
  static const _tokenKey = 'jwt_token';
  static const _baseUrlKey = 'base_url';
  static const _entityIdKey = 'current_entity_id';
  static const _entityTypeKey = 'current_entity_type';
  static const _phoneKey = 'current_phone';
  static const _localeKey = 'app_locale';
  // G17 "remember me": the phone to pre-fill on the login screen. Kept SEPARATE
  // from `_phoneKey` (the active-session phone) so it survives logout/`clear()`.
  static const _rememberedPhoneKey = 'remembered_phone';

  // static const defaultBaseUrl = 'http://localhost:8080';
  // Override at launch with --dart-define=API_BASE=http://<host>:8080 for local
  // testing; defaults to the hosted dev backend when unset.
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://inteshar-be-dev.azimuth-iraq.com',
    // defaultValue: 'http://localhost:8080',
  );

  Future<void> setToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tokenKey, token);
  }

  Future<String?> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_tokenKey);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_tokenKey);
    await p.remove(_entityIdKey);
    await p.remove(_entityTypeKey);
    await p.remove(_phoneKey);
  }

  Future<void> setBaseUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_baseUrlKey, url);
  }

  Future<String> getBaseUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_baseUrlKey) ?? defaultBaseUrl;
  }

  Future<void> setCurrentEntityId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_entityIdKey, id);
  }

  Future<String?> getCurrentEntityId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_entityIdKey);
  }

  Future<void> setCurrentEntityType(String type) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_entityTypeKey, type);
  }

  Future<String?> getCurrentEntityType() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_entityTypeKey);
  }

  Future<void> setCurrentPhone(String phone) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_phoneKey, phone);
  }

  Future<String?> getCurrentPhone() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_phoneKey);
  }

  /// G17: remember the phone for login pre-fill (empty string = forget it).
  Future<void> setRememberedPhone(String phone) async {
    final p = await SharedPreferences.getInstance();
    if (phone.isEmpty) {
      await p.remove(_rememberedPhoneKey);
    } else {
      await p.setString(_rememberedPhoneKey, phone);
    }
  }

  Future<String?> getRememberedPhone() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_rememberedPhoneKey);
  }

  Future<void> setLocale(String languageCode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_localeKey, languageCode);
  }

  Future<String?> getLocale() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_localeKey);
  }
}

final sessionStorage = SessionStorage();
