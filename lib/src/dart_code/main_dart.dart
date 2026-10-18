import '../core/exceptions.dart';

const mainFile = 'lib/main.dart';

/// Comment on the import that selects the default flavor in `lib/main.dart`.
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
final _defaultFlavorImport = RegExp(
  r"^import\s+'main_(\w+)\.dart'\s+as\s+default_flavor;[ \t]*" +
      RegExp.escape(defaultFlavorMarker),
  multiLine: true,
);

String _defaultFlavorImportLine(String flavor) =>
    "import 'main_$flavor.dart' as default_flavor; $defaultFlavorMarker";

const _newMain =
    '// Plain `flutter run` (without -t) starts the default flavor.\n'
    'Future<void> main() => default_flavor.main();\n'
    '\n';

/// Result of [refactorMainDart].
class MainDartRefactor {
  MainDartRefactor(this.source, {required this.runMainAppReturnsFuture});

  final String source;
  final bool runMainAppReturnsFuture;
}

/// Refactors `lib/main.dart` so flavor entry points can share it:
///
/// * the existing top-level `main` is renamed to `runMainApp`;
/// * a new `main` delegates to the default flavor's entry point
///   (`lib/main_<flavor>.dart`), so plain `flutter run` keeps working and
///   goes through the same start-up (flavor, Firebase) as `-t`.
///
/// On an already refactored file only the default-flavor import is updated.
/// A file that declares `runMainApp` without easy_flavor's marker was set up
/// by hand and is left alone.
MainDartRefactor refactorMainDart(String source, String flavor) {
  final existing = _runMainAppDecl.firstMatch(source);
  if (existing != null) {
    return MainDartRefactor(
      source.replaceFirst(
        _defaultFlavorImport,
        _defaultFlavorImportLine(flavor),
      ),
      runMainAppReturnsFuture: existing.group(1)?.startsWith('Future') ?? false,
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
  final at = _declarationStart(result, main.start);
  result = result.replaceRange(at, at, _newMain);
  return MainDartRefactor(
    _addImport(result, _defaultFlavorImportLine(flavor)),
    runMainAppReturnsFuture: returnsFuture,
  );
}

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
  final imports = RegExp(
    r'''^import\s+['"][^'"]+['"][^;]*;[^\n]*\n''',
    multiLine: true,
  ).allMatches(source).toList();
  if (imports.isEmpty) return '$directive\n\n$source';
  final at = imports.last.end;
  return source.replaceRange(at, at, '$directive\n');
}
