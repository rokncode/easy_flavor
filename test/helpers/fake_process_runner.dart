import 'dart:io';

import 'package:easy_flavor/src/core/process_runner.dart';
import 'package:path/path.dart' as p;

import 'fixtures.dart';

/// Records commands. `flutter create <dir>` copies the fresh_kts fixture;
/// [onRun] can simulate other tools' side effects.
class FakeProcessRunner extends ProcessRunner {
  FakeProcessRunner({
    this.missing = const {},
    this.loggedIn = true,
    this.onRun,
  });

  /// Executables reported as not installed.
  final Set<String> missing;
  final bool loggedIn;
  final void Function(String executable, List<String> args, String? cwd)? onRun;

  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    _handle(executable, arguments, workingDirectory);
    if (executable == 'firebase' && arguments.first == 'login:list') {
      return ProcessResult(
        0,
        0,
        loggedIn
            ? 'Logged in as someone'
            : 'No authorized accounts, run "firebase login"',
        '',
      );
    }
    return ProcessResult(0, 0, '', '');
  }

  @override
  Future<void> runInherit(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => _handle(executable, arguments, workingDirectory);

  @override
  Future<bool> isAvailable(String executable) async =>
      !missing.contains(executable);

  void _handle(String executable, List<String> arguments, String? cwd) {
    calls.add([executable, ...arguments]);
    if (executable == 'flutter' && arguments.first == 'create') {
      final target = Directory(arguments.last)..createSync(recursive: true);
      copyDirectory(Directory(p.join(fixturesDir, 'fresh_kts')), target);
    }
    onRun?.call(executable, arguments, cwd);
  }
}
