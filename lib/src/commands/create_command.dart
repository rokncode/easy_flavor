import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import '../config/easy_flavor_config.dart';
import '../config/flavor_resolver.dart';
import '../core/exceptions.dart';
import '../core/flutter_project.dart';
import 'base_command.dart';
import 'setup_flow.dart';

/// `easy_flavor create <name>`: `flutter create` + flavor setup.
class CreateCommand extends EasyFlavorCommand {
  CreateCommand({required super.logger, super.processRunner}) {
    argParser
      ..addOption(
        'org',
        help: 'Reverse-DNS organization, used for default identifiers.',
        defaultsTo: 'com.example',
      )
      ..addOption('description', help: 'Project description for pubspec.yaml.')
      ..addMultiOption(
        'platforms',
        help: 'Platforms passed to flutter create.',
        allowed: ['android', 'ios'],
        defaultsTo: ['android', 'ios'],
      );
    addFlavorOptions(argParser);
  }

  @override
  String get name => 'create';

  @override
  String get description =>
      'Create a new Flutter project with flavors configured.';

  @override
  String get invocation => 'easy_flavor create <project_name> [options]';

  @override
  Future<int> run() async {
    final projectName = singleRest('project name');
    if (!dartPackageName.hasMatch(projectName)) {
      throw UsageError(
        '"$projectName" is not a valid Dart package name.',
        hint: 'Use lowercase letters, digits and underscores, e.g. my_app.',
      );
    }
    final org = args.option('org')!;
    final target = p.absolute(projectDirArg, projectName);
    if (Directory(target).existsSync() &&
        Directory(target).listSync().isNotEmpty) {
      throw ProjectError('Directory $target already exists and is not empty.');
    }

    var cli = flavorOverridesFrom(args);
    if (!cli.hasFlavorList) {
      // Non-interactive runs fall back to the common three-flavor setup.
      cli = flavorOverridesFrom(
        args,
        defaultFlavors: interactive
            ? promptFlavorNames(logger)
            : const ['dev', 'staging', 'prod'],
        defaultFirebase: interactive && !args.wasParsed('firebase')
            ? logger.confirm(
                'Set up Firebase for each flavor?',
                defaultValue: false,
              )
            : null,
      );
    }

    final config = resolveConfig(
      file: const PartialConfig(),
      cli: cli,
      baseId: '$org.${bundleSegmentFromPackage(projectName)}',
      baseAppName: titleCaseFromPackage(projectName),
    );

    final flutterArgs = [
      'create',
      '--org',
      org,
      '--project-name',
      projectName,
      '--platforms',
      args.multiOption('platforms').join(','),
      if (args.option('description') case final d?) ...['--description', d],
      target,
    ];
    logger.info(
      '${lightCyan.wrap('Step 1/2:')} flutter ${flutterArgs.join(' ')}',
    );
    if (dryRun) {
      logger.info(
        'Dry run: skipping flutter create; showing flavor plan for an empty project.',
      );
    } else {
      // TODO(step 2): run flutter create, then plan against the new project.
      logger.warn('flutter create is not wired up yet (scaffold build).');
    }

    logger.info('${lightCyan.wrap('Step 2/2:')} configure flavors');
    return runSetup(context: contextFor(target), config: config);
  }
}
