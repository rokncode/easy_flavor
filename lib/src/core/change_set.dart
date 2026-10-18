import 'dart:io';

import 'package:path/path.dart' as p;

import 'process_runner.dart';

enum ChangeKind { create, modify, delete }

/// A single planned filesystem change, relative to the project root.
class FileChange {
  FileChange({
    required this.path,
    required this.kind,
    this.before,
    this.after,
    this.reason,
  });

  final String path;
  final ChangeKind kind;
  final String? before;
  final String? after;

  /// Short human-readable explanation shown in dry-run output.
  final String? reason;
}

/// An external tool run after the files are written (e.g. `flutterfire
/// configure`).
class ExternalCommand {
  ExternalCommand(
    this.executable,
    this.arguments, {
    required this.reason,
    this.preserve = const [],
    this.mayModify = const [],
  });

  final String executable;
  final List<String> arguments;
  final String reason;

  /// Files the tool modifies that easy_flavor manages itself; they are
  /// restored to their planned content after the command runs.
  final List<String> preserve;

  /// Other files the tool may create or change; they are backed up before
  /// it runs.
  final List<String> mayModify;

  String get display => [executable, ...arguments.map(_shellQuote)].join(' ');

  static String _shellQuote(String s) => RegExp(r'^[\w@%+=:,./-]+$').hasMatch(s)
      ? s
      : "'${s.replaceAll("'", r"'\''")}'";
}

/// Collects every change a command intends to make so it can be previewed
/// (`--dry-run`), backed up, and then written in one pass.
///
/// Generators never write to disk directly; they read the current content
/// (which reflects earlier planned changes) and record the new content here.
/// A write whose content is unchanged is dropped, which is what makes running
/// the same command twice a no-op.
class ChangeSet {
  ChangeSet(this.root);

  final String root;
  final _changes = <String, FileChange>{};
  final _commands = <ExternalCommand>[];

  List<FileChange> get changes => List.unmodifiable(_changes.values);

  List<ExternalCommand> get commands => List.unmodifiable(_commands);

  bool get isEmpty => _changes.isEmpty && _commands.isEmpty;

  void run(ExternalCommand command) => _commands.add(command);

  /// Current content of [relativePath], taking planned changes into account.
  String? read(String relativePath) {
    final key = p.normalize(relativePath);
    final planned = _changes[key];
    if (planned != null) return planned.after;
    final f = File(p.join(root, key));
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  void write(String relativePath, String content, {String? reason}) {
    final key = p.normalize(relativePath);
    final original = _original(key);
    if (original == content) {
      _changes.remove(key);
      return;
    }
    _changes[key] = FileChange(
      path: key,
      kind: original == null ? ChangeKind.create : ChangeKind.modify,
      before: original,
      after: content,
      reason: reason,
    );
  }

  void delete(String relativePath, {String? reason}) {
    final key = p.normalize(relativePath);
    final original = _original(key);
    if (original == null) {
      _changes.remove(key);
      return;
    }
    _changes[key] = FileChange(
      path: key,
      kind: ChangeKind.delete,
      before: original,
      reason: reason,
    );
  }

  String? _original(String key) {
    final f = File(p.join(root, key));
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  /// Writes every change, then runs the commands in order.
  Future<void> applyAll(ProcessRunner runner) async {
    apply();
    for (final command in _commands) {
      final snapshot = {for (final path in command.preserve) path: read(path)};
      await runner.runInherit(
        command.executable,
        command.arguments,
        workingDirectory: root,
      );
      snapshot.forEach((path, content) {
        final file = File(p.join(root, path));
        if (content == null) {
          if (file.existsSync()) file.deleteSync();
        } else if (!file.existsSync() || file.readAsStringSync() != content) {
          file.writeAsStringSync(content);
        }
      });
    }
  }

  /// Writes every file change to disk (commands are not run). Directories
  /// emptied by deletions are removed, up to (not including) [root].
  void apply() {
    for (final c in _changes.values) {
      final file = File(p.join(root, c.path));
      if (c.kind == ChangeKind.delete) {
        if (file.existsSync()) file.deleteSync();
        _removeEmptyParents(file.parent);
      } else {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(c.after!);
      }
    }
  }

  void _removeEmptyParents(Directory dir) {
    final rootPath = p.normalize(p.absolute(root));
    var current = dir;
    while (p.isWithin(rootPath, p.normalize(p.absolute(current.path))) &&
        current.existsSync() &&
        current.listSync().isEmpty) {
      current.deleteSync();
      current = current.parent;
    }
  }
}
