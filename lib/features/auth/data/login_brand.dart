import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inteshar/features/entities/domain/branding.dart';
import 'package:inteshar/features/update/data/release_repository.dart';

/// PROD-006: the sign-in screen is the one screen shown before the app knows whose device it is, so
/// it always said "Inteshar". Two things now decide what it shows:
///
/// * the **remembered brand**: the Main-Agent logo and colours of the last account that signed in
///   on this device, saved after every successful sign-in. A shop device belongs to one agent, so
///   from the second sign-in on, the shop sees its own agent;
/// * **HQ's switch** `branding.login.showInteshar`, read before sign-in from the public update check.
///   When HQ turns it off, a device with nothing remembered shows a neutral screen.
class LoginBrand {
  final String logoUrl;
  final String primaryColor;
  final String secondaryColor;

  const LoginBrand({this.logoUrl = '', this.primaryColor = '', this.secondaryColor = ''});

  bool get hasLogo => logoUrl.trim().isNotEmpty;
  bool get hasColors => primaryColor.trim().isNotEmpty || secondaryColor.trim().isNotEmpty;
  bool get isEmpty => !hasLogo && !hasColors;

  factory LoginBrand.fromBrandInfo(BrandInfo b) => LoginBrand(
        logoUrl: b.agentLogoUrl,
        primaryColor: b.primaryColor,
        secondaryColor: b.secondaryColor,
      );

  Map<String, dynamic> toJson() =>
      {'logoUrl': logoUrl, 'primaryColor': primaryColor, 'secondaryColor': secondaryColor};

  factory LoginBrand.fromJson(Map<String, dynamic> j) => LoginBrand(
        logoUrl: j['logoUrl'] as String? ?? '',
        primaryColor: j['primaryColor'] as String? ?? '',
        secondaryColor: j['secondaryColor'] as String? ?? '',
      );
}

/// What the sign-in header shows.
enum LoginHeaderMode { inteshar, agent, neutral }

/// The rule, kept pure so it can be tested: a remembered agent logo wins; otherwise HQ's switch
/// decides between Inteshar and a neutral header. [showInteshar] is null while it is still being
/// read — neutral then, so a device HQ wants unbranded never flashes the Inteshar brand.
LoginHeaderMode loginHeaderMode({LoginBrand? remembered, bool? showInteshar}) {
  if (remembered != null && remembered.hasLogo) return LoginHeaderMode.agent;
  if (showInteshar == null) return LoginHeaderMode.neutral;
  return showInteshar ? LoginHeaderMode.inteshar : LoginHeaderMode.neutral;
}

/// Device-level storage. Deliberately NOT cleared on sign-out (`SessionStorage.clear` removes only
/// the session keys): the brand belongs to the device, not to a session.
class LoginBrandStore {
  static const key = 'login_brand_v1';

  static Future<LoginBrand?> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null || raw.isEmpty) return null;
      final b = LoginBrand.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return b.isEmpty ? null : b;
    } catch (_) {
      return null; // a corrupt entry must never break the sign-in screen
    }
  }

  /// Called with the branding the server just returned for a signed-in account. An agent brand is
  /// remembered; an empty one (HQ, or an agent with no brand set) clears it, so the device does not
  /// keep showing a brand that no longer applies. Only call this after a SUCCESSFUL fetch — a
  /// network failure must not wipe a shop's brand.
  static Future<void> remember(BrandInfo brand) async {
    final p = await SharedPreferences.getInstance();
    final b = LoginBrand.fromBrandInfo(brand);
    if (b.isEmpty) {
      await p.remove(key);
    } else {
      await p.setString(key, jsonEncode(b.toJson()));
    }
  }
}

/// The remembered brand. autoDispose, so every time the sign-in screen opens it is read again
/// (after a sign-out the brand saved during that session is the one shown).
final rememberedLoginBrandProvider =
    FutureProvider.autoDispose<LoginBrand?>((ref) => LoginBrandStore.load());

/// HQ's switch, from the public update check. Any failure (offline, an older server without the
/// field) keeps the long-standing behaviour: show Inteshar.
final loginShowIntesharProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    final check = await ref
        .read(releaseRepositoryProvider)
        .check(versionCode: 0, platform: kIsWeb ? 'web' : 'android')
        .timeout(const Duration(seconds: 8));
    return check.showIntesharOnLogin;
  } catch (_) {
    return true;
  }
});
