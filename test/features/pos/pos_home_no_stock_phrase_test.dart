import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PROD-021 (client, 2026-11-21 12:26): «اطبع عند المنفذ من المخزون المتاح.» under «اختر الفئة»
/// — "what is this phrase, what is it for?". The POS home header has no subtitle now.
void main() {
  test('the POS home header carries no stock phrase', () {
    final src = File('lib/features/pos/presentation/pos_home_page.dart').readAsStringSync();
    expect(src, isNot(contains('subtitle: l.posHomeCounterSubtitle')));
    expect(src, contains('_header(l, title: l.posHomePickDenomination)'));
  });
}
