import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UX-127 — **the weights the code asks for must be weights that exist.**
///
/// Codec Pro ships six upright faces and `assets/fonts/` contains no SemiBold,
/// so `FontWeight.w600` had no face. Flutter does not fail on that: it silently
/// substitutes a neighbour by its own rules, so 58 call sites rendered a weight
/// nobody wrote. `w500` had the same hole. Nothing in the app could notice,
/// because the mismatch is between a Dart literal and a YAML asset list.
///
/// So this test is the check that couldn't exist inside either file: it reads
/// the registered faces out of `pubspec.yaml`, walks every `.dart` file under
/// `lib/`, works out **which family** each `FontWeight` literal is being applied
/// to, and asserts the weight has a face in that family. JetBrains Mono is
/// checked separately and does register 500/600 — a `w600` on a serial is fine,
/// the same `w600` on a label is not, and only the enclosing call says which.
///
/// It deliberately does not restate the mapping it is checking. Both sides are
/// read from the real artifacts, so the assertion is only true while the two
/// files actually agree.
void main() {
  // ── the source-of-truth side ───────────────────────────────────────────────

  /// Registered `{family: {weights}}` from the real `pubspec.yaml`.
  Map<String, Set<int>> readRegisteredFamilies() {
    final lines = File('pubspec.yaml').readAsLinesSync();
    final out = <String, Set<int>>{};
    String? family;
    for (final line in lines) {
      final fam = RegExp(r'^\s*-\s*family:\s*(\S+)').firstMatch(line);
      if (fam != null) {
        family = fam.group(1)!;
        out[family] = <int>{};
        continue;
      }
      if (family == null) continue;
      // A top-level key ends the `fonts:` block.
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
        family = null;
        continue;
      }
      final w = RegExp(r'^\s*weight:\s*(\d+)').firstMatch(line);
      if (w != null) out[family]!.add(int.parse(w.group(1)!));
    }
    return out;
  }

  // ── the call-site side ─────────────────────────────────────────────────────

  /// [src] with every comment and string *body* replaced by spaces, preserving
  /// length and line structure.
  ///
  /// Needed because the scan below matches brackets and identifiers. `//` inside
  /// a URL string and a `(` inside an interpolation would both wreck it, and a
  /// `FontWeight.w600` quoted in a doc comment is prose, not a call site.
  String mask(String src) {
    final out = List<String>.filled(src.length, '');
    for (var i = 0; i < src.length; i++) {
      out[i] = src[i];
    }
    void blank(int from, int to) {
      for (var i = from; i < to && i < src.length; i++) {
        if (src[i] != '\n') out[i] = ' ';
      }
    }

    var i = 0;
    while (i < src.length) {
      final c = src[i];
      final next = i + 1 < src.length ? src[i + 1] : '';
      if (c == '/' && next == '/') {
        final end = src.indexOf('\n', i);
        blank(i, end == -1 ? src.length : end);
        i = end == -1 ? src.length : end;
      } else if (c == '/' && next == '*') {
        final end = src.indexOf('*/', i + 2);
        blank(i, end == -1 ? src.length : end + 2);
        i = end == -1 ? src.length : end + 2;
      } else if (c == "'" || c == '"') {
        // Triple-quoted first — otherwise it reads as an empty string.
        final triple = c * 3;
        if (src.startsWith(triple, i)) {
          final end = src.indexOf(triple, i + 3);
          blank(i, end == -1 ? src.length : end + 3);
          i = end == -1 ? src.length : end + 3;
        } else {
          var j = i + 1;
          while (j < src.length && src[j] != c && src[j] != '\n') {
            if (src[j] == r'\') {
              j += 2;
              continue;
            }
            j++;
          }
          blank(i, j + 1);
          i = j + 1;
        }
      } else {
        i++;
      }
    }
    return out.join();
  }

  /// The identifier opening the innermost argument list that contains [index] —
  /// `IntesharType.sans`, `TextStyle`, `mono`, … Empty when there is none.
  ///
  /// This is what makes the check family-aware. A `FontWeight` literal means
  /// nothing on its own; it is only wrong relative to the family it lands on.
  (String, int) enclosingCall(String masked, int index) {
    final open = <int>[];
    for (var i = 0; i < index; i++) {
      final c = masked[i];
      if (c == '(') {
        open.add(i);
      } else if (c == ')' && open.isNotEmpty) {
        open.removeLast();
      }
    }
    if (open.isEmpty) return ('', -1);
    final paren = open.last;
    var start = paren;
    while (start > 0) {
      final ch = masked[start - 1];
      if (RegExp(r'[A-Za-z0-9_.]').hasMatch(ch)) {
        start--;
      } else {
        break;
      }
    }
    return (masked.substring(start, paren), paren);
  }

  /// Index of the ')' closing the '(' at [paren].
  int closeOf(String masked, int paren) {
    var depth = 0;
    for (var i = paren; i < masked.length; i++) {
      if (masked[i] == '(') depth++;
      if (masked[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return masked.length;
  }

  const codecFamily = 'CodecPro';
  const monoFamily = 'JetBrainsMono';

  /// Helpers whose returned style is in a known family.
  const codecCalls = <String>{
    'IntesharType.sans',
    'IntesharType.display',
    'IntesharType.serif',
    'IntesharType.codec',
    'IntesharType.overline',
    'sans',
    'display',
    'serif',
    'codec',
    'overline',
  };
  const monoCalls = <String>{
    'IntesharType.mono',
    'mono',
    'monoText',
  };

  /// Which family a `FontWeight` literal at [index] is applied to, or null when
  /// it is a plain `TextStyle` with no family (Material's default) or something
  /// this scan cannot attribute — those are outside the question being asked.
  String? familyAt(String masked, int index) {
    final (name, paren) = enclosingCall(masked, index);
    if (paren == -1) return null;
    final short = name.contains('.') ? name.split('.').last : name;
    if (codecCalls.contains(name) || codecCalls.contains(short)) {
      return codecFamily;
    }
    if (monoCalls.contains(name) || monoCalls.contains(short)) return monoFamily;
    if (short == 'TextStyle' || short == 'copyWith') {
      final args = masked.substring(paren, closeOf(masked, paren));
      // The string literal is masked out, so match on the argument name plus
      // whatever identifier follows (`kMonoFamily`) — and fall back to the raw
      // source for the quoted form.
      if (args.contains('fontFamily')) {
        if (args.contains('kMonoFamily')) return monoFamily;
        return codecFamily; // the only quoted family the app ever writes
      }
      return null; // no family: Material default, not our problem
    }
    return null;
  }

  int? weightOf(String token) {
    if (token == 'bold') return 700;
    if (token == 'normal') return 400;
    final m = RegExp(r'^w(\d00)$').firstMatch(token);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Files another agent owns in this round, so UX-127 could not touch them.
  /// Both still write an unregistered CodecPro weight. **Delete an entry the
  /// moment its file is fixed** — the list is asserted to be exactly this size,
  /// so it cannot quietly grow into a permanent exemption.
  const exempt = <String>{
    // `FontWeight.w600` on the splash tagline.
    'lib/features/auth/presentation/splash_page.dart',
    // `FontWeight.w500` on two raw `TextStyle(fontFamily: 'CodecPro', …)`.
    'lib/features/auth/presentation/login_page.dart',
  };

  List<String> scan({required bool includeExempt}) {
    final registered = readRegisteredFamilies();
    final problems = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final rel = file.path;
      if (!includeExempt && exempt.any(rel.endsWith)) continue;
      final masked = mask(file.readAsStringSync());
      for (final m in RegExp(r'FontWeight\.([A-Za-z0-9]+)').allMatches(masked)) {
        final weight = weightOf(m.group(1)!);
        if (weight == null) continue;
        final family = familyAt(masked, m.start);
        if (family == null) continue;
        final faces = registered[family];
        if (faces == null || faces.contains(weight)) continue;
        final line = '\n'.allMatches(masked.substring(0, m.start)).length + 1;
        problems.add('$rel:$line asks $family for w$weight — '
            'registered: ${(faces.toList()..sort()).join('/')}');
      }
    }
    return problems;
  }

  test('the scanner can read the registered families out of pubspec', () {
    final registered = readRegisteredFamilies();
    expect(registered.keys, containsAll([codecFamily, monoFamily]));
    expect(registered[codecFamily], isNotEmpty);
    expect(registered[monoFamily], isNotEmpty);
    // The premise of the whole item: there is no 600 face in the brand family.
    expect(registered[codecFamily], isNot(contains(600)));
    // …and mono DOES have one, which is why the check must be family-aware
    // rather than banning the literal outright.
    expect(registered[monoFamily], contains(600));
  });

  test('every FontWeight in lib/ has a real face in the family it lands on', () {
    final problems = scan(includeExempt: false);
    expect(
      problems,
      isEmpty,
      reason: 'These ask for a weight the font does not register, so Flutter '
          'substitutes a neighbour and the rendered result is not what the '
          'source says. Use an IntesharWeight token.\n${problems.join('\n')}',
    );
  });

  test('the ownership exemption list has not grown', () {
    // If this fails because a file was FIXED, delete its entry — that is the
    // intended end state. If it fails because one was ADDED, the addition is
    // the bug.
    expect(exempt, hasLength(2));
  });
}
