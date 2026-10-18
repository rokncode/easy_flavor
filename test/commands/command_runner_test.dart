import 'dart:io';

import 'package:easy_flavor/src/version.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../helpers/capture.dart';
import '../helpers/fake_process_runner.dart';
import '../helpers/fixtures.dart';

void main() {
  test('--version', () async {
    final r = await runCli(['--version']);
    expect(r.exitCode, ExitCode.success.code);
    expect(r.stdout.trim(), packageVersion);
  });

  test('version matches pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(packageVersion, pubspec['version']);
  });

  test('--help lists every command', () async {
    final r = await runCli(['--help']);
    expect(r.exitCode, 0);
    for (final c in ['create', 'init', 'add', 'remove', 'doctor']) {
      expect(r.stdout, contains('  $c '));
    }
  });

  test('unknown option is a usage error', () async {
    final r = await runCli(['init', '--nope']);
    expect(r.exitCode, ExitCode.usage.code);
  });

  group('create', () {
    late Directory parent;
    setUp(
      () => parent = Directory.systemTemp.createTempSync('easy_flavor_create_'),
    );
    tearDown(() => parent.deleteSync(recursive: true));

    test('--dry-run with the documented example', () async {
      final r = await runCli([
        'create', 'my_app', '-C', parent.path, '--dry-run', //
        '--org', 'com.company',
        '--flavors', 'dev,staging,prod',
        '--bundle-ids',
        'dev=com.company.myapp.dev,staging=com.company.myapp.stg,prod=com.company.myapp',
        '--app-names', 'dev=MyApp Dev,staging=MyApp Stg,prod=MyApp',
        '--firebase',
        '--firebase-projects',
        'dev=myapp-dev,staging=myapp-stg,prod=myapp-prod',
      ]);
      expect(r.exitCode, 0, reason: r.output);
      expect(
        r.stdout,
        contains('flutter create --org com.company --project-name my_app'),
      );
      expect(r.stdout, contains('MyApp Stg'));
      expect(r.stdout, contains('com.company.myapp.stg'));
      expect(r.stdout, contains('Dry run'));
      expect(r.stdout, contains('run     flutterfire configure --yes'));
      expect(r.stdout, contains('--project=myapp-stg'));
      expect(Directory(p.join(parent.path, 'my_app')).existsSync(), isFalse);
    });

    test(
      'defaults to dev,staging,prod with <org>.<app>.<flavor> ids',
      () async {
        final r = await runCli([
          'create',
          'shop_app',
          '-C',
          parent.path,
          '--dry-run',
        ]);
        expect(r.exitCode, 0, reason: r.output);
        expect(r.stdout, contains('com.example.shopapp.staging'));
        expect(
          r.stdout,
          matches(RegExp(r'prod\s+Shop App\s+com\.example\.shopapp\s')),
        );
      },
    );

    test('runs flutter create and writes the flavor setup', () async {
      final runner = FakeProcessRunner();
      final r = await runCli([
        'create', 'shop_app', '-C', parent.path, '--flavors', 'dev,prod', //
      ], processRunner: runner);
      expect(r.exitCode, 0, reason: r.output);
      final root = p.join(parent.path, 'shop_app');
      expect(
        runner.calls.single,
        containsAllInOrder(['flutter', 'create', '--org']),
      );
      expect(File(p.join(root, 'lib', 'main_dev.dart')).existsSync(), isTrue);
      expect(
        File(p.join(root, 'easy_flavor.yaml')).readAsStringSync(),
        contains('com.example.shopapp.dev'),
      );
      expect(
        r.stdout,
        contains('flutter run --flavor dev -t lib/main_dev.dart'),
      );
    });

    test('validates the project name', () async {
      final r = await runCli([
        'create',
        'My-App',
        '-C',
        parent.path,
        '--dry-run',
      ]);
      expect(r.exitCode, ExitCode.usage.code);
    });

    test('requires a project name', () async {
      final r = await runCli(['create', '-C', parent.path]);
      expect(r.exitCode, ExitCode.usage.code);
    });
  });

  group('init', () {
    late Directory project;
    setUp(() => project = createMinimalFlutterProject());
    tearDown(() => project.deleteSync(recursive: true));

    test('needs flavors when non-interactive', () async {
      final r = await runCli(['init', '-C', project.path]);
      expect(r.exitCode, ExitCode.usage.code);
      expect(r.output, contains('No flavors specified'));
    });

    test('reads flavors from easy_flavor.yaml; flags override it', () async {
      File(p.join(project.path, 'easy_flavor.yaml')).writeAsStringSync(
        'flavors:\n  dev:\n    app_name: Yaml Dev\n  prod:\n    android_id: com.y.app\n',
      );
      final r = await runCli([
        'init',
        '-C',
        project.path,
        '--dry-run',
        '--app-names',
        'prod=Flag Prod', //
      ]);
      expect(r.exitCode, 0, reason: r.output);
      expect(r.stdout, contains('Yaml Dev'));
      expect(r.stdout, contains('Flag Prod'));
      expect(r.stdout, contains('com.y.app'));
    });

    for (final (fixture, id) in [
      ('fresh_kts', 'com.acme.fresh_app'),
      ('groovy', 'com.legacy.legacy_app'),
    ]) {
      test('uses the detected applicationId as prod ($fixture)', () async {
        final dir = copyFixture(fixture);
        final r = await runCli([
          'init',
          '-C',
          dir.path,
          '--flavors',
          'dev,prod',
          '--dry-run',
        ]);
        expect(r.exitCode, 0, reason: r.output);
        expect(
          r.stdout,
          matches(RegExp('prod\\s+\\S.*\\s${RegExp.escape(id)}\\s')),
        );
        expect(r.stdout, contains('$id.dev'));
        expect(
          r.stdout,
          contains('${id.replaceAll('_app', 'App')}.dev'),
          reason: 'iOS id',
        );
        expect(r.stdout, contains('modify  android/app/'));
        expect(r.output, isNot(contains('Could not detect')));
      });
    }

    test('aborts on unmanaged flavors without --merge', () async {
      final dir = copyFixture('existing_flavors');
      final r = await runCli([
        'init',
        '-C',
        dir.path,
        '--flavors',
        'dev,prod',
        '--dry-run',
      ]);
      expect(r.exitCode, isNot(0));
      expect(r.output, contains('already has flavors: dev, prod'));
    });

    test('does not write existing projects yet', () async {
      final dir = copyFixture('fresh_kts');
      final r = await runCli(['init', '-C', dir.path, '--flavors', 'dev,prod']);
      expect(r.exitCode, 0, reason: r.output);
      expect(
        File(p.join(dir.path, 'lib', 'main_dev.dart')).existsSync(),
        isFalse,
      );
    });

    test('fails outside a Flutter project', () async {
      final empty = Directory.systemTemp.createTempSync('easy_flavor_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));
      final r = await runCli(['init', '-C', empty.path, '--flavors', 'dev']);
      expect(r.exitCode, ExitCode.config.code);
    });
  });

  group('add / remove', () {
    late Directory project;
    setUp(() {
      project = createMinimalFlutterProject(
        easyFlavorYaml: '''
flavors:
  dev:
    app_name: App Dev
    android_id: com.a.app.dev
    ios_bundle_id: com.a.app.dev
  prod:
    app_name: App
    android_id: com.a.app
    ios_bundle_id: com.a.app
''',
      );
    });
    tearDown(() => project.deleteSync(recursive: true));

    test('add derives ids from prod', () async {
      final r = await runCli(['add', 'qa', '-C', project.path, '--dry-run']);
      expect(r.exitCode, 0, reason: r.output);
      expect(
        r.stdout,
        matches(RegExp(r'qa\s+App Qa\s+com\.a\.app\.qa\s+com\.a\.app\.qa')),
      );
    });

    test('add rejects an existing flavor', () async {
      final r = await runCli(['add', 'dev', '-C', project.path]);
      expect(r.exitCode, ExitCode.usage.code);
    });

    test('remove rejects an unknown flavor', () async {
      final r = await runCli(['remove', 'qa', '-C', project.path, '-y']);
      expect(r.exitCode, ExitCode.usage.code);
      expect(r.output, contains('dev, prod'));
    });

    test('remove drops the flavor from the plan', () async {
      final r = await runCli([
        'remove',
        'dev',
        '-C',
        project.path,
        '-y',
        '--dry-run',
      ]);
      expect(r.exitCode, 0, reason: r.output);
      expect(r.stdout, isNot(contains('App Dev')));
    });

    test('add without easy_flavor.yaml asks to run init', () async {
      final bare = createMinimalFlutterProject();
      addTearDown(() => bare.deleteSync(recursive: true));
      final r = await runCli(['add', 'qa', '-C', bare.path]);
      expect(r.exitCode, ExitCode.config.code);
      expect(r.output, contains('easy_flavor init'));
    });
  });

  group('doctor', () {
    test('reports a missing easy_flavor.yaml', () async {
      final project = createMinimalFlutterProject();
      addTearDown(() => project.deleteSync(recursive: true));
      final r = await runCli(['doctor', '-C', project.path]);
      expect(r.exitCode, ExitCode.config.code);
      expect(r.output, contains('No easy_flavor.yaml found'));
    });
  });
}
