import '../core/exceptions.dart';
import 'easy_flavor_config.dart';

final _flavorName = RegExp(r'^[a-z][a-zA-Z0-9]*$');

// Android source set names and Gradle task prefixes that clash with flavors.
const _reservedByAndroid = {
  'main',
  'test',
  'androidTest',
  'debug',
  'release',
  'profile',
  'testFixtures',
};

// Dart keywords that would break `enum Flavor { ... }`.
const _reservedByDart = {
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
  'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
  'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
  'external', 'factory', 'false', 'final', 'finally', 'for', 'function', 'get',
  'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late',
  'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part', 'required',
  'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super', 'switch',
  'sync', 'this', 'throw', 'true', 'try', 'type', 'typedef', 'var', 'void',
  'when', 'while', 'with', 'yield',
  // Members of Enum / Object.
  'values', 'index', 'name', 'hashCode', 'runtimeType',
};

/// Throws [UsageError] if [name] cannot be used as a flavor on every
/// platform (Gradle flavor, Xcode configuration suffix, Dart enum value,
/// file name).
void validateFlavorName(String name) {
  if (!_flavorName.hasMatch(name)) {
    throw UsageError(
      'Invalid flavor name "$name".',
      hint:
          'Use a lowerCamelCase identifier starting with a letter, e.g. dev, staging, qa2.',
    );
  }
  if (_reservedByAndroid.contains(name) || _reservedByDart.contains(name)) {
    throw UsageError(
      '"$name" is reserved and cannot be used as a flavor name.',
    );
  }
}

final _androidId = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$');
final _iosBundleId = RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$');

void validateAndroidId(String flavor, String id) {
  if (!_androidId.hasMatch(id)) {
    throw UsageError(
      'Invalid Android applicationId "$id" for flavor "$flavor".',
      hint:
          'Needs at least two dot-separated segments, each starting with a letter '
          '(letters, digits and _ only).',
    );
  }
}

void validateIosBundleId(String flavor, String id) {
  if (!_iosBundleId.hasMatch(id)) {
    throw UsageError(
      'Invalid iOS bundle identifier "$id" for flavor "$flavor".',
      hint:
          'Use reverse-DNS with letters, digits, "-" and ".", e.g. com.company.app.dev',
    );
  }
}

/// Validates a fully resolved config.
void validateConfig(EasyFlavorConfig config) {
  if (config.flavors.isEmpty) {
    throw UsageError('At least one flavor is required.');
  }
  final androidIds = <String, String>{};
  final iosIds = <String, String>{};
  for (final f in config.flavors) {
    validateFlavorName(f.name);
    validateAndroidId(f.name, f.androidId);
    validateIosBundleId(f.name, f.iosBundleId);
    final a = androidIds[f.androidId];
    if (a != null) {
      throw UsageError(
        'Flavors "$a" and "${f.name}" share applicationId ${f.androidId}.',
      );
    }
    androidIds[f.androidId] = f.name;
    final i = iosIds[f.iosBundleId];
    if (i != null) {
      throw UsageError(
        'Flavors "$i" and "${f.name}" share bundle id ${f.iosBundleId}.',
      );
    }
    iosIds[f.iosBundleId] = f.name;
    if (f.appName.trim().isEmpty) {
      throw UsageError('Flavor "${f.name}" has an empty app name.');
    }
  }
}
