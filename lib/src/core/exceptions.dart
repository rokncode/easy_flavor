import 'package:mason_logger/mason_logger.dart';

/// An expected, user-facing failure. The CLI prints [message] (and [hint] if
/// present) without a stack trace and exits with [exitCode].
class EasyFlavorException implements Exception {
  EasyFlavorException(
    this.message, {
    this.hint,
    this.exitCode = ExitCode.software,
  });

  final String message;
  final String? hint;
  final ExitCode exitCode;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}

/// Invalid flags or config values.
class UsageError extends EasyFlavorException {
  UsageError(super.message, {super.hint}) : super(exitCode: ExitCode.usage);
}

/// The working directory is not something we can operate on.
class ProjectError extends EasyFlavorException {
  ProjectError(super.message, {super.hint}) : super(exitCode: ExitCode.config);
}

/// A required external tool (flutter, flutterfire, firebase, ruby, ...) is
/// missing or failed.
class ToolError extends EasyFlavorException {
  ToolError(super.message, {super.hint})
    : super(exitCode: ExitCode.unavailable);
}
