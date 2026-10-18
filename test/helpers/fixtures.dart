import 'dart:io';

import 'package:easy_flavor/easy_flavor.dart';
import 'package:easy_flavor/src/core/change_set.dart';
import 'package:easy_flavor/src/core/generator.dart';
import 'package:easy_flavor/src/core/pipeline.dart';
import 'package:easy_flavor/src/core/process_runner.dart';
import 'package:easy_flavor/src/core/project_context.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_process_runner.dart';

/// Fixture projects in test/fixtures:
/// * fresh_kts: files from `flutter create` (Flutter 3.44, Kotlin DSL).
/// * groovy: the older Groovy-DSL template.
/// * existing_flavors: Groovy with hand-written productFlavors and an
///   app_name already defined in main/res/values/strings.xml.
final fixturesDir = p.join(Directory.current.path, 'test', 'fixtures');

/// Copies fixture [name] to a temp dir that is deleted after the test.
Directory copyFixture(String name) {
  final target = Directory.systemTemp.createTempSync('easy_flavor_$name');
  addTearDown(() => target.deleteSync(recursive: true));
  copyDirectory(Directory(p.join(fixturesDir, name)), target);
  return target;
}

void copyDirectory(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    final rel = p.relative(entity.path, from: from.path);
    if (entity is File) {
      final dest = File(p.join(to.path, rel));
      dest.parent.createSync(recursive: true);
      entity.copySync(dest.path);
    }
  }
}

ProjectContext contextFor(Directory dir, {ProcessRunner? processRunner}) =>
    ProjectContext(
      root: dir.path,
      logger: Logger(level: Level.quiet),
      processRunner: processRunner ?? FakeProcessRunner(),
    );

/// Plans [generators] for [config] in [dir].
Future<ChangeSet> plan(
  Directory dir,
  EasyFlavorConfig config, {
  EasyFlavorConfig? previous,
  List<Generator> generators = defaultGenerators,
  ProcessRunner? processRunner,
}) => planChanges(
  context: contextFor(dir, processRunner: processRunner),
  config: config,
  previous: previous,
  generators: generators,
);

/// Plans and applies, then checks a second run is a no-op.
Future<ChangeSet> applyAndExpectIdempotent(
  Directory dir,
  EasyFlavorConfig config, {
  EasyFlavorConfig? previous,
  List<Generator> generators = defaultGenerators,
}) async {
  final changes = await plan(
    dir,
    config,
    previous: previous,
    generators: generators,
  );
  changes.apply();
  final again = await plan(
    dir,
    config,
    previous: config,
    generators: generators,
  );
  expect(
    again.changes.map((c) => c.path),
    isEmpty,
    reason: 'second run must not change anything',
  );
  return changes;
}

String read(Directory dir, String relative) =>
    File(p.join(dir.path, relative)).readAsStringSync();

bool exists(Directory dir, String relative) =>
    FileSystemEntity.typeSync(p.join(dir.path, relative)) !=
    FileSystemEntityType.notFound;

EasyFlavorConfig configOf(
  List<String> flavors, {
  String base = 'com.acme.app',
  String appName = 'App',
  List<IdeTarget> ide = IdeTarget.values,
}) => EasyFlavorConfig(
  flavors: [
    for (final f in flavors)
      FlavorSpec(
        name: f,
        appName: f == 'prod' ? appName : '$appName ${f.toUpperCase()}',
        androidId: f == 'prod' ? base : '$base.$f',
        iosBundleId: f == 'prod' ? base : '$base.$f',
      ),
  ],
  ide: ide,
);

/// Creates a minimal Flutter project in a temp dir (pubspec + main.dart).
Directory createMinimalFlutterProject({
  String name = 'my_app',
  String? easyFlavorYaml,
}) {
  final dir = Directory.systemTemp.createTempSync('easy_flavor_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
environment:
  sdk: ^3.8.0
dependencies:
  flutter:
    sdk: flutter
''');
  File(p.join(dir.path, 'lib', 'main.dart'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('void main() {}\n');
  if (easyFlavorYaml != null) {
    File(
      p.join(dir.path, 'easy_flavor.yaml'),
    ).writeAsStringSync(easyFlavorYaml);
  }
  return dir;
}

/// [config] with Firebase on and project `<flavor>-proj` for each flavor.
EasyFlavorConfig withFirebase(EasyFlavorConfig config) => config.copyWith(
  firebase: true,
  flavors: [
    for (final f in config.flavors)
      f.copyWith(firebaseProjectId: '${f.name}-proj'),
  ],
);
