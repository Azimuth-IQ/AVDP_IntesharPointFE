import 'package:flutter_test/flutter_test.dart';
import 'package:inteshar/features/reports/domain/report_rows.dart';

// Field test 2026-10-29: exporting the balances report crashed. Export and
// load-more gather rows into a List<dynamic>, and `data as List<T>?` throws on
// that list even when every row is a T.
void main() {
  test('a List<dynamic> of rows reads as typed rows', () {
    final gathered = <dynamic>['a', 'b'];
    expect(() => gathered as List<String>?, throwsA(isA<TypeError>()));
    expect(rowsOf<String>(gathered), ['a', 'b']);
  });

  test('null or a non-list reads as no rows', () {
    expect(rowsOf<String>(null), isEmpty);
    expect(rowsOf<String>('x'), isEmpty);
  });

  test('an already-typed list passes through', () {
    expect(rowsOf<int>(const [1, 2]), [1, 2]);
  });
}
