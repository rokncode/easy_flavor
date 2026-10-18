import 'package:mason_logger/mason_logger.dart';

import '../config/easy_flavor_config.dart';
import '../core/exceptions.dart';
import '../core/pipeline.dart';
import '../core/project_context.dart';
import '../core/summary.dart';

/// Plans the changes for [config] and applies them (or prints them with
/// `--dry-run`). Shared by create, init, add and remove.
///
/// [allowWrite] is only set for freshly created projects until backups exist.
Future<int> runSetup({
  required ProjectContext context,
  required EasyFlavorConfig config,
  EasyFlavorConfig? previous,
  bool confirm = false,
  bool allowWrite = false,
}) async {
  final logger = context.logger;
  config = promptFirebaseProjects(context, config);
  logger.info('');
  printFlavorTable(logger, config);
  logger.info('');

  final progress = logger.progress('Planning changes');
  final changes = await planChanges(
    context: context,
    config: config,
    previous: previous,
  );
  progress.complete(
    'Planned ${changes.changes.length} file change(s)'
    '${changes.commands.isEmpty ? '' : ' and ${changes.commands.length} command(s)'}',
  );
  printChanges(logger, changes);

  if (changes.isEmpty) return ExitCode.success.code;

  if (context.dryRun) {
    logger.info('');
    logger.info(lightCyan.wrap('Dry run: no files were written.'));
    return ExitCode.success.code;
  }

  if (confirm &&
      context.interactive &&
      !logger.confirm('Apply these changes?', defaultValue: true)) {
    throw EasyFlavorException(
      'Aborted; nothing was changed.',
      exitCode: ExitCode.success,
    );
  }

  if (!allowWrite) {
    // TODO(step 5): git status check, backups to .easy_flavor_backup/, write.
    logger.warn(
      'Changing existing projects is enabled once backups are implemented '
      '(step 5); nothing was changed.',
    );
    return ExitCode.success.code;
  }
  await changes.applyAll(context.processRunner);
  logger.success('Flavors configured in ${context.root}.');

  printRunCommands(logger, config);
  return ExitCode.success.code;
}

/// Asks for missing Firebase project ids when Firebase is enabled and
/// prompts are allowed (the generator reports them otherwise).
EasyFlavorConfig promptFirebaseProjects(
  ProjectContext context,
  EasyFlavorConfig config,
) {
  if (!config.firebase || !context.interactive) return config;
  if (config.flavors.every((f) => f.firebaseProjectId != null)) return config;
  context.logger.info(
    'Each flavor needs a Firebase project id (see `firebase projects:list`).',
  );
  return config.copyWith(
    flavors: [
      for (final f in config.flavors)
        if (f.firebaseProjectId != null)
          f
        else
          f.copyWith(
            firebaseProjectId: context.logger.prompt(
              'Firebase project id for "${f.name}":',
            ).trim(),
          ),
    ],
  );
}

/// Asks for flavors when none were given and prompts are allowed.
List<String> promptFlavorNames(Logger logger) {
  final answer = logger.prompt(
    'Which flavors? (comma-separated)',
    defaultValue: 'dev,staging,prod',
  );
  return [
    for (final s in answer.split(','))
      if (s.trim().isNotEmpty) s.trim(),
  ];
}
