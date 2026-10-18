import '../core/exceptions.dart';

const mainFile = 'lib/main.dart';

/// Comment on the line that selects the default flavor in `lib/main.dart`.
const defaultFlavorMarker = '// easy_flavor:default-flavor';

// A top-level function declaration starting at column 0, with an optional
// return type, e.g. `void main() {`, `Future<void> main() async {`,
// `main() => ...`.
RegExp _topLevelFunction(String name) => RegExp(
  r'^(?:([A-Za-z_][\w<>?, ]*?)\s+)?' +
      name +
      r'\s*\(([^)]*)\)\s*(?:async\s*)?(?:\{|=>)',
  multiLine: true,
);

final _runMainAppDecl = _topLevelFunction('runMainApp');
final _mainDecl = _topLevelFunction('main');
final _defaultFlavorLine = RegExp(
  r'FlavorConfig\.init\(Flavor\.(\w+)\);(\s*)' +
      RegExp.escape(defaultFlavorMarker),
);

/// Result of [refactorMainDart].
class MainDartRefactor {
  MainDartRefactor(this.source, {required this.runMainAppReturnsFuture});

  final String source;
  final bool runMainAppReturnsFuture;
}

/// Refactors `lib/main.dart` so flavor entry points can share it:
///
/// * the existing top-level `main` is renamed to `runMainApp`;
/// * a new `main` is added that selects [flavor] and calls `runMainApp`, so
///   `lib/main.dart` keeps working as the default entry point;
/// * `import 'flavors.dart';` is added.
///
/// On an already refactored file only the default flavor is updated. A file
/// that declares `runMainApp` without easy_flavor's marker was set up by hand
/// and is left alone.
MainDartRefactor refactorMainDart(String source, String flavor) {
  final existing = _runMainAppDecl.firstMatch(source);
  if (existing != null) {
    final returnsFuture = existing.group(1)?.startsWith('Future') ?? false;
    return MainDartRefactor(
      source.replaceFirstMapped(
        _defaultFlavorLine,
        (m) =>
            'FlavorConfig.init(Flavor.$flavor);${m.group(2)}$defaultFlavorMarker',
      ),
      runMainAppReturnsFuture: returnsFuture,
    );
  }

  final main = _mainDecl.firstMatch(source);
  if (main == null) {
    throw ProjectError(
      'Could not find a top-level main() in $mainFile.',
      hint:
          'Add `void runMainApp()` that starts your app; the flavor entry '
          'points call it.',
    );
  }
  if (main.group(2)!.trim().isNotEmpty) {
    throw ProjectError(
      'main() in $mainFile takes parameters, which flavor entry points cannot pass.',
      hint:
          'Move the app start-up into `runMainApp()` without parameters, then re-run.',
    );
  }

  final returnsFuture = main.group(1)?.startsWith('Future') ?? false;
  final nameStart = main.start + main.group(0)!.indexOf(RegExp(r'\bmain\s*\('));
  var result = source.replaceRange(
    nameStart,
    nameStart + 'main'.length,
    'runMainApp',
  );

  final newMain = returnsFuture
      ? '''
Future<void> main() async {
  FlavorConfig.init(Flavor.$flavor); $defaultFlavorMarker
  await runMainApp();
}

'''
      : '''
void main() {
  FlavorConfig.init(Flavor.$flavor); $defaultFlavorMarker
  runMainApp();
}

''';
  result = result.replaceRange(
    _declarationStart(result, main.start),
    _declarationStart(result, main.start),
    newMain,
  );
  return MainDartRefactor(
    _addImport(result, "import 'flavors.dart';"),
    runMainAppReturnsFuture: returnsFuture,
  );
}

/// Whether [source] (a refactored main.dart) has `runMainApp` returning a
/// Future. Defaults to false.
bool runMainAppReturnsFuture(String source) =>
    _runMainAppDecl.firstMatch(source)?.group(1)?.startsWith('Future') ?? false;

/// Moves [offset] up past doc comments and annotations directly above it, so
/// the new main does not end up between `runMainApp` and its comments.
int _declarationStart(String source, int offset) {
  var start = offset;
  while (start > 0) {
    final prevEnd = start - 1; // the '\n' before the current line
    final prevStart = source.lastIndexOf('\n', prevEnd - 1) + 1;
    final line = source.substring(prevStart, prevEnd).trim();
    if (line.startsWith('///') || line.startsWith('@')) {
      start = prevStart;
    } else {
      break;
    }
  }
  return start;
}

String _addImport(String source, String directive) {
  if (source.contains(directive) ||
      source.contains(directive.replaceAll("'", '"'))) {
    return source;
  }
  final imports = RegExp(
    r'''^import\s+['"][^'"]+['"][^;]*;[ \t]*\n''',
    multiLine: true,
  ).allMatches(source).toList();
  if (imports.isEmpty) return '$directive\n\n$source';
  final at = imports.last.end;
  return source.replaceRange(at, at, '$directive\n');
}
