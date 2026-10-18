import 'package:mason_logger/mason_logger.dart';

import '../config/config_loader.dart';
import '../config/easy_flavor_config.dart';
import '../core/exceptions.dart';
import '../core/flutter_project.dart';
import '../core/generator.dart';
import '../core/pipeline.dart';
import '../core/summary.dart';
import 'base_command.dart';

/// `easy_flavor doctor`: report problems with the current flavor setup.
class DoctorCommand extends EasyFlavorCommand {
  DoctorCommand({required super.logger, super.processRunner});

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check the flavor setup (Gradle, Xcode, Firebase) and report issues.';

  @override
  Future<int> run() async {
    final root = requireFlutterProject(projectDirArg);
    final context = contextFor(root);

    final EasyFlavorConfig? config;
    try {
      config = loadAppliedConfig(root);
    } on EasyFlavorException catch (e) {
      _report([Issue(Severity.error, e.message, fix: e.hint)]);
      return ExitCode.config.code;
    }
    if (config == null) {
      _report([
        const Issue(
          Severity.error,
          'No ${EasyFlavorConfig.fileName} found.',
          fix: 'Run `easy_flavor init`.',
        ),
      ]);
      return ExitCode.config.code;
    }

    printFlavorTable(logger, config);
    logger.info('');

    final issues = <Issue>[
      if (!await processRunner.isAvailable('flutter'))
        const Issue(Severity.warning, 'flutter is not on PATH.'),
      for (final g in defaultGenerators)
        if (g case final Checker c) ...c.check(context, config),
    ];
    _report(issues);
    return issues.any((i) => i.severity == Severity.error)
        ? ExitCode.software.code
        : ExitCode.success.code;
  }

  void _report(List<Issue> issues) {
    if (issues.isEmpty) {
      logger.success('No issues found.');
      return;
    }
    for (final i in issues) {
      final label = switch (i.severity) {
        Severity.error => red.wrap('✗ error  '),
        Severity.warning => yellow.wrap('! warning'),
        Severity.info => lightBlue.wrap('• info   '),
      };
      logger.info('$label ${i.message}');
      if (i.fix != null) {
        logger.info('          ${darkGray.wrap('→ ${i.fix}')}');
      }
    }
  }
}
