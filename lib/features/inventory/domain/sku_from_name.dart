/// Derives a product code from a category name.
///
/// The customer asked for this on 2026-08-12 — "ورمز المادة من نرفعة ياخذ اسم
/// الفئة وليس اني اقوم بكتابتة" — after a batch went in under the code "A1",
/// which is what you get when a required field means nothing to the person
/// filling it in.
///
/// The result has to survive being a URL query parameter, a spreadsheet cell and
/// a Mongo key, so it keeps letters and digits, turns runs of anything else into
/// a single dash, and trims the dashes off the ends. Letters of any script are
/// kept: an Arabic catalogue should not be forced through a transliteration
/// nobody asked for.
String skuFromName(String name, {int maxLength = 40}) {
  final buffer = StringBuffer();
  var pendingSeparator = false;

  for (final rune in name.trim().runes) {
    final ch = String.fromCharCode(rune);
    if (_isLetterOrDigit(ch)) {
      if (pendingSeparator && buffer.isNotEmpty) buffer.write('-');
      pendingSeparator = false;
      buffer.write(ch.toUpperCase());
    } else {
      // Commas inside numbers ("5,000") must not become dashes, so a separator
      // is only emitted once a following character proves more content exists.
      pendingSeparator = ch != ',' || buffer.isEmpty;
    }
  }

  var out = buffer.toString();
  if (out.length > maxLength) out = out.substring(0, maxLength);
  // A truncation can leave a trailing dash.
  while (out.endsWith('-')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

bool _isLetterOrDigit(String ch) {
  // Unicode-aware: \p{L} covers Arabic and Latin alike.
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(ch);
}
