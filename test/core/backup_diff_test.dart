import 'dart:io';

import 'package:easy_flavor/src/core/backup.dart';
import 'package:easy_flavor/src/core/change_set.dart';
import 'package:easy_flavor/src/core/diff.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Backup', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('backup_test_');
      File(p.join(dir.path, 'a.txt')).writeAsStringSync('A');
      File(p.join(dir.path, 'gone.txt')).writeAsStringSync('G');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('restores modified, deleted and created files', () async {
      final changes = ChangeSet(dir.path)
        ..write('a.txt', 'A2')
        ..write('new/b.txt', 'B')
        ..delete('gone.txt')
        ..run(
          ExternalCommand('tool', [], reason: 'x', mayModify: ['tool-out.txt']),
        );
      final t = DateTime(2026, 1, 2, 3, 4, 5);
      final backup = Backup.create(dir.path, changes, now: t)!;
      expect(backup.id, '20260102-030405');
      changes.apply();
      File(p.join(dir.path, 'tool-out.txt')).writeAsStringSync('T');

      Backup.find(dir.path, null).restore(dir.path);
      expect(File(p.join(dir.path, 'a.txt')).readAsStringSync(), 'A');
      expect(File(p.join(dir.path, 'gone.txt')).readAsStringSync(), 'G');
      expect(File(p.join(dir.path, 'new/b.txt')).existsSync(), isFalse);
      expect(File(p.join(dir.path, 'tool-out.txt')).existsSync(), isFalse);

      final second = Backup.create(dir.path, changes, now: t)!;
      expect(second.id, '20260102-030405-2', reason: 'no collision');
      expect(Backup.list(dir.path).map((b) => b.id), [
        '20260102-030405',
        '20260102-030405-2',
      ]);
    });

    test('nothing to back up', () {
      expect(Backup.create(dir.path, ChangeSet(dir.path)), isNull);
    });
  });

  test('unifiedDiff', () {
    overrideAnsiOutput(false, () {
      final before = [for (var i = 1; i <= 20; i++) 'line $i'].join('\n');
      final after = before
          .replaceFirst('line 10', 'line ten')
          .replaceFirst('line 20', 'line 20\nline 21');
      expect(unifiedDiff(before, after, path: 'f.txt'), '''
--- a/f.txt
+++ b/f.txt
@@ -7,7 +7,7 @@
 line 7
 line 8
 line 9
-line 10
+line ten
 line 11
 line 12
 line 13
@@ -18,3 +18,4 @@
 line 18
 line 19
 line 20
+line 21''');
      expect(unifiedDiff('', 'x', path: 'n'), endsWith('@@ -1,0 +1,1 @@\n+x'));
    });
  });
}
