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
    for (final f in existingFlavors) f.name,
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
    if (const {
          'create',
          'register',
          'maybeCreate',
          'getByName',
          'named',
        }.contains(b.name) &&
        b.args != null) {
      return unquoteGradleString(b.args!);
    }
    if (b.args == null && b.name.isNotEmpty && !b.name.contains('.')) {
      return b.name;
    }
    return null;
  }

  /// Flavors declared outside the managed block, with the values
  /// easy_flavor can read from them (for `init --merge`).
  List<ExistingAndroidFlavor> get existingFlavors {
    final defaultId = applicationId;
    return [
      for (final pf in _productFlavorBlocks())
        if (!_isManaged(pf.start))
          for (final f in pf.children)
            if (_flavorName(f) case final name?)
              _readExisting(name, f.body(source), defaultId),
    ];
  }

  static ExistingAndroidFlavor _readExisting(
    String name,
    String body,
    String? defaultId,
  ) {
    String? literal(String key) {
      final m = RegExp(
        '^\\s*$key\\s*=?\\s*(["\'][^"\'\\n]*["\'])\\s*\$',
        multiLine: true,
      ).firstMatch(body);
      return m == null ? null : unquoteGradleString(m.group(1)!);
    }

    final id = literal('applicationId');
    final suffix = literal('applicationIdSuffix');
    final appName = RegExp(
      r"""resValue\s*\(?\s*["']string["']\s*,\s*["']app_name["']\s*,\s*(["'][^"'\n]*["'])""",
    ).firstMatch(body);
    return ExistingAndroidFlavor(
      name: name,
      applicationId:
          id ?? (defaultId == null ? null : '$defaultId${suffix ?? ''}'),
      appName: appName == null ? null : unquoteGradleString(appName.group(1)!),
      dimension: literal('dimension'),
    );
  }

  /// Flavor dimensions declared outside the managed block.
  Set<String> get existingDimensions {
    final dims = {
      for (final f in existingFlavors)
        if (f.dimension != null) f.dimension!,
    };
    final a = android;
    if (a == null) return dims;
    final body = a.body(source);
    final offset = a.open + 1;
    for (final m in RegExp(r'flavorDimensions[^\n]*').allMatches(body)) {
      if (_isManaged(offset + m.start)) continue;
      for (final q in RegExp(r"""["']([^"']+)["']""").allMatches(m.group(0)!)) {
        dims.add(q.group(1)!);
      }
    }
    return dims;
  }

  /// Returns the source with the managed block set to [flavors].
  ///
  /// Normally the block is inserted after `defaultConfig { }` (or replaced
  /// in place) and unmanaged flavors are an error. With [merge], flavors the
  /// project already declares are configured on top of its own
  /// `productFlavors` block, in its flavor dimension.
  String withFlavors(
    List<FlavorSpec> flavors,
    AppNameSource appName, {
    bool merge = false,
  }) {
    final existing = existingFlavors;
    if (existing.isNotEmpty && !merge) {
      throw ProjectError(
        '$path already declares productFlavors '
        '(${existing.map((f) => f.name).join(', ')}) that easy_flavor does not '
        'manage.',
        hint:
            'Remove them, or re-run `easy_flavor init --merge` to adopt them.',
      );
    }
    String? dimension;
    if (merge && existing.isNotEmpty) {
      final dims = existingDimensions;
      if (dims.length > 1) {
        throw ProjectError(
          '$path uses several flavor dimensions (${dims.join(', ')}).',
          hint:
              'easy_flavor can only merge with a single dimension; Flutter '
              'flavors map to one dimension.',
        );
      }
      dimension = dims.isEmpty ? null : dims.single;
    }
    String render(String indent) => renderFlavorBlock(
      flavors,
      dsl,
      appName,
      indent: indent,
      dimension: dimension,
      adopted: {for (final f in existing) f.name},
    );

    final range = managedRange;
    if (range != null) {
      return source.replaceRange(
        range.$1,
        range.$2,
        render(_indentOfLine(range.$1)),
      );
    }

    final androidBlock = _requireAndroid;
    // Merging: after the project's own productFlavors, so its flavors exist
    // and our settings win.
    final anchor = existing.isNotEmpty
        ? _productFlavorBlocks().last
        : androidBlock.child('defaultConfig');
    if (anchor != null) {
      final block = render(
        _indentOfLine(source.lastIndexOf('\n', anchor.start) + 1),
      );
      // After the line holding the anchor's closing brace.
      var at = source.indexOf('\n', anchor.close);
      at = at == -1 ? source.length : at + 1;
      return source.replaceRange(at, at, '\n$block');
    }
    // Before the line holding android's closing brace.
    final block = render(
      '${_indentOfLine(source.lastIndexOf('\n', androidBlock.start) + 1)}    ',
    );
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
///
/// With [dimension] (merge mode), the project's own flavor dimension is used
/// and not declared again; flavors in [adopted] already exist in the
/// project's `productFlavors` and are configured rather than created, with
/// any `applicationIdSuffix` cleared so `applicationId` is exact.
String renderFlavorBlock(
  List<FlavorSpec> flavors,
  GradleDsl dsl,
  AppNameSource appName, {
  String indent = '    ',
  String? dimension,
  Set<String> adopted = const {},
}) {
  final kts = dsl == GradleDsl.kotlin;
  final merging = dimension != null || adopted.isNotEmpty;
  final dim = dimension ?? flavorDimension;
  String set(String key, String value) => kts ? '$key = $value' : '$key $value';
  final lines = <String>[
    '$beginMarker (generated from easy_flavor.yaml; edits here are overwritten)',
    // AGP 9 disables resValue by default.
    if (appName == AppNameSource.resValue) ...[
      'buildFeatures {',
      '    ${set('resValues', 'true')}',
      '}',
    ],
    if (!merging)
      set(
        'flavorDimensions',
        '"$flavorDimension"',
      ).replaceFirst('flavorDimensions = ', 'flavorDimensions += '),
    'productFlavors {',
    for (final f in flavors) ...[
      if (!kts)
        '    ${f.name} {'
      else if (adopted.contains(f.name))
        '    getByName("${f.name}") {'
      else
        '    create("${f.name}") {',
      '        ${set('dimension', '"$dim"')}',
      '        ${set('applicationId', '"${f.androidId}"')}',
      if (adopted.contains(f.name)) '        applicationIdSuffix = null',
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

/// A flavor declared in the project's own `productFlavors` block.
class ExistingAndroidFlavor {
  ExistingAndroidFlavor({
    required this.name,
    this.applicationId,
    this.appName,
    this.dimension,
  });

  final String name;

  /// Effective id: its `applicationId`, or defaultConfig's plus its suffix.
  final String? applicationId;
  final String? appName;
  final String? dimension;
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
