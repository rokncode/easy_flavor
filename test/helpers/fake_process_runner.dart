import 'dart:io';

import 'package:easy_flavor/src/core/process_runner.dart';
import 'package:path/path.dart' as p;

import 'fixtures.dart';

/// Records commands; `flutter create <dir>` copies the fresh_kts fixture.
class FakeProcessRunner extends ProcessRunner {
  final calls = <List<String>>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    _handle(executable, arguments);
    return ProcessResult(0, 0, '', '');
  }

  @override
  Future<void> runInherit(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => _handle(executable, arguments);

  @override
  Future<bool> isAvailable(String executable) async => true;

  void _handle(String executable, List<String> arguments) {
    calls.add([executable, ...arguments]);
    if (executable == 'flutter' && arguments.first == 'create') {
      final target = Directory(arguments.last)..createSync(recursive: true);
      copyDirectory(Directory(p.join(fixturesDir, 'fresh_kts')), target);
    }
  }
}
