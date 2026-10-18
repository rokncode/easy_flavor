import 'dart:io';

import 'package:easy_flavor/src/core/change_set.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ChangeSet changes;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('change_set_test_');
    File(p.join(dir.path, 'a.txt')).writeAsStringSync('original');
    changes = ChangeSet(dir.path);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('records creates and modifications', () {
    changes
      ..write('a.txt', 'changed')
      ..write('lib/new.dart', 'new');
    expect(
      {for (final c in changes.changes) c.path: c.kind},
      {
        'a.txt': ChangeKind.modify,
        p.join('lib', 'new.dart'): ChangeKind.create,
      },
    );
    expect(changes.changes.first.before, 'original');
  });

  test('read sees planned content', () {
    changes.write('a.txt', 'changed');
    expect(changes.read('a.txt'), 'changed');
    expect(changes.read('./a.txt'), 'changed', reason: 'paths are normalized');
    expect(changes.read('missing.txt'), isNull);
  });

  test('writing the original content back drops the change (idempotency)', () {
    changes.write('a.txt', 'original');
    expect(changes.isEmpty, isTrue);
    changes
      ..write('a.txt', 'x')
      ..write('a.txt', 'original');
    expect(changes.isEmpty, isTrue);
  });

  test('delete', () {
    changes.delete('a.txt');
    expect(changes.changes.single.kind, ChangeKind.delete);
    expect(changes.read('a.txt'), isNull);
    changes.delete('missing.txt');
    expect(changes.changes, hasLength(1));
  });

  test('nothing touches the disk', () {
    changes
      ..write('a.txt', 'changed')
      ..write('b.txt', 'b');
    expect(File(p.join(dir.path, 'a.txt')).readAsStringSync(), 'original');
    expect(File(p.join(dir.path, 'b.txt')).existsSync(), isFalse);
  });
}
