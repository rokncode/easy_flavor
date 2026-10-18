import 'dart:io';

import 'exceptions.dart';

/// Thin wrapper over [Process] so commands can be tested with a fake.
class ProcessRunner {
  const ProcessRunner();

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    try {
      return await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (e) {
      throw ToolError(
        'Could not run "$executable": ${e.message}',
        hint: 'Make sure $executable is installed and on your PATH.',
      );
    }
  }

  /// Like [run], streaming output to the terminal; throws on non-zero exit.
  Future<void> runInherit(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.inheritStdio,
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (e) {
      throw ToolError(
        'Could not run "$executable": ${e.message}',
        hint: 'Make sure $executable is installed and on your PATH.',
      );
    }
    final code = await process.exitCode;
    if (code != 0) {
      throw ToolError(
        '"$executable ${arguments.join(' ')}" failed with exit code $code.',
      );
    }
  }

  /// Whether [executable] resolves on PATH.
  Future<bool> isAvailable(String executable) async {
    final result = await run(Platform.isWindows ? 'where' : 'which', [
      executable,
    ]).catchError((_) => ProcessResult(0, 1, '', ''));
    return result.exitCode == 0;
  }
}
