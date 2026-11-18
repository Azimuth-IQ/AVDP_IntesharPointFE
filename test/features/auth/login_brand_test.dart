import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/auth/data/login_brand.dart';
import 'package:inteshar/features/entities/domain/branding.dart';
import 'package:inteshar/features/update/domain/app_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PROD-006 — what the sign-in screen shows before the app knows whose device it is.
void main() {
  const agent = LoginBrand(logoUrl: 'https://media/agent.png', primaryColor: '#123456');
  const coloursOnly = LoginBrand(primaryColor: '#123456');

  group('loginHeaderMode', () {
    test('a remembered agent logo wins over everything, HQ switch included', () {
      expect(loginHeaderMode(remembered: agent, showInteshar: true), LoginHeaderMode.agent);
      expect(loginHeaderMode(remembered: agent, showInteshar: false), LoginHeaderMode.agent);
      expect(loginHeaderMode(remembered: agent, showInteshar: null), LoginHeaderMode.agent);
    });

    test('with nothing remembered, HQ switch decides', () {
      expect(loginHeaderMode(showInteshar: true), LoginHeaderMode.inteshar);
      expect(loginHeaderMode(showInteshar: false), LoginHeaderMode.neutral);
    });

    test('while the switch is still being read: neutral, never a flash of Inteshar', () {
      expect(loginHeaderMode(showInteshar: null), LoginHeaderMode.neutral);
    });

    test('colours alone are not a logo to show', () {
      expect(loginHeaderMode(remembered: coloursOnly, showInteshar: true), LoginHeaderMode.inteshar);
    });
  });

  group('LoginBrandStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('remembers an agent brand from the branding the server returned', () async {
      await LoginBrandStore.remember(const BrandInfo(
          agentLogoUrl: 'https://media/agent.png', primaryColor: '#123456', secondaryColor: '#abcdef'));
      final b = await LoginBrandStore.load();
      expect(b?.logoUrl, 'https://media/agent.png');
      expect(b?.primaryColor, '#123456');
      expect(b?.secondaryColor, '#abcdef');
    });

    test('an empty brand (HQ signing in) clears what was remembered', () async {
      await LoginBrandStore.remember(const BrandInfo(agentLogoUrl: 'https://media/agent.png'));
      await LoginBrandStore.remember(const BrandInfo());
      expect(await LoginBrandStore.load(), isNull);
    });

    test('survives a sign-out: it is not one of the session keys', () async {
      await LoginBrandStore.remember(const BrandInfo(agentLogoUrl: 'https://media/agent.png'));
      final p = await SharedPreferences.getInstance();
      for (final k in ['jwt_token', 'current_entity_id', 'current_entity_type', 'current_phone']) {
        await p.remove(k); // what SessionStorage.clear removes
      }
      expect((await LoginBrandStore.load())?.logoUrl, 'https://media/agent.png');
    });

    test('a corrupt entry never breaks the sign-in screen', () async {
      SharedPreferences.setMockInitialValues({LoginBrandStore.key: '{not json'});
      expect(await LoginBrandStore.load(), isNull);
    });

    test('round-trips through its JSON', () {
      final back = LoginBrand.fromJson(jsonDecode(jsonEncode(agent.toJson())) as Map<String, dynamic>);
      expect(back.logoUrl, agent.logoUrl);
      expect(back.primaryColor, agent.primaryColor);
    });
  });

  group('UpdateCheck.showIntesharOnLogin', () {
    test('an older server without the field keeps the brand shown', () {
      expect(UpdateCheck.fromJson({'updateAvailable': false, 'mandatory': false}).showIntesharOnLogin, isTrue);
    });

    test('HQ turning it off reaches the app', () {
      expect(
          UpdateCheck.fromJson({'updateAvailable': false, 'mandatory': false, 'showIntesharOnLogin': false})
              .showIntesharOnLogin,
          isFalse);
    });
  });
}
