import 'dart:convert';
import 'dart:io';

import 'package:easy_flavor/easy_flavor.dart';
import 'package:easy_flavor/src/core/process_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import 'fake_process_runner.dart';

/// Result of running the CLI in-process.
class RunResult {
  RunResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  String get output => '$stdout$stderr';
}

/// Runs `easy_flavor [args]` in-process with captured, colorless output and
/// prompts disabled.
Future<RunResult> runCli(
  List<String> args, {
  ProcessRunner? processRunner,
}) async {
  final out = _FakeStdout();
  final err = _FakeStdout();
  late int code;
  await IOOverrides.runZoned(
    () => overrideAnsiOutput(false, () async {
      code = await EasyFlavorCommandRunner(
        logger: Logger(),
        processRunner: processRunner ?? FakeProcessRunner(),
      ).run(['--no-interactive', ...args]);
    }),
    stdout: () => out,
    stderr: () => err,
  );
  return RunResult(code, out.text, err.text);
}

class _FakeStdout implements Stdout {
  final _buffer = StringBuffer();

  String get text => _buffer.toString();

  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
