import 'package:mason_logger/mason_logger.dart';

import '../core/backup.dart';
import '../core/flutter_project.dart';
import 'base_command.dart';

/// `easy_flavor restore [<backup>]`: undo a run using its backup.
class RestoreCommand extends EasyFlavorCommand {
  RestoreCommand({required super.logger, super.processRunner}) {
    argParser.addFlag(
      'list',
      abbr: 'l',
      help: 'List backups instead of restoring.',
      negatable: false,
    );
  }

  @override
  String get name => 'restore';

  @override
  String get description =>
      'Undo an easy_flavor run from $backupDirName/ (default: the latest).';

  @override
  String get invocation => 'easy_flavor restore [<backup>] [options]';

  @override
  Future<int> run() async {
    final root = requireFlutterProject(projectDirArg);
    if (args.flag('list')) {
      final all = Backup.list(root);
      if (all.isEmpty) {
        logger.info('No backups.');
      }
      for (final b in all) {
        logger.info('${b.id}  (${b.entries.length} file(s))');
      }
      return ExitCode.success.code;
    }
    if (args.rest.length > 1) usageException('Expected at most one backup.');
    final backup = Backup.find(root, args.rest.firstOrNull);
    for (final e in backup.entries.entries) {
      final action = e.value == BackupEntry.existed ? 'restore' : 'delete ';
      logger.info('  $action  ${e.key}');
    }
    if (dryRun) {
      logger.info(lightCyan.wrap('Dry run: nothing was restored.'));
      return ExitCode.success.code;
    }
    if (interactive &&
        !logger.confirm('Restore backup ${backup.id}?', defaultValue: true)) {
      return ExitCode.success.code;
    }
    backup.restore(root);
    logger.success(
      'Restored ${backup.entries.length} file(s) from ${backup.id}.',
    );
    return ExitCode.success.code;
  }
}
