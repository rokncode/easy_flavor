import 'package:mason_logger/mason_logger.dart';

import '../config/easy_flavor_config.dart';
import '../core/backup.dart';
import '../core/diff.dart';
import '../core/exceptions.dart';
import '../core/git.dart';
import '../core/pipeline.dart';
import '../core/project_context.dart';
import '../core/summary.dart';

/// Plans the changes for [config] and applies them (or prints them with
/// `--dry-run`). Shared by create, init, add and remove.
///
/// Before writing to an existing project it checks git (uncommitted changes
/// need [force] or a confirmation) and backs up every file it will touch to
/// `.easy_flavor_backup/<timestamp>/`. [freshProject] skips both for
/// projects `create` has just generated.
Future<int> runSetup({
  required ProjectContext context,
  required EasyFlavorConfig config,
  EasyFlavorConfig? previous,
  bool confirm = false,
  bool force = false,
  bool freshProject = false,
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
    if (logger.level.index <= Level.verbose.index) {
      for (final c in changes.changes) {
        logger.info('');
        logger.info(unifiedDiff(c.before ?? '', c.after ?? '', path: c.path));
      }
    }
    if (!freshProject) await _checkGit(context, force: true);
    logger.info('');
    logger.info(
      lightCyan.wrap(
        'Dry run: no files were written.'
        '${logger.level.index > Level.verbose.index ? ' Add --verbose to see diffs.' : ''}',
      ),
    );
    return ExitCode.success.code;
  }

  if (!freshProject) await _checkGit(context, force: force);

  if (confirm &&
      context.interactive &&
      !logger.confirm('Apply these changes?', defaultValue: true)) {
    throw EasyFlavorException(
      'Aborted; nothing was changed.',
      exitCode: ExitCode.success,
    );
  }

  Backup? backup;
  if (!freshProject) {
    backup = Backup.create(context.root, changes);
    if (backup != null) {
      logger.detail(
        'Backed up ${backup.entries.length} file(s) to ${backup.dir.path}.',
      );
    }
  }
  try {
    await changes.applyAll(context.processRunner);
  } on Object {
    if (backup != null) {
      logger.err(
        'Setup failed part-way. Undo everything with: '
        'easy_flavor restore ${backup.id}',
      );
    }
    rethrow;
  }
  logger.success('Flavors configured in ${context.root}.');
  if (backup != null) {
    logger.info(
      darkGray.wrap(
        'Backup: $backupDirName/${backup.id} '
        '(undo with `easy_flavor restore ${backup.id}`)',
      ),
    );
  }

  printRunCommands(logger, config);
  return ExitCode.success.code;
}

/// Warns about (or, without [force], stops on) uncommitted changes.
Future<void> _checkGit(ProjectContext context, {required bool force}) async {
  final logger = context.logger;
  final git = await readGitStatus(context.processRunner, context.root);
  if (!git.isRepo) {
    logger.warn(
      'This project is not a git repository; the backup in $backupDirName/ '
      'is the only way to undo these changes.',
    );
    return;
  }
  if (git.isClean) return;
  logger.warn(
    'The project has ${git.changes.length} uncommitted change(s). Commit or '
    'stash them first so easy_flavor\'s changes are easy to review.',
  );
  if (force || context.dryRun) return;
  if (context.interactive &&
      logger.confirm('Continue anyway?', defaultValue: false)) {
    return;
  }
  throw EasyFlavorException(
    'Stopped because of uncommitted changes.',
    hint: 'Commit or stash them, or re-run with --force.',
  );
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
            firebaseProjectId: context.logger
                .prompt('Firebase project id for "${f.name}":')
                .trim(),
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
