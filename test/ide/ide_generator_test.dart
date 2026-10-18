import 'dart:convert';
import 'dart:io';

import 'package:easy_flavor/easy_flavor.dart';
import 'package:easy_flavor/src/ide/ide_generator.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  const ide = [IdeGenerator()];

  List<Object?> launchConfigs(Directory dir) =>
      (jsonDecode(read(dir, launchJsonFile)) as Map)['configurations']
          as List<Object?>;

  test('creates VS Code and Android Studio configs', () async {
    final dir = copyFixture('fresh_kts');
    await applyAndExpectIdempotent(
      dir,
      configOf(['dev', 'prod']),
      generators: ide,
    );
    expect(launchConfigs(dir), [
      {
        'name': 'dev',
        'request': 'launch',
        'type': 'dart',
        'program': 'lib/main_dev.dart',
        'args': ['--flavor', 'dev'],
      },
      {
        'name': 'prod',
        'request': 'launch',
        'type': 'dart',
        'program': 'lib/main_prod.dart',
        'args': ['--flavor', 'prod'],
      },
    ]);
    expect(
      read(dir, '.run/dev.run.xml'),
      contains(r'value="$PROJECT_DIR$/lib/main_dev.dart"'),
    );
  });

  test(
    'merges with user launch configs (JSONC) and removes stale flavors',
    () async {
      final dir = copyFixture('fresh_kts');
      File('${dir.path}/$launchJsonFile')
        ..parent.createSync()
        ..writeAsStringSync('''
{
  // my config
  "version": "0.2.0",
  "configurations": [
    {"name": "mine", "request": "launch", "type": "dart", "program": "lib/main.dart"},
  ]
}
''');
      final before = configOf(['dev', 'prod']);
      final changes = await applyAndExpectIdempotent(
        dir,
        before,
        generators: ide,
      );
      expect(
        changes.changes.firstWhere((c) => c.path == launchJsonFile).reason,
        contains('comments removed'),
      );
      expect(launchConfigs(dir).map((c) => (c as Map)['name']), [
        'mine',
        'dev',
        'prod',
      ]);

      await applyAndExpectIdempotent(
        dir,
        configOf(['prod']),
        previous: before,
        generators: ide,
      );
      expect(launchConfigs(dir).map((c) => (c as Map)['name']), [
        'mine',
        'prod',
      ]);
      expect(exists(dir, '.run/dev.run.xml'), isFalse);
    },
  );

  test('respects the ide setting', () async {
    final dir = copyFixture('fresh_kts');
    await applyAndExpectIdempotent(
      dir,
      configOf(['dev'], ide: [IdeTarget.androidStudio]),
      generators: ide,
    );
    expect(exists(dir, launchJsonFile), isFalse);
    expect(exists(dir, '.run/dev.run.xml'), isTrue);

    await applyAndExpectIdempotent(
      dir,
      configOf(['dev'], ide: const []),
      generators: ide,
    );
    expect(exists(dir, '.run'), isFalse);
  });

  test('leaves unrelated run configs alone', () async {
    final dir = copyFixture('fresh_kts');
    File('${dir.path}/.run/dev.run.xml')
      ..parent.createSync()
      ..writeAsStringSync('<component>custom</component>');
    await applyAndExpectIdempotent(dir, configOf(['dev']), generators: ide);
    expect(read(dir, '.run/dev.run.xml'), '<component>custom</component>');
  });

  test('parseJsonc', () {
    final parsed = parseJsonc('{"a": "// not a comment", /* c */ "b": [1,],}')!;
    expect(parsed.$1, {
      'a': '// not a comment',
      'b': [1],
    });
    expect(parsed.$2, isTrue);
    expect(parseJsonc('{nope'), isNull);
  });
}
