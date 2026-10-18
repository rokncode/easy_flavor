import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../version.dart';
import 'change_set.dart';
import 'exceptions.dart';

const backupDirName = '.easy_flavor_backup';
const _manifestName = 'manifest.json';

/// How a file looked before a run: it existed (and is copied in the backup)
/// or it did not (and restoring deletes it).
enum BackupEntry { existed, absent }

/// A snapshot of every file a run is about to touch, stored in
/// `.easy_flavor_backup/<timestamp>/`.
class Backup {
  Backup._(this.dir, this.entries);

  final Directory dir;
  final Map<String, BackupEntry> entries;

  String get id => p.basename(dir.path);

  /// Backs up the files [changes] will write or delete, plus [extra] files
  /// that its commands may modify. Returns null if there is nothing to back
  /// up.
  static Backup? create(
    String root,
    ChangeSet changes, {
    Iterable<String> extra = const [],
    DateTime? now,
  }) {
    final paths = <String>{
      for (final c in changes.changes) c.path,
      for (final c in changes.commands) ...c.preserve,
      for (final c in changes.commands) ...c.mayModify,
      ...extra,
    };
    if (paths.isEmpty) return null;

    final base = Directory(p.join(root, backupDirName));
    final name = _timestamp(now ?? DateTime.now());
    var dir = Directory(p.join(base.path, name));
    for (var i = 2; dir.existsSync(); i++) {
      dir = Directory(p.join(base.path, '$name-$i'));
    }
    final entries = <String, BackupEntry>{};
    for (final path in paths.toList()..sort()) {
      final source = File(p.join(root, path));
      if (source.existsSync()) {
        final target = File(p.join(dir.path, 'files', path));
        target.parent.createSync(recursive: true);
        source.copySync(target.path);
        entries[path] = BackupEntry.existed;
      } else {
        entries[path] = BackupEntry.absent;
      }
    }
    dir.createSync(recursive: true);
    File(p.join(dir.path, _manifestName)).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'easy_flavor': packageVersion,
        'created': (now ?? DateTime.now()).toIso8601String(),
        'files': {for (final e in entries.entries) e.key: e.value.name},
      }),
    );
    return Backup._(dir, entries);
  }

  /// Backups in [root], oldest first.
  static List<Backup> list(String root) {
    final base = Directory(p.join(root, backupDirName));
    if (!base.existsSync()) return const [];
    final backups = <Backup>[];
    for (final dir in base.listSync().whereType<Directory>()) {
      final manifest = File(p.join(dir.path, _manifestName));
      if (!manifest.existsSync()) continue;
      final json =
          jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
      final files = (json['files'] as Map?)?.cast<String, String>() ?? const {};
      backups.add(
        Backup._(dir, {
          for (final e in files.entries)
            e.key: BackupEntry.values.byName(e.value),
        }),
      );
    }
    return backups..sort((a, b) => a.id.compareTo(b.id));
  }

  static Backup find(String root, String? id) {
    final all = list(root);
    if (all.isEmpty) {
      throw ProjectError('No backups found in $backupDirName/.');
    }
    if (id == null) return all.last;
    return all.firstWhere(
      (b) => b.id == id,
      orElse: () => throw UsageError(
        'No backup "$id".',
        hint: 'Available: ${all.map((b) => b.id).join(', ')}',
      ),
    );
  }

  /// Puts every file back the way it was before the run.
  void restore(String root) {
    entries.forEach((path, entry) {
      final file = File(p.join(root, path));
      switch (entry) {
        case BackupEntry.existed:
          file.parent.createSync(recursive: true);
          File(p.join(dir.path, 'files', path)).copySync(file.path);
        case BackupEntry.absent:
          if (file.existsSync()) file.deleteSync();
      }
    });
  }

  static String _timestamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
