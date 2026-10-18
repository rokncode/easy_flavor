import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Everything a generator needs to know about where and how it runs.
class ProjectContext {
  ProjectContext({
    required this.root,
    required this.logger,
    this.dryRun = false,
    this.interactive = true,
  });

  /// Absolute path to the Flutter project root (the folder with pubspec.yaml).
  final String root;
  final Logger logger;
  final bool dryRun;

  /// Whether prompts may be shown. False on CI or with `--no-interactive`.
  final bool interactive;

  String path(String relative) => p.join(root, relative);

  File file(String relative) => File(path(relative));

  Directory dir(String relative) => Directory(path(relative));

  bool exists(String relative) =>
      FileSystemEntity.typeSync(path(relative)) !=
      FileSystemEntityType.notFound;

  String? readOrNull(String relative) {
    final f = file(relative);
    return f.existsSync() ? f.readAsStringSync() : null;
  }
}
