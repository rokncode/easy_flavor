import '../android/android_project.dart';
import '../config/config_loader.dart';
import '../config/easy_flavor_config.dart';
import '../config/flavor_resolver.dart';
import '../core/exceptions.dart';
import '../core/existing_flavors.dart';
import '../core/flutter_project.dart';
import '../ios/ios_project.dart';
import 'base_command.dart';
import 'setup_flow.dart';

/// `easy_flavor init`: add flavors to an existing project.
class InitCommand extends EasyFlavorCommand {
  InitCommand({required super.logger, super.processRunner}) {
    addFlavorOptions(argParser);
    argParser.addFlag(
      'merge',
      help:
          'If the project already has flavors, merge with them instead of aborting '
          '(asked interactively when omitted).',
      defaultsTo: null,
    );
    addSafetyOptions(argParser);
  }

  @override
  String get name => 'init';

  @override
  String get description => 'Add flavors to the existing Flutter project.';

  @override
  Future<int> run() async {
    final root = requireFlutterProject(projectDirArg);
    final context = contextFor(root);
    final file = loadConfigFile(root);
    var cli = flavorOverridesFrom(args);

    // Flavors the project already has outside easy_flavor.
    final detected = detectExistingFlavorConfig(context);
    var base = file;
    if (detected.flavors.isNotEmpty) {
      if (file.mergeExisting != true) {
        final names = detected.flavors.map((f) => f.name).join(', ');
        final merge = args.wasParsed('merge')
            ? args.flag('merge')
            : interactive &&
                  logger.confirm(
                    'This project already has flavors ($names). Merge with '
                    'them (keep your Gradle/Xcode setup and configure them '
                    'on top)?',
                  );
        if (!merge) {
          throw EasyFlavorException(
            'Project already has flavors: $names.',
            hint: 'Re-run with --merge to adopt them, or remove them first.',
          );
        }
      }
      base = layerConfig(
        layerConfig(detected, file),
        const PartialConfig(mergeExisting: true),
      );
    }

    if (!cli.hasFlavorList && base.flavors.isEmpty) {
      if (!interactive) {
        throw UsageError(
          'No flavors specified.',
          hint:
              'Pass --flavors dev,prod or create ${EasyFlavorConfig.fileName}.',
        );
      }
      cli = flavorOverridesFrom(
        args,
        defaultFlavors: promptFlavorNames(logger),
        defaultFirebase: args.wasParsed('firebase')
            ? null
            : file.firebase ??
                  logger.confirm(
                    'Set up Firebase for each flavor?',
                    defaultValue: false,
                  ),
      );
    }

    final packageName = readPackageName(root);
    final androidId = detectApplicationId(context);
    final iosId = detectBundleIdentifier(context);
    final fallbackId = 'com.example.${bundleSegmentFromPackage(packageName)}';
    final config = resolveConfig(
      file: base,
      cli: cli,
      baseId: androidId ?? iosId ?? fallbackId,
      iosBaseId: iosId ?? iosBundleIdFromAndroid(androidId ?? fallbackId),
      baseAppName: titleCaseFromPackage(packageName),
    );
    if (androidId == null && iosId == null) {
      logger.warn(
        'Could not detect the existing applicationId / bundle id; '
        'defaults are based on $fallbackId. Pass --bundle-ids to set them explicitly.',
      );
    }

    return runSetup(
      context: context,
      config: config,
      previous: loadAppliedConfig(root),
      confirm: true,
      force: args.flag('force'),
    );
  }
}
