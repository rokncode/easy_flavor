import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../config/cli_overrides.dart';
import '../config/easy_flavor_config.dart';
import '../core/process_runner.dart';
import '../core/project_context.dart';

/// Shared plumbing for all easy_flavor commands.
abstract class EasyFlavorCommand extends Command<int> {
  EasyFlavorCommand({
    required this.logger,
    this.processRunner = const ProcessRunner(),
  });

  final Logger logger;
  final ProcessRunner processRunner;

  @override
  void printUsage() => logger.info(usage);

  ArgResults get args => argResults!;
  ArgResults get globals => globalResults!;

  bool get dryRun => globals.flag('dry-run');

  /// Prompts are allowed unless disabled or not attached to a terminal (CI,
  /// piped input/output).
  bool get interactive =>
      globals.flag('interactive') && stdin.hasTerminal && stdout.hasTerminal;

  /// The directory passed with `--project-dir`, or the current directory.
  String get projectDirArg =>
      globals.option('project-dir') ?? Directory.current.path;

  ProjectContext contextFor(String root) => ProjectContext(
    root: root,
    logger: logger,
    dryRun: dryRun,
    interactive: interactive,
  );

  /// Exactly one positional argument, e.g. `add <flavor>`.
  String singleRest(String label) {
    final rest = args.rest;
    if (rest.length != 1) usageException('Expected exactly one $label.');
    return rest.single;
  }
}

/// Adds the options that describe flavors (used by `create` and `init`).
void addFlavorOptions(ArgParser parser) {
  parser
    ..addMultiOption(
      'flavors',
      abbr: 'f',
      help: 'Comma-separated flavor names, e.g. dev,staging,prod.',
      valueHelp: 'names',
    )
    ..addMultiOption(
      'bundle-ids',
      help: 'Identifier per flavor for both Android and iOS.',
      valueHelp: 'dev=com.co.app.dev,prod=com.co.app',
    )
    ..addMultiOption(
      'android-ids',
      help: 'Android applicationId per flavor (overrides --bundle-ids).',
      valueHelp: 'flavor=id',
    )
    ..addMultiOption(
      'ios-bundle-ids',
      help: 'iOS bundle identifier per flavor (overrides --bundle-ids).',
      valueHelp: 'flavor=id',
    )
    ..addMultiOption(
      'app-names',
      help: 'Display name per flavor. Quote names with spaces.',
      valueHelp: 'dev="MyApp Dev",prod=MyApp',
    )
    ..addFlag(
      'firebase',
      help: 'Configure Firebase per flavor with the FlutterFire CLI.',
      defaultsTo: null,
    )
    ..addMultiOption(
      'firebase-projects',
      help: 'Firebase project id per flavor.',
      valueHelp: 'dev=myapp-dev,prod=myapp-prod',
    )
    ..addMultiOption(
      'ide',
      allowed: [for (final t in IdeTarget.values) t.id],
      help: 'IDE run configurations to generate (default: all).',
    );
}

/// Reads the options added by [addFlavorOptions]. [defaultFlavors] and
/// [defaultFirebase] are used when the matching flag was not passed (e.g.
/// answers from interactive prompts).
PartialConfig flavorOverridesFrom(
  ArgResults args, {
  List<String>? defaultFlavors,
  bool? defaultFirebase,
}) => parseCliOverrides(
  flavors: args.wasParsed('flavors')
      ? args.multiOption('flavors')
      : defaultFlavors ?? const [],
  bundleIds: args.multiOption('bundle-ids'),
  androidIds: args.multiOption('android-ids'),
  iosBundleIds: args.multiOption('ios-bundle-ids'),
  appNames: args.multiOption('app-names'),
  firebaseProjects: args.multiOption('firebase-projects'),
  firebase: args.wasParsed('firebase')
      ? args.flag('firebase')
      : defaultFirebase,
  ide: args.wasParsed('ide') ? args.multiOption('ide') : null,
);
