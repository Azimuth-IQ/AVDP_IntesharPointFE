import 'dart:math';

class IdGenerator {
  static final _rng = Random();

  static String generate([String prefix = 'id']) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _rng.nextInt(99999).toString().padLeft(5, '0');
    return '$prefix-$ts-$rand';
  }
}
