import '../core/exceptions.dart';
import 'easy_flavor_config.dart';

/// Builds a [PartialConfig] from command-line values.
///
/// `--flavors dev,prod` gives the flavor list (and order). Per-flavor
/// options use `flavor=value` pairs, e.g. `--bundle-ids dev=com.a.dev`.
/// A per-flavor value for a flavor not listed in `--flavors` is an error when
/// `--flavors` is given; otherwise the values are overrides for flavors that
/// must already exist in easy_flavor.yaml (checked by the resolver).
PartialConfig parseCliOverrides({
  List<String> flavors = const [],
  List<String> bundleIds = const [],
  List<String> androidIds = const [],
  List<String> iosBundleIds = const [],
  List<String> appNames = const [],
  List<String> firebaseProjects = const [],
  bool? firebase,
  List<String>? ide,
}) {
  final names = <String>[];
  for (final raw in flavors) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    if (names.contains(name)) {
      throw UsageError('Flavor "$name" is listed twice in --flavors.');
    }
    names.add(name);
  }

  final bundle = parsePairs('--bundle-ids', bundleIds);
  final android = parsePairs('--android-ids', androidIds);
  final ios = parsePairs('--ios-bundle-ids', iosBundleIds);
  final apps = parsePairs('--app-names', appNames);
  final projects = parsePairs('--firebase-projects', firebaseProjects);

  final mentioned = <String>{
    ...bundle.keys,
    ...android.keys,
    ...ios.keys,
    ...apps.keys,
    ...projects.keys,
  };
  if (names.isNotEmpty) {
    final unknown = mentioned.difference(names.toSet());
    if (unknown.isNotEmpty) {
      throw UsageError(
        'Values given for flavor(s) not in --flavors: ${unknown.join(', ')}.',
      );
    }
  }

  final order = names.isNotEmpty ? names : mentioned.toList();
  return PartialConfig(
    firebase: firebase,
    hasFlavorList: names.isNotEmpty,
    ide: ide?.map(IdeTarget.parse).toList(),
    flavors: [
      for (final name in order)
        PartialFlavor(
          name: name,
          appName: apps[name],
          // --android-ids / --ios-bundle-ids are more specific than --bundle-ids.
          androidId: android[name] ?? bundle[name],
          iosBundleId: ios[name] ?? bundle[name],
          firebaseProjectId: projects[name],
        ),
    ],
  );
}

/// Parses `key=value` items. Values may themselves contain `=`.
Map<String, String> parsePairs(String option, List<String> items) {
  final result = <String, String>{};
  for (final item in items) {
    if (item.trim().isEmpty) continue;
    final i = item.indexOf('=');
    if (i <= 0) {
      throw UsageError(
        'Invalid value "$item" for $option.',
        hint: 'Expected flavor=value, e.g. $option dev=value,prod=value',
      );
    }
    final key = item.substring(0, i).trim();
    var value = item.substring(i + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty) throw UsageError('Empty value for "$key" in $option.');
    result[key] = value;
  }
  return result;
}
