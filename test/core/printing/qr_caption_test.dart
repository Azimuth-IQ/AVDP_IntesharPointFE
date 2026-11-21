import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/printing/escpos_builder.dart';
import 'package:inteshar/features/inventory/domain/voucher_template.dart';

/// PROD-022 (client photos, 2026-11-21 12:54: «يظهر الكود مرتين»): the receipt printed the PIN,
/// then the QR, then the QR's content under it — the PIN again — in every category.
void main() {
  const pin = '3002727956077715';
  const serial = '26041919843328';

  group('the line under the QR', () {
    test('default template (PIN shown, QR of the PIN, no instructions) → nothing', () {
      expect(qrCaption(const VoucherTemplate(), pin: pin, serial: serial), isNull);
    });

    test('a dial-code QR (*133*PIN#) is still the PIN → nothing', () {
      const t = VoucherTemplate(qrPrefix: '*133*', qrSuffix: '#');
      expect(qrCaption(t, pin: pin, serial: serial), isNull);
    });

    test('HQ wrote redeem instructions → the instructions', () {
      const t = VoucherTemplate(redeemInstructions: 'لغرض التعبئة اتصل على 333');
      expect(qrCaption(t, pin: pin, serial: serial), 'لغرض التعبئة اتصل على 333');
    });

    test('a template that hides the PIN keeps it readable under the QR', () {
      const t = VoucherTemplate(showPin: false);
      expect(qrCaption(t, pin: pin, serial: serial), pin);
    });

    test('a QR of the serial, serial shown → nothing', () {
      const t = VoucherTemplate(qrSource: 'SERIAL');
      expect(qrCaption(t, pin: pin, serial: serial), isNull);
    });
  });

  test('the text-only receipt (vendor printers) carries the PIN once', () {
    final text = buildVoucherReceiptText(
      template: const VoucherTemplate(),
      headerFallback: 'POS',
      shopName: 'العقل 1',
      productName: 'Asiacell 1000',
      price: '1,000',
      serial: serial,
      pin: pin,
      timestamp: DateTime(2026, 11, 21, 12, 54),
    );
    expect(pin.allMatches(text).length, 1);
  });

  test('the sale screen uses the same rule as the paper', () {
    final src = File('lib/features/pos/presentation/pos_home_page.dart').readAsStringSync();
    expect(src, contains('qrCaption(t, pin: p.pin, serial: p.serialNumber)'));
    expect(src, isNot(contains('? t.redeemInstructions.trim() : t.qrPayload(')));
  });

  test("HQ's template preview follows the paper too", () {
    final src = File('lib/features/inventory/presentation/voucher_templates_page.dart').readAsStringSync();
    expect(src, contains('if (!qrValueAlreadyPrinted(template, pin: _samplePin, serial: _sampleSerial))'));
  });
}
