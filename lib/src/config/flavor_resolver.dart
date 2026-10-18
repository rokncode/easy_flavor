import '../core/exceptions.dart';
import 'easy_flavor_config.dart';
import 'flavor_spec.dart';
import 'validators.dart';

/// Names treated as the production flavor: it gets the base identifiers and
/// app name without a suffix.
const productionFlavorNames = {'prod', 'production', 'release', 'live'};

bool isProductionFlavor(String name) => productionFlavorNames.contains(name);

/// Combines the YAML file and CLI flags into a complete, validated config.
///
/// Precedence per field: CLI flag > easy_flavor.yaml > generated default.
/// The flavor list comes from `--flavors` if given, else from the file.
/// Defaults are derived from [baseId] (e.g. `com.company.myapp`, from
/// `--org` + app name for `create`, or the detected applicationId for `init`)
/// and [baseAppName].
EasyFlavorConfig resolveConfig({
  required PartialConfig file,
  required PartialConfig cli,
  required String baseId,
  required String baseAppName,
  String? iosBaseId,
}) {
  final fromFile = {for (final f in file.flavors) f.name: f};

  final List<String> names;
  if (cli.hasFlavorList) {
    names = [for (final f in cli.flavors) f.name];
  } else {
    names = [for (final f in file.flavors) f.name];
    final unknown = [
      for (final f in cli.flavors)
        if (!fromFile.containsKey(f.name)) f.name,
    ];
    if (unknown.isNotEmpty) {
      throw UsageError(
        'Unknown flavor(s): ${unknown.join(', ')}.',
        hint:
            'List them in --flavors or add them with `easy_flavor add <flavor>`.',
      );
    }
  }
  if (names.isEmpty) {
    throw UsageError(
      'No flavors specified.',
      hint:
          'Pass --flavors dev,prod or add them to ${EasyFlavorConfig.fileName}.',
    );
  }
  for (final n in names) {
    validateFlavorName(n);
  }

  final fromCli = {for (final f in cli.flavors) f.name: f};
  final flavors = <FlavorSpec>[];
  for (final name in names) {
    var partial = PartialFlavor(name: name);
    if (fromFile[name] case final f?) partial = partial.merge(f);
    if (fromCli[name] case final c?) partial = partial.merge(c);
    flavors.add(
      FlavorSpec(
        name: name,
        appName: partial.appName ?? defaultAppName(baseAppName, name),
        androidId: partial.androidId ?? defaultBundleId(baseId, name),
        iosBundleId:
            partial.iosBundleId ?? defaultBundleId(iosBaseId ?? baseId, name),
        firebaseProjectId: partial.firebaseProjectId,
      ),
    );
  }

  final config = EasyFlavorConfig(
    flavors: flavors,
    firebase: cli.firebase ?? file.firebase ?? false,
    ide: cli.ide ?? file.ide ?? IdeTarget.values,
  );
  validateConfig(config);
  return config;
}

/// `com.company.myapp` + `dev` -> `com.company.myapp.dev`; prod keeps the base.
String defaultBundleId(String baseId, String flavor) =>
    isProductionFlavor(flavor) ? baseId : '$baseId.$flavor';

/// `MyApp` + `staging` -> `MyApp Staging`; prod keeps the base.
String defaultAppName(String baseAppName, String flavor) {
  if (isProductionFlavor(flavor)) return baseAppName;
  return '$baseAppName ${flavor[0].toUpperCase()}${flavor.substring(1)}';
}

/// `my_app` -> `My App`.
String titleCaseFromPackage(String packageName) => packageName
    .split(RegExp(r'[_\s]+'))
    .where((s) => s.isNotEmpty)
    .map((s) => s[0].toUpperCase() + s.substring(1))
    .join(' ');

/// `my_app` -> `myapp` (bundle-id friendly segment, like `flutter create`
/// does for iOS, but also valid for Android).
String bundleSegmentFromPackage(String packageName) =>
    packageName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
