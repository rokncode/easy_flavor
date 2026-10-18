import '../config/config_loader.dart';
import '../config/easy_flavor_config.dart';
import '../config/flavor_resolver.dart';
import '../config/flavor_spec.dart';
import '../config/validators.dart';
import '../core/exceptions.dart';
import '../core/flutter_project.dart';
import 'base_command.dart';
import 'setup_flow.dart';

/// `easy_flavor add <flavor>`.
class AddCommand extends EasyFlavorCommand {
  AddCommand({required super.logger, super.processRunner}) {
    argParser
      ..addOption(
        'app-name',
        help: 'Display name (default: "<prod name> <Flavor>").',
      )
      ..addOption('bundle-id', help: 'Identifier for both Android and iOS.')
      ..addOption(
        'android-id',
        help: 'Android applicationId (overrides --bundle-id).',
      )
      ..addOption(
        'ios-bundle-id',
        help: 'iOS bundle identifier (overrides --bundle-id).',
      )
      ..addOption(
        'firebase-project',
        help: 'Firebase project id for this flavor.',
      );
    addSafetyOptions(argParser);
  }

  @override
  String get name => 'add';

  @override
  String get description =>
      'Add a flavor to a project set up with easy_flavor.';

  @override
  String get invocation => 'easy_flavor add <flavor> [options]';

  @override
  Future<int> run() async {
    final flavor = singleRest('flavor name');
    validateFlavorName(flavor);
    final root = requireFlutterProject(projectDirArg);
    final current = requireAppliedConfig(root);
    if (current.flavor(flavor) != null) {
      throw UsageError('Flavor "$flavor" already exists.');
    }

    final base = current.flavors.firstWhere(
      (f) => isProductionFlavor(f.name),
      orElse: () => current.flavors.last,
    );
    final bundleId = args.option('bundle-id');
    final spec = FlavorSpec(
      name: flavor,
      appName: args.option('app-name') ?? defaultAppName(base.appName, flavor),
      androidId:
          args.option('android-id') ?? bundleId ?? '${base.androidId}.$flavor',
      iosBundleId:
          args.option('ios-bundle-id') ??
          bundleId ??
          '${base.iosBundleId}.$flavor',
      firebaseProjectId: args.option('firebase-project'),
    );
    final config = current.copyWith(flavors: [...current.flavors, spec]);
    validateConfig(config);

    return runSetup(
      context: contextFor(root),
      config: config,
      previous: current,
      force: args.flag('force'),
    );
  }
}

/// Loads easy_flavor.yaml or explains that `init` must run first.
EasyFlavorConfig requireAppliedConfig(String root) {
  final config = loadAppliedConfig(root);
  if (config == null) {
    throw ProjectError(
      'No flavors configured (${EasyFlavorConfig.fileName} not found or empty).',
      hint: 'Run `easy_flavor init` first.',
    );
  }
  return config;
}
