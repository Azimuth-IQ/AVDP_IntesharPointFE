import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/core/storage/session_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// B-064: POS quick-sell recents — most-recent-first, de-duplicated, capped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty when nothing sold yet', () async {
    expect(await sessionStorage.getRecentPosSkus(), isEmpty);
  });

  test('most-recent pushes to the front', () async {
    await sessionStorage.pushRecentPosSku('A', 'Baghdad');
    await sessionStorage.pushRecentPosSku('B', '');
    final keys = await sessionStorage.getRecentPosSkus();
    expect(keys.first, 'B${SessionStorage.recentPosSkuSep}');
    expect(keys.length, 2);
  });

  test('re-selling an existing SKU de-dups and moves it to the front', () async {
    await sessionStorage.pushRecentPosSku('A', 'Baghdad');
    await sessionStorage.pushRecentPosSku('B', '');
    await sessionStorage.pushRecentPosSku('A', 'Baghdad');
    final keys = await sessionStorage.getRecentPosSkus();
    expect(keys.length, 2); // not 3
    expect(keys.first, 'A${SessionStorage.recentPosSkuSep}Baghdad');
  });

  test('same SKU in different governorates are distinct entries', () async {
    await sessionStorage.pushRecentPosSku('A', 'Baghdad');
    await sessionStorage.pushRecentPosSku('A', 'Basra');
    expect((await sessionStorage.getRecentPosSkus()).length, 2);
  });

  test('caps at 8, dropping the oldest', () async {
    for (var i = 0; i < 12; i++) {
      await sessionStorage.pushRecentPosSku('SKU$i', '');
    }
    final keys = await sessionStorage.getRecentPosSkus();
    expect(keys.length, 8);
    expect(keys.first, 'SKU11${SessionStorage.recentPosSkuSep}');
    expect(keys.contains('SKU0${SessionStorage.recentPosSkuSep}'), isFalse);
  });

  test('empty sku is ignored', () async {
    await sessionStorage.pushRecentPosSku('', 'Baghdad');
    expect(await sessionStorage.getRecentPosSkus(), isEmpty);
  });
}
