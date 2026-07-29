// Generates test/fixtures/backend_routes.txt from the Spring controllers in the
// sibling backend repo, and doubles as the parser the coverage test uses to
// detect that the fixture has gone stale.
//
//   dart run tool/gen_backend_routes.dart            # rewrite the fixture
//   dart run tool/gen_backend_routes.dart --check    # exit 1 if it is stale
//
// Why this exists: `lib/features/system_activity/domain/log_phrase.dart` turns
// API routes into sentences for the activity feed, and the coverage test asserts
// every route resolves to a real phrase. That fixture used to be a hand-run
// snapshot, so a new backend endpoint never failed anything — it just quietly
// rendered as "Request" in the app. The test now re-parses the controllers on
// every run (when the backend checkout is present) and fails on any drift.
//
// Parsing rules — deliberately the same ones the original snapshot used, over
// every `.java` file under `src/main/java` that mentions `@RestController` or
// `@Controller` (so a controller not named `*Controller.java` is still seen):
//   * class-level `@RequestMapping("/api/x")` gives the base path;
//   * method-level `@GetMapping` / `@PostMapping` / `@PutMapping` /
//     `@PatchMapping` / `@DeleteMapping` give the suffix (bare = base path);
//   * `value =` / `path =` attributes and `{"/a", "/b"}` arrays are understood;
//   * comments are stripped first, so a commented-out mapping is NOT a route.
//
// Known limitations (both are reported when the generator runs):
//   * method-level `@RequestMapping` is not treated as a route — Spring accepts
//     it, but it is a legacy style here and folding it in would change what the
//     phrase dictionary has to cover. Any occurrence is listed in the fixture
//     header so it cannot hide.
//   * paths built from constants (`@GetMapping(SOME_CONST)`) rather than string
//     literals cannot be resolved by a text parser and are counted as bare.

import 'dart:io';

/// Env var that overrides where the backend source tree is looked for.
const backendSrcEnvVar = 'INTESHAR_BE_SRC';

/// The command a human should run when the fixture is stale.
const regenerateCommand = 'dart run tool/gen_backend_routes.dart';

/// Path of the fixture, relative to the Flutter package root.
const fixturePath = 'test/fixtures/backend_routes.txt';

/// Candidate locations of the backend `src/main/java`, relative to the Flutter
/// package root, in the monorepo layout
/// `Dev/Inteshar Project/{avdp_inteshar_be, avdp_inteshar_fe/inteshar}`.
const backendSrcCandidates = <String>[
  '../../avdp_inteshar_be/src/main/java',
  '../../../avdp_inteshar_be/src/main/java',
  '../avdp_inteshar_be/src/main/java',
];

/// One `@…Mapping` found in a controller.
class BackendRoute {
  /// Full path, e.g. `/api/inventory/product/sendForPrinting`.
  final String path;

  /// `GET`, `POST`, … — informational only, the fixture keys on [path].
  final String verb;

  /// `EntityController.java:301` — used in failure messages.
  final String origin;

  const BackendRoute(this.path, this.verb, this.origin);

  @override
  String toString() => '$verb $path  ($origin)';
}

/// Everything a scan of the backend produced.
class RouteScan {
  final List<BackendRoute> routes;

  /// Distinct paths, sorted — this is what the fixture stores.
  final List<String> paths;

  /// Controller files that contributed at least one route.
  final int controllerCount;

  /// Method-level `@RequestMapping`s, which are intentionally NOT routes here.
  final List<BackendRoute> methodLevelRequestMappings;

  /// Mappings whose path could not be read as a string literal.
  final List<String> unresolvedPathExpressions;

  const RouteScan({
    required this.routes,
    required this.paths,
    required this.controllerCount,
    required this.methodLevelRequestMappings,
    required this.unresolvedPathExpressions,
  });
}

/// Where [locateBackendSource] will look, in order. `$backendSrcEnvVar`, when
/// set, replaces the defaults rather than being prepended to them — an explicit
/// pointer that turns out to be wrong should not silently resolve elsewhere.
List<String> backendSearchPaths({Directory? packageRoot}) {
  final override = Platform.environment[backendSrcEnvVar];
  if (override != null && override.trim().isNotEmpty) return [override.trim()];
  final root = packageRoot ?? findPackageRoot();
  return backendSrcCandidates.map((c) => _join(root.path, c)).toList();
}

/// Locates the backend `src/main/java`, or null when it is not checked out
/// (the FE repo is built on its own in CI — see .github/workflows/apk.yml).
Directory? locateBackendSource({Directory? packageRoot}) {
  for (final path in backendSearchPaths(packageRoot: packageRoot)) {
    final dir = Directory(path);
    if (dir.existsSync() && _javaFiles(dir).isNotEmpty) return dir;
  }
  return null;
}

/// Walks up from [start] (default: cwd) to the directory holding `pubspec.yaml`.
Directory findPackageRoot({Directory? start}) {
  var dir = start ?? Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(_join(dir.path, 'pubspec.yaml')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return start ?? Directory.current;
}

/// Parses every controller under [backendSrc] and returns the routes they map.
RouteScan scanBackendRoutes(Directory backendSrc) {
  final routes = <BackendRoute>[];
  final methodLevel = <BackendRoute>[];
  final unresolved = <String>[];
  var controllers = 0;

  for (final file in _javaFiles(backendSrc)) {
    // Cheap pre-filter: only controllers are worth stripping and parsing.
    final raw = file.readAsStringSync();
    if (!raw.contains('@RestController') && !raw.contains('@Controller')) {
      continue;
    }
    final source = stripJavaComments(raw);
    final name = file.uri.pathSegments.last;
    final classAt = _classDeclaration.firstMatch(source)?.start ?? source.length;

    // Class-level base path: the first @RequestMapping above the class keyword.
    var base = '';
    for (final m in _requestMapping.allMatches(source)) {
      if (m.start >= classAt) break;
      base = _pathsOf(_annotationArgs(source, m.end)).first;
      break;
    }

    var found = 0;
    for (final m in _verbMapping.allMatches(source)) {
      final args = _annotationArgs(source, m.end);
      final origin = '$name:${_lineAt(source, m.start)}';
      final paths = _pathsOf(args);
      if (paths.length == 1 && paths.first.isEmpty && _looksLikeExpression(args)) {
        unresolved.add('$origin — ${args!.trim()}');
      }
      for (final p in paths) {
        routes.add(BackendRoute(_joinRoute(base, p), m.group(1)!.toUpperCase(), origin));
        found++;
      }
    }

    // Method-level @RequestMapping: recorded, not folded in. See the header.
    for (final m in _requestMapping.allMatches(source)) {
      if (m.start < classAt) continue;
      final suffix = _pathsOf(_annotationArgs(source, m.end)).first;
      methodLevel.add(BackendRoute(_joinRoute(base, suffix), 'ANY',
          '$name:${_lineAt(source, m.start)}'));
    }

    if (found > 0) controllers++;
  }

  final paths = routes.map((r) => r.path).toSet().toList()..sort();
  return RouteScan(
    routes: routes,
    paths: paths,
    controllerCount: controllers,
    methodLevelRequestMappings: methodLevel,
    unresolvedPathExpressions: unresolved,
  );
}

/// Reads the route lines out of a fixture, ignoring `#` header comments.
List<String> parseFixture(String contents) => contents
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty && !l.startsWith('#'))
    .toList();

/// Renders the fixture file for [scan].
String renderFixture(RouteScan scan) {
  final b = StringBuffer()
    ..writeln('# GENERATED FILE — do not hand-edit.')
    ..writeln('# Regenerate:  $regenerateCommand')
    ..writeln('#')
    ..writeln('# Every route the backend controllers map: class @RequestMapping +')
    ..writeln('# method @Get/@Post/@Put/@Patch/@DeleteMapping, comments stripped.')
    ..writeln('# ${scan.paths.length} distinct routes across ${scan.controllerCount} controllers.')
    ..writeln('#')
    ..writeln('# The system_activity coverage test asserts each of these resolves to a')
    ..writeln('# phrase in lib/features/system_activity/domain/log_phrase.dart, and');
  b.writeln('# fails if this list has drifted from the live controllers.');
  if (scan.methodLevelRequestMappings.isNotEmpty) {
    b
      ..writeln('#')
      ..writeln('# NOT COVERED — method-level @RequestMapping (legacy style, not parsed');
    b.writeln('# as a route; add a phrase by hand if one of these starts showing up):');
    for (final r in scan.methodLevelRequestMappings) {
      b.writeln('#   ${r.path}  (${r.origin})');
    }
  }
  if (scan.unresolvedPathExpressions.isNotEmpty) {
    b
      ..writeln('#')
      ..writeln('# UNRESOLVED — mapping paths that are not string literals:');
    for (final u in scan.unresolvedPathExpressions) {
      b.writeln('#   $u');
    }
  }
  b.writeln();
  for (final p in scan.paths) {
    b.writeln(p);
  }
  return b.toString();
}

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final root = findPackageRoot();
  final src = locateBackendSource(packageRoot: root);
  if (src == null) {
    stderr
      ..writeln('Backend source not found. Looked in:')
      ..writeln(backendSearchPaths(packageRoot: root)
          .map((c) => '  $c')
          .join('\n'))
      ..writeln('Set $backendSrcEnvVar=/path/to/avdp_inteshar_be/src/main/java '
          'to point at it explicitly.');
    exitCode = 2;
    return;
  }

  final scan = scanBackendRoutes(src);
  final fixture = File(_join(root.path, fixturePath));
  final rendered = renderFixture(scan);

  stdout
    ..writeln('Backend: ${src.path}')
    ..writeln('${scan.paths.length} distinct routes '
        '(${scan.routes.length} mappings) across ${scan.controllerCount} controllers.');
  for (final r in scan.methodLevelRequestMappings) {
    stdout.writeln('  note: method-level @RequestMapping not counted — '
        '${r.path} (${r.origin})');
  }
  for (final u in scan.unresolvedPathExpressions) {
    stdout.writeln('  note: non-literal mapping path — $u');
  }

  final current = fixture.existsSync() ? parseFixture(fixture.readAsStringSync()) : const <String>[];
  final added = scan.paths.where((p) => !current.contains(p)).toList();
  final removed = current.where((p) => !scan.paths.contains(p)).toList();

  if (checkOnly) {
    if (added.isEmpty && removed.isEmpty) {
      stdout.writeln('$fixturePath is up to date.');
      return;
    }
    stderr.writeln('$fixturePath is STALE. Run: $regenerateCommand');
    for (final a in added) {
      stderr.writeln('  + $a');
    }
    for (final r in removed) {
      stderr.writeln('  - $r');
    }
    exitCode = 1;
    return;
  }

  fixture.writeAsStringSync(rendered);
  if (added.isEmpty && removed.isEmpty) {
    stdout.writeln('$fixturePath unchanged.');
  } else {
    stdout.writeln('$fixturePath rewritten: '
        '${added.length} added, ${removed.length} removed.');
    for (final a in added) {
      stdout.writeln('  + $a');
    }
    for (final r in removed) {
      stdout.writeln('  - $r');
    }
    stdout.writeln('Add a phrase for each new route in '
        'lib/features/system_activity/domain/log_phrase.dart.');
  }
}

// ───────────────────────────── parsing internals ─────────────────────────────

final RegExp _classDeclaration = RegExp(r'\bclass\s+\w+');
final RegExp _requestMapping = RegExp(r'@RequestMapping\b');
final RegExp _verbMapping = RegExp(r'@(Get|Post|Put|Patch|Delete)Mapping\b');
final RegExp _namedArg = RegExp(r'^\s*(\w+)\s*=\s*([\s\S]*)$');
final RegExp _stringLiteral = RegExp(r'"([^"]*)"');

List<File> _javaFiles(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.java'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Blanks out `//` and `/* */` comments while preserving offsets/line numbers,
/// so a commented-out `@PostMapping` is never mistaken for a live route.
String stripJavaComments(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '"' || c == "'") {
      final quote = c;
      out.write(c);
      i++;
      while (i < src.length) {
        final d = src[i];
        if (d == r'\' && i + 1 < src.length) {
          out
            ..write(d)
            ..write(src[i + 1]);
          i += 2;
          continue;
        }
        out.write(d);
        i++;
        if (d == quote) break;
      }
      continue;
    }
    if (c == '/' && i + 1 < src.length) {
      final n = src[i + 1];
      if (n == '/') {
        while (i < src.length && src[i] != '\n') {
          i++;
        }
        continue;
      }
      if (n == '*') {
        i += 2;
        while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
          if (src[i] == '\n') out.write('\n');
          i++;
        }
        i = i + 2 > src.length ? src.length : i + 2;
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Text between the parentheses of the annotation ending at [end], or null when
/// the annotation has no argument list (`@GetMapping`).
String? _annotationArgs(String src, int end) {
  var i = end;
  while (i < src.length && (src[i] == ' ' || src[i] == '\t' || src[i] == '\n' || src[i] == '\r')) {
    i++;
  }
  if (i >= src.length || src[i] != '(') return null;
  final start = i;
  var depth = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '"') {
      i++;
      while (i < src.length) {
        if (src[i] == r'\') {
          i += 2;
          continue;
        }
        if (src[i] == '"') {
          i++;
          break;
        }
        i++;
      }
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return src.substring(start + 1, i);
    }
    i++;
  }
  return null;
}

/// The path(s) an annotation argument list declares. Returns `['']` for a bare
/// annotation or one that only sets unrelated attributes (`consumes = …`).
List<String> _pathsOf(String? args) {
  if (args == null || args.trim().isEmpty) return const [''];
  String? expr;
  for (final segment in _splitTopLevel(args)) {
    final named = _namedArg.firstMatch(segment);
    if (named == null) {
      expr ??= segment; // positional argument == the path
      continue;
    }
    final name = named.group(1);
    if (name == 'value' || name == 'path') {
      expr = named.group(2);
      break;
    }
  }
  if (expr == null) return const [''];
  final literals =
      _stringLiteral.allMatches(expr).map((m) => m.group(1)!).toList();
  return literals.isEmpty ? const [''] : literals;
}

/// True when the annotation declares a path we could not read (a constant).
bool _looksLikeExpression(String? args) {
  if (args == null || args.trim().isEmpty) return false;
  for (final segment in _splitTopLevel(args)) {
    final named = _namedArg.firstMatch(segment);
    final expr = named == null
        ? segment
        : (named.group(1) == 'value' || named.group(1) == 'path')
            ? named.group(2)!
            : null;
    if (expr == null) continue;
    if (!_stringLiteral.hasMatch(expr) && expr.trim().isNotEmpty) return true;
  }
  return false;
}

List<String> _splitTopLevel(String args) {
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var i = 0;
  while (i < args.length) {
    final c = args[i];
    if (c == '"') {
      buf.write(c);
      i++;
      while (i < args.length) {
        if (args[i] == r'\') {
          buf.write(args.substring(i, (i + 2).clamp(0, args.length)));
          i += 2;
          continue;
        }
        buf.write(args[i]);
        i++;
        if (args[i - 1] == '"') break;
      }
      continue;
    }
    if (c == '(' || c == '{' || c == '[') depth++;
    if (c == ')' || c == '}' || c == ']') depth--;
    if (c == ',' && depth == 0) {
      parts.add(buf.toString());
      buf.clear();
      i++;
      continue;
    }
    buf.write(c);
    i++;
  }
  if (buf.isNotEmpty) parts.add(buf.toString());
  return parts;
}

String _joinRoute(String base, String suffix) {
  var path = '$base$suffix';
  if (path.isEmpty) return path;
  path = path.replaceAll(RegExp(r'/{2,}'), '/');
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path.startsWith('/') ? path : '/$path';
}

int _lineAt(String src, int offset) =>
    '\n'.allMatches(src.substring(0, offset)).length + 1;

String _join(String a, String b) =>
    a.endsWith(Platform.pathSeparator) ? '$a$b' : '$a${Platform.pathSeparator}$b';
