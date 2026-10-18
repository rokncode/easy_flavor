import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import 'commands/add_command.dart';
import 'commands/create_command.dart';
import 'commands/doctor_command.dart';
import 'commands/init_command.dart';
import 'commands/remove_command.dart';
import 'commands/restore_command.dart';
import 'core/exceptions.dart';
import 'core/process_runner.dart';
import 'version.dart';

const executableName = 'easy_flavor';

class EasyFlavorCommandRunner extends CommandRunner<int> {
  EasyFlavorCommandRunner({
    Logger? logger,
    ProcessRunner processRunner = const ProcessRunner(),
  }) : _logger = logger ?? Logger(),
       super(
         executableName,
         'Set up Flutter flavors for Android and iOS in one command.',
       ) {
    argParser
      ..addFlag('version', negatable: false, help: 'Print the current version.')
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Show detailed output.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the planned changes without writing anything.',
      )
      ..addFlag(
        'interactive',
        defaultsTo: true,
        help:
            'Prompt for missing values. Disabled automatically when stdin is not a terminal.',
      )
      ..addOption(
        'project-dir',
        abbr: 'C',
        help:
            'Flutter project root (create: parent directory). Defaults to the current directory.',
        valueHelp: 'path',
      );

    for (final command in [
      CreateCommand(logger: _logger, processRunner: processRunner),
      InitCommand(logger: _logger, processRunner: processRunner),
      AddCommand(logger: _logger, processRunner: processRunner),
      RemoveCommand(logger: _logger, processRunner: processRunner),
      DoctorCommand(logger: _logger, processRunner: processRunner),
      RestoreCommand(logger: _logger, processRunner: processRunner),
    ]) {
      addCommand(command);
    }
  }

  final Logger _logger;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final results = parse(args);
      if (results.flag('verbose')) _logger.level = Level.verbose;
      return await runCommand(results) ?? ExitCode.success.code;
    } on FormatException catch (e) {
      _logger
        ..err(e.message)
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      _logger
        ..err(e.message)
        ..info('')
        ..info(e.usage);
      return ExitCode.usage.code;
    } on EasyFlavorException catch (e) {
      _logger.err(e.message);
      if (e.hint != null) _logger.info(e.hint);
      return e.exitCode.code;
    }
  }

  @override
  void printUsage() => _logger.info(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      _logger.info(packageVersion);
      return ExitCode.success.code;
    }
    return super.runCommand(topLevelResults);
  }
}
