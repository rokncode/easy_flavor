import '../config/flavor_spec.dart';
import '../core/exceptions.dart';
import 'gradle_parser.dart';

enum GradleDsl { groovy, kotlin }

/// The app module build script, relative to the project root.
const groovyBuildFile = 'android/app/build.gradle';
const kotlinBuildFile = 'android/app/build.gradle.kts';

const beginMarker = '// easy_flavor:begin';
const endMarker = '// easy_flavor:end';

/// Gradle flavor dimension used for the generated flavors.
const flavorDimension = 'flavor';

/// How the app name reaches the manifest's `@string/app_name`.
enum AppNameSource {
  /// `resValue("string", "app_name", ...)` in each flavor (default).
  resValue,

  /// `src/<flavor>/res/values/strings.xml`, used when the main source set
  /// already defines `app_name` (a resValue would then be a duplicate
  /// resource).
  flavorStringsXml,
}

/// A parsed app-module build script.
class GradleFile {
  GradleFile(this.path, this.source)
    : dsl = path.endsWith('.kts') ? GradleDsl.kotlin : GradleDsl.groovy {
    try {
      _blocks = parseGradleBlocks(source);
    } on FormatException catch (e) {
      throw ProjectError(
        'Could not parse $path: ${e.message}.',
        hint: 'Check the file for unbalanced braces or quotes.',
      );
    }
  }

  final String path;
  final String source;
  final GradleDsl dsl;
  late final List<GradleBlock> _blocks;

  GradleBlock? get android {
    for (final b in _blocks) {
      if (b.name == 'android') return b;
    }
    return null;
  }

  GradleBlock get _requireAndroid =>
      android ?? (throw ProjectError('No `android { }` block found in $path.'));

  /// Offsets of the managed region (start of the begin-marker line to the end
  /// of the end-marker line, including its newline), if present.
  (int, int)? get managedRange {
    final begin = source.indexOf(beginMarker);
    if (begin == -1) return null;
    final end = source.indexOf(endMarker, begin);
    if (end == -1) {
      throw ProjectError(
        'Found "$beginMarker" without "$endMarker" in $path.',
        hint: 'Restore the end marker or delete the partial block.',
      );
    }
    final lineStart = source.lastIndexOf('\n', begin) + 1;
    var lineEnd = source.indexOf('\n', end);
    lineEnd = lineEnd == -1 ? source.length : lineEnd + 1;
    return (lineStart, lineEnd);
  }

  bool _isManaged(int offset) {
    final r = managedRange;
    return r != null && offset >= r.$1 && offset < r.$2;
  }

  /// `defaultConfig { applicationId ... }`, if it is a plain string literal.
  String? get applicationId {
    final defaultConfig = android?.child('defaultConfig');
    if (defaultConfig == null) return null;
    final match = RegExp(
      r'''^\s*applicationId\s*=?\s*(["'][^"'\n]*["'])\s*$''',
      multiLine: true,
    ).firstMatch(defaultConfig.body(source));
    return match == null ? null : unquoteGradleString(match.group(1)!);
  }

  /// Flavors declared in a `productFlavors` block that easy_flavor does not
  /// manage.
  List<String> get unmanagedFlavors => [
    for (final pf in _productFlavorBlocks())
      if (!_isManaged(pf.start))
        for (final f in pf.children) ?_flavorName(f),
  ];

  /// Flavors in the easy_flavor-managed block.
  List<String> get managedFlavors => [
    for (final pf in _productFlavorBlocks())
      if (_isManaged(pf.start))
        for (final f in pf.children) ?_flavorName(f),
  ];

  Iterable<GradleBlock> _productFlavorBlocks() sync* {
    final a = android;
    if (a == null) return;
    for (final c in a.children) {
      if (c.name == 'productFlavors') yield c;
    }
  }

  /// `dev { }` (Groovy), `create("dev") { }` / `register("dev")` (Kotlin).
  static String? _flavorName(GradleBlock b) {
    if ((b.name == 'create' ||
            b.name == 'register' ||
            b.name == 'maybeCreate') &&
        b.args != null) {
      return unquoteGradleString(b.args!);
    }
    if (b.args == null && b.name.isNotEmpty && !b.name.contains('.')) {
      return b.name;
    }
    return null;
  }

  /// Returns the source with the managed block set to [flavors]. Replaces an
  /// existing managed block in place, otherwise inserts it after
  /// `defaultConfig { }` (or at the end of `android { }`).
  String withFlavors(List<FlavorSpec> flavors, AppNameSource appName) {
    final unmanaged = unmanagedFlavors;
    if (unmanaged.isNotEmpty) {
      throw ProjectError(
        '$path already declares productFlavors (${unmanaged.join(', ')}) '
        'that easy_flavor does not manage.',
        hint:
            'Remove them, or re-run `easy_flavor init --merge` to adopt them.',
      );
    }

    final range = managedRange;
    if (range != null) {
      final indent = _indentOfLine(range.$1);
      final block = renderFlavorBlock(flavors, dsl, appName, indent: indent);
      return source.replaceRange(range.$1, range.$2, block);
    }

    final androidBlock = _requireAndroid;
    final anchor = androidBlock.child('defaultConfig');
    final indent = anchor != null
        ? _indentOfLine(source.lastIndexOf('\n', anchor.start) + 1)
        : '${_indentOfLine(source.lastIndexOf('\n', androidBlock.start) + 1)}    ';
    final block = renderFlavorBlock(flavors, dsl, appName, indent: indent);

    if (anchor != null) {
      // After the line holding defaultConfig's closing brace.
      var at = source.indexOf('\n', anchor.close);
      at = at == -1 ? source.length : at + 1;
      return source.replaceRange(at, at, '\n$block');
    }
    // Before the line holding android's closing brace.
    final at = source.lastIndexOf('\n', androidBlock.close) + 1;
    return source.replaceRange(at, at, '\n$block');
  }

  String _indentOfLine(int lineStart) {
    var j = lineStart;
    while (j < source.length && (source[j] == ' ' || source[j] == '\t')) {
      j++;
    }
    return source.substring(lineStart, j);
  }
}

/// Renders the managed block, each line prefixed with [indent], ending with
/// a newline.
String renderFlavorBlock(
  List<FlavorSpec> flavors,
  GradleDsl dsl,
  AppNameSource appName, {
  String indent = '    ',
}) {
  final kts = dsl == GradleDsl.kotlin;
  final lines = <String>[
    '$beginMarker (generated from easy_flavor.yaml; edits here are overwritten)',
    // AGP 9 disables resValue by default.
    if (appName == AppNameSource.resValue) ...[
      'buildFeatures {',
      kts ? '    resValues = true' : '    resValues true',
      '}',
    ],
    kts
        ? 'flavorDimensions += "$flavorDimension"'
        : 'flavorDimensions "$flavorDimension"',
    'productFlavors {',
    for (final f in flavors) ...[
      kts ? '    create("${f.name}") {' : '    ${f.name} {',
      kts
          ? '        dimension = "$flavorDimension"'
          : '        dimension "$flavorDimension"',
      kts
          ? '        applicationId = "${f.androidId}"'
          : '        applicationId "${f.androidId}"',
      if (appName == AppNameSource.resValue)
        kts
            ? '        resValue("string", "app_name", "${gradleResValueString(f.appName)}")'
            : '        resValue "string", "app_name", "${gradleResValueString(f.appName)}"',
      '    }',
    ],
    '}',
    endMarker,
  ];
  return '${lines.map((l) => '$indent$l').join('\n')}\n';
}

/// Escapes [value] for a double-quoted Gradle string (Groovy and Kotlin)
/// whose content becomes an Android string resource. AGP escapes XML
/// characters itself, but Android resource escapes (apostrophes, quotes) must
/// be added here.
String gradleResValueString(String value) {
  final android = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('"', r'\"');
  return android
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(r'$', r'\$');
}
