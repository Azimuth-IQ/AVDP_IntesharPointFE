// PROD-028 … PROD-033 (the client's notes of 25 Nov): the rules that are not drawing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/utils/hand_off.dart';
import 'package:inteshar/features/companies/domain/company.dart';
import 'package:inteshar/features/entities/domain/entity.dart';

String src(String path) => File(path).readAsStringSync();

void main() {
  group('PROD-033: the PIN comes back every time, except after a trip the app started', () {
    setUp(HandOff.reset);
    final t0 = DateTime(2026, 11, 25, 16, 37);

    test('screen off and on, or the app left and reopened: nothing marked, so the PIN', () {
      expect(HandOff.consume(t0), isFalse);
    });

    test('printing through the vendor app: the trip is let through once', () {
      HandOff.mark(t0);
      expect(HandOff.consume(t0.add(const Duration(seconds: 3))), isTrue);
      // The next screen-off is the cashier's, not ours.
      expect(HandOff.consume(t0.add(const Duration(minutes: 1))), isFalse);
    });

    test('an old mark does not cover a later screen-off', () {
      HandOff.mark(t0);
      expect(HandOff.consume(t0.add(HandOff.window + const Duration(seconds: 1))), isFalse);
    });

    test('the POS home uses it, and the 90-second grace is gone', () {
      final home = src('lib/features/pos/presentation/pos_home_page.dart');
      expect(home, contains('!HandOff.consume(since)'));
      expect(home, isNot(contains('_relockAfter')));
      expect(src('lib/core/printing/printer_service.dart'),
          matches(RegExp(r'HandOff\.mark\(\);\s*await RovoPrinter\.printText')));
      expect(src('lib/features/update/application/update_controller.dart'), contains('HandOff.mark()'));
    });
  });

  test('PROD-032: pulling down on the POS also re-reads the slider and branding', () {
    final home = src('lib/features/pos/presentation/pos_home_page.dart');
    expect(home, contains('onRefresh: _pullToRefresh'));
    expect(home, isNot(contains('onRefresh: _load')));
    expect(home, matches(RegExp(r'_pullToRefresh\(\) async \{\s*await ref\.read\(authStateProvider\.notifier\)\.refresh\(\);\s*await _load\(\);')));
  });

  test('PROD-028: a company carries its own receipt logo, and sends it on save', () {
    final c = Company.fromJson({'id': 'co', 'name': 'ASIACELL', 'logoUrl': '/tile.jpg', 'receiptLogoUrl': '/receipt.png'});
    expect(c.receiptLogoUrl, '/receipt.png');
    expect(c.toJson()['receiptLogoUrl'], '/receipt.png');
    expect(c.copyWith(receiptLogoUrl: '').toJson()['receiptLogoUrl'], '', reason: 'empty clears it on the server');
    expect(Company.fromJson({'name': 'OLD'}).receiptLogoUrl, '');
    expect(src('lib/features/companies/presentation/companies_page.dart'), contains('s.receiptLogo'));
  });

  test('PROD-029 / PROD-031: the agent switches survive a round trip', () {
    final m = EntityMeta.fromJson({'name': 'x', 'receiptHeaderHidden': true, 'posCreationLocked': true});
    expect(m.receiptHeaderHidden, isTrue);
    expect(m.posCreationLocked, isTrue);
    final j = m.toJson();
    expect(j['receiptHeaderHidden'], isTrue);
    expect(j['posCreationLocked'], isTrue);
    final legacy = EntityMeta.fromJson({'name': 'x'});
    expect(legacy.receiptHeaderHidden, isFalse);
    expect(legacy.posCreationLocked, isFalse);
    // Editing anything else keeps them (every meta save is a whole-document PUT).
    expect(m.copyWith(name: 'y').posCreationLocked, isTrue);
  });

  test('PROD-031: Add POS offers "belongs to" for a Main Agent and refuses a locked sub-agent', () {
    final page = src('lib/features/pos_admin/presentation/pos_admin_page.dart');
    expect(page, contains("ValueKey('onboard-belongs-to')"));
    expect(page, contains('entityId: hostId ?? _effectiveId'));
    expect(page, contains('|| _addLocked)'));
    final form = src('lib/features/agents/presentation/agent_form.dart');
    expect(form, contains("ValueKey('pos-creation-switch')"));
    expect(form, contains("ValueKey('receipt-header-switch')"));
  });
}
