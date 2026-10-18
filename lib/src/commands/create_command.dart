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

    final platforms = args.multiOption('platforms');
    List<String> flutterCreateArgs(String dir) => [
      'create',
      '--org',
      org,
      '--project-name',
      projectName,
      '--platforms',
      platforms.join(','),
      if (args.option('description') case final d?) ...['--description', d],
      dir,
    ];

    if (dryRun) {
      // Plan against a throwaway project so the preview shows real changes.
      logger.info('Would run: flutter ${flutterCreateArgs(target).join(' ')}');
      final temp = Directory.systemTemp.createTempSync('easy_flavor_create_');
      try {
        final progress = logger.progress('Generating a preview project');
        final result = await processRunner.run(
          'flutter',
          flutterCreateArgs(p.join(temp.path, projectName)),
        );
        if (result.exitCode != 0) {
          progress.fail();
          throw ToolError('flutter create failed:\n${result.stderr}');
        }
        progress.complete();
        return await runSetup(
          context: contextFor(p.join(temp.path, projectName)),
          config: config,
        );
      } finally {
        temp.deleteSync(recursive: true);
      }
    }

    logger.info('${lightCyan.wrap('Step 1/2:')} flutter create');
    await processRunner.runInherit('flutter', flutterCreateArgs(target));
    logger.info('${lightCyan.wrap('Step 2/2:')} configure flavors');
    return runSetup(
      context: contextFor(target),
      config: config,
      allowWrite: true,
    );
  }
}
