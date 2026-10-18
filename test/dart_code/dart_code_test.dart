import 'dart:io';

import 'package:easy_flavor/src/core/exceptions.dart';
import 'package:easy_flavor/src/dart_code/dart_code_generator.dart';
import 'package:easy_flavor/src/dart_code/main_dart.dart';
import 'package:easy_flavor/src/dart_code/pubspec_editor.dart';
import 'package:easy_flavor/src/dart_code/templates.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  const dart = [DartCodeGenerator()];

  group('refactorMainDart', () {
    test('fresh template', () {
      final r = refactorMainDart(
        "import 'package:flutter/material.dart';\n\nvoid main() {\n  runApp(const MyApp());\n}\n",
        'prod',
      );
      expect(r.runMainAppReturnsFuture, isFalse);
      expect(r.source, '''
import 'package:flutter/material.dart';
import 'flavors.dart';

void main() {
  FlavorConfig.init(Flavor.prod); $defaultFlavorMarker
  runMainApp();
}

void runMainApp() {
  runApp(const MyApp());
}
''');
    });

    test('async main with doc comments and annotations', () {
      final r = refactorMainDart(
        '/// Starts the app.\n@pragma("vm:entry-point")\nFuture<void> main() async {\n  await init();\n}\n',
        'dev',
      );
      expect(r.runMainAppReturnsFuture, isTrue);
      expect(
        r.source,
        startsWith("import 'flavors.dart';\n\nFuture<void> main() async {"),
      );
      expect(
        r.source,
        contains('  await runMainApp();\n}\n\n/// Starts the app.\n@pragma'),
      );
      expect(r.source, contains('Future<void> runMainApp() async {'));
    });

    test('expression body and no return type', () {
      expect(
        refactorMainDart('main() => run();\n', 'dev').source,
        contains('runMainApp() => run();'),
      );
    });

    test('only updates the default flavor on later runs', () {
      final once = refactorMainDart('void main() {}\n', 'prod').source;
      final twice = refactorMainDart(once, 'prod').source;
      expect(twice, once);
      final changed = refactorMainDart(once, 'dev').source;
      expect(
        changed,
        contains('FlavorConfig.init(Flavor.dev); $defaultFlavorMarker'),
      );
      expect('runMainApp('.allMatches(changed), hasLength(2));
    });

    test('leaves a hand-written runMainApp alone', () {
      const src = 'void main() => runMainApp();\nvoid runMainApp() {}\n';
      expect(refactorMainDart(src, 'prod').source, src);
    });

    test('does not mistake an indented main() call for a declaration', () {
      const src = 'void start() {\n  main();\n}\n';
      expect(() => refactorMainDart(src, 'prod'), throwsA(isA<ProjectError>()));
    });

    test('rejects main with parameters', () {
      expect(
        () => refactorMainDart('void main(List<String> args) {}\n', 'prod'),
        throwsA(isA<ProjectError>()),
      );
    });
  });

  group('flavors.dart', () {
    test('keeps edited baseUrl lines and drops removed flavors', () {
      final first = renderFlavorsDart(configOf(['dev', 'prod']));
      final edited = first.replaceFirst(
        "baseUrl: 'https://api.dev.example.com',",
        "baseUrl: 'https://dev.internal' /* mine */,",
      );
      final urls = readBaseUrls(edited);
      expect(urls['dev'], "'https://dev.internal' /* mine */");
      final second = renderFlavorsDart(
        configOf(['dev', 'qa', 'prod']),
        baseUrls: urls,
      );
      expect(second, contains("baseUrl: 'https://dev.internal' /* mine */,"));
      expect(second, contains("baseUrl: 'https://api.qa.example.com',"));
      expect(second, contains('enum Flavor { dev, qa, prod }'));
    });

    test('escapes app titles', () {
      expect(dartString(r"Bob's $5 \ x"), r"'Bob\'s \$5 \\ x'");
    });
  });

  group('pubspec default-flavor', () {
    test('adds, updates and keeps comments', () {
      const src =
          'name: a\n# keep me\nflutter:\n  uses-material-design: true\n';
      final out = withDefaultFlavor(src, 'prod');
      expect(out, contains('# keep me'));
      expect(readDefaultFlavor(out), 'prod');
      expect(withDefaultFlavor(out, 'prod'), out);
      expect(readDefaultFlavor(withDefaultFlavor(out, 'dev')), 'dev');
    });

    test('creates the flutter section if missing', () {
      expect(readDefaultFlavor(withDefaultFlavor('name: a\n', 'dev')), 'dev');
    });
  });

  group('generator on fresh_kts', () {
    test(
      'generates entry points, is idempotent, and removes flavors',
      () async {
        final dir = copyFixture('fresh_kts');
        final three = configOf(['dev', 'staging', 'prod']);
        await applyAndExpectIdempotent(dir, three, generators: dart);
        for (final f in ['dev', 'staging', 'prod']) {
          expect(
            read(dir, 'lib/main_$f.dart'),
            contains('FlavorConfig.init(Flavor.$f);'),
          );
        }
        expect(read(dir, 'lib/main.dart'), contains('void runMainApp() {'));
        expect(readDefaultFlavor(read(dir, 'pubspec.yaml')), 'prod');

        // A user file named like an entry point is never deleted.
        File(
          '${dir.path}/lib/main_custom.dart',
        ).writeAsStringSync('void main() {}\n');
        final two = configOf(['dev', 'staging']);
        await applyAndExpectIdempotent(
          dir,
          two,
          previous: three,
          generators: dart,
        );
        expect(exists(dir, 'lib/main_prod.dart'), isFalse);
        expect(exists(dir, 'lib/main_custom.dart'), isTrue);
        expect(readDefaultFlavor(read(dir, 'pubspec.yaml')), 'dev');
        expect(
          read(dir, 'lib/main.dart'),
          contains('FlavorConfig.init(Flavor.dev);'),
        );
      },
    );

    test('refuses to overwrite a hand-written lib/flavors.dart', () async {
      final dir = copyFixture('fresh_kts');
      File(
        '${dir.path}/lib/flavors.dart',
      ).writeAsStringSync('enum Flavor { a }\n');
      expect(
        () => plan(dir, configOf(['dev']), generators: dart),
        throwsA(isA<ProjectError>()),
      );
    });

    test('generated Dart is already dart-format clean', () async {
      final dir = copyFixture('fresh_kts');
      await applyAndExpectIdempotent(
        dir,
        configOf(['dev', 'prod']),
        generators: dart,
      );
      final result = await Process.run(Platform.resolvedExecutable, [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        '--language-version=3.8',
        'lib/flavors.dart',
        'lib/main_dev.dart',
        'lib/main_prod.dart',
      ], workingDirectory: dir.path);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });
  });
}
