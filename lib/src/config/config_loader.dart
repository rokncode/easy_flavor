import 'dart:io';

import 'package:path/path.dart' as p;

import 'easy_flavor_config.dart';
import 'flavor_resolver.dart';

/// Reads `easy_flavor.yaml` from [projectRoot]; empty if the file is missing.
PartialConfig loadConfigFile(String projectRoot) {
  final path = p.join(projectRoot, EasyFlavorConfig.fileName);
  final file = File(path);
  if (!file.existsSync()) return const PartialConfig();
  return EasyFlavorConfig.parse(file.readAsStringSync(), sourceUrl: path);
}

/// The complete config easy_flavor last applied, or null if the project has
/// no `easy_flavor.yaml` (or it lists no flavors).
///
/// Files written by easy_flavor are complete; for hand-written ones, missing
/// identifiers default from the production flavor (or the first flavor).
EasyFlavorConfig? loadAppliedConfig(String projectRoot) {
  final file = loadConfigFile(projectRoot);
  if (file.flavors.isEmpty) return null;
  final base = file.flavors.firstWhere(
    (f) => isProductionFlavor(f.name),
    orElse: () => file.flavors.first,
  );
  final baseId = base.androidId ?? base.iosBundleId ?? 'com.example.app';
  return resolveConfig(
    file: file,
    cli: const PartialConfig(),
    baseId: isProductionFlavor(base.name)
        ? baseId
        : _stripSuffix(baseId, base.name),
    iosBaseId: base.iosBundleId == null
        ? null
        : (isProductionFlavor(base.name)
              ? base.iosBundleId
              : _stripSuffix(base.iosBundleId!, base.name)),
    baseAppName: base.appName ?? 'App',
  );
}

String _stripSuffix(String id, String flavor) => id.endsWith('.$flavor')
    ? id.substring(0, id.length - flavor.length - 1)
    : id;
