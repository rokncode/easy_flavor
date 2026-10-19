import 'dart:io';

import 'package:easy_flavor/src/core/exceptions.dart';
import 'package:easy_flavor/src/core/generator.dart';
import 'package:easy_flavor/src/dart_code/dart_code_generator.dart';
import 'package:easy_flavor/src/firebase/firebase_generator.dart';
import 'package:easy_flavor/src/ios/ios_generator.dart';
import 'package:easy_flavor/src/ios/xcode_project.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/fake_process_runner.dart';
import '../helpers/fixtures.dart';

void main() {
  const generators = <Generator>[
    DartCodeGenerator(),
    IosGenerator(),
    FirebaseGenerator(environment: {}),
  ];

  /// Writes what `flutterfire configure` would produce for [flavors].
  void fakeFlutterfireOutputs(Directory dir, List<String> flavors) {
    for (final f in flavors) {
      for (final path in [
        'lib/firebase/firebase_options_$f.dart',
        googleServicesJsonPath(f),
        googleServiceInfoPlistPath(f),
      ]) {
        File(p.join(dir.path, path))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('// $f');
      }
    }
  }

  test(
    'plans flutterfire per flavor, firebase_core, and the iOS copy phase',
    () async {
      final dir = copyFixture('fresh_kts');
      final config = withFirebase(configOf(['dev', 'prod']));
      final changes = await plan(dir, config, generators: generators);

      final commands = changes.commands.map((c) => c.display).toList();
      expect(commands.first, 'flutter pub add firebase_core');
      expect(commands, hasLength(3));
      final dev = changes.commands[1];
      expect(dev.arguments, [
        'configure',
        '--yes',
        '--overwrite-firebase-options',
        '--project=dev-proj',
        '--out=lib/firebase/firebase_options_dev.dart',
        '--platforms=android,ios',
        '--android-package-name=com.acme.app.dev',
        '--android-out=android/app/src/dev/google-services.json',
        '--ios-bundle-id=com.acme.app.dev',
        '--ios-out=ios/config/dev/GoogleService-Info.plist',
        '--ios-build-config=Release-dev',
      ]);
      expect(dev.preserve, [pbxprojFile]);

      final xcode = XcodeProject.parse(changes.read(pbxprojFile)!);
      final phases = (xcode.appTarget.object['buildPhases']! as List)
          .cast<String>();
      final copy = xcode.scriptPhaseNamed(copyPlistPhaseName)!;
      expect(
        xcode.pbx.object(phases[phases.indexOf(copy) - 1])!['isa'],
        'PBXResourcesBuildPhase',
        reason: 'runs right after Resources',
      );
      expect(
        changes.read('lib/main_dev.dart'),
        contains('Firebase.initializeApp('),
      );
    },
  );

  test('is idempotent once flutterfire outputs exist', () async {
    final dir = copyFixture('fresh_kts');
    final config = withFirebase(configOf(['dev', 'prod']));
    (await plan(dir, config, generators: generators)).apply();
    fakeFlutterfireOutputs(dir, ['dev', 'prod']);
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
      read(dir, 'pubspec.yaml').replaceFirst(
        'dependencies:\n',
        'dependencies:\n  firebase_core: ^4.0.0\n',
      ),
    );

    final again = await plan(
      dir,
      config,
      previous: config,
      generators: generators,
    );
    expect(again.changes.map((c) => c.path), isEmpty);
    expect(again.commands, isEmpty);

    // Changing a flavor's project re-runs flutterfire for that flavor only.
    final moved = config.copyWith(
      flavors: [
        config.flavors.first.copyWith(firebaseProjectId: 'other'),
        config.flavors.last,
      ],
    );
    final rerun = await plan(
      dir,
      moved,
      previous: config,
      generators: generators,
    );
    expect(rerun.commands.single.arguments, contains('--project=other'));
  });

  test(
    'turning Firebase off removes the copy phase and Firebase init',
    () async {
      final dir = copyFixture('fresh_kts');
      final on = withFirebase(configOf(['dev']));
      (await plan(dir, on, generators: generators)).apply();
      final off = on.copyWith(firebase: false);
      final changes = await plan(
        dir,
        off,
        previous: on,
        generators: generators,
      );
      changes.apply();
      expect(
        XcodeProject.parse(
          read(dir, pbxprojFile),
        ).scriptPhaseNamed(copyPlistPhaseName),
        isNull,
      );
      expect(read(dir, 'lib/main_dev.dart'), isNot(contains('Firebase')));
      expect(changes.commands, isEmpty);
    },
  );

  test('requires a project per flavor', () {
    final dir = copyFixture('fresh_kts');
    final config = withFirebase(configOf(['dev', 'prod']));
    final partial = config.copyWith(
      flavors: [
        config.flavors.first,
        configOf(['prod']).flavors.single,
      ],
    );
    expect(
      () => plan(dir, partial, generators: generators),
      throwsA(
        isA<UsageError>().having((e) => e.message, 'message', contains('prod')),
      ),
    );
  });

  group('tool checks', () {
    final config = withFirebase(configOf(['dev']));

    test('missing CLIs stop with install instructions', () {
      final dir = copyFixture('fresh_kts');
      expect(
        () => plan(
          dir,
          config,
          generators: generators,
          processRunner: FakeProcessRunner(
            missing: {'flutterfire', 'firebase'},
          ),
        ),
        throwsA(
          isA<ToolError>().having(
            (e) => e.hint,
            'hint',
            allOf(
              contains('dart pub global activate flutterfire_cli'),
              contains('firebase-tools'),
            ),
          ),
        ),
      );
    });

    test('not logged in', () {
      final dir = copyFixture('fresh_kts');
      expect(
        () => plan(
          dir,
          config,
          generators: generators,
          processRunner: FakeProcessRunner(loggedIn: false),
        ),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('not logged in'),
          ),
        ),
      );
    });

    test('CI credentials skip the login check and are passed on', () async {
      final dir = copyFixture('fresh_kts');
      final changes = await plan(
        dir,
        config,
        processRunner: FakeProcessRunner(loggedIn: false),
        generators: const [
          DartCodeGenerator(),
          IosGenerator(),
          FirebaseGenerator(environment: {'FIREBASE_TOKEN': 'tok'}),
        ],
      );
      expect(changes.commands.last.arguments, contains('--token=tok'));
    });
  });

  test(
    'applyAll restores preserved files after a command edits them',
    () async {
      final dir = copyFixture('fresh_kts');
      final config = withFirebase(configOf(['dev']));
      final changes = await plan(dir, config, generators: generators);
      final planned = changes.read(pbxprojFile);
      final runner = FakeProcessRunner(
        onRun: (exe, args, cwd) {
          if (exe == 'flutterfire') {
            File(
              p.join(cwd!, pbxprojFile),
            ).writeAsStringSync('// edited by ruby');
          }
        },
      );
      await changes.applyAll(runner);
      expect(read(dir, pbxprojFile), planned);
      expect(runner.calls.where((c) => c.first == 'flutterfire'), hasLength(1));
    },
  );

  test(
    'doctor reports missing Firebase files, then nothing once present',
    () async {
      final dir = copyFixture('fresh_kts');
      final config = withFirebase(configOf(['dev']));
      (await plan(dir, config, generators: generators)).apply();
      const firebase = FirebaseGenerator(environment: {});
      final before = firebase
          .check(contextFor(dir), config)
          .map((i) => i.message);
      expect(before, contains('firebase_core is not a dependency.'));
      expect(before, contains('${googleServicesJsonPath('dev')} is missing.'));

      fakeFlutterfireOutputs(dir, ['dev']);
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        read(dir, 'pubspec.yaml').replaceFirst(
          'dependencies:\n',
          'dependencies:\n  firebase_core: ^4.0.0\n',
        ),
      );
      expect(firebase.check(contextFor(dir), config), isEmpty);
    },
  );

  test(
    'removes an existing GoogleService-Info.plist from Copy Bundle Resources',
    () async {
      // The usual pre-flavor Firebase setup: the plist is a Runner resource.
      final dir = copyFixture('fresh_kts');
      final xcode = XcodeProject.parse(read(dir, pbxprojFile));
      final pbx = xcode.pbx;
      pbx.add('AACED6046613BEEFAFAA70A1', {
        'isa': 'PBXFileReference',
        'lastKnownFileType': 'text.plist.xml',
        'path': 'Runner/GoogleService-Info.plist',
        'sourceTree': '<group>',
      }, comment: 'GoogleService-Info.plist');
      pbx.add(
        'D47943A4E594549467AAF6AB',
        {'isa': 'PBXBuildFile', 'fileRef': 'AACED6046613BEEFAFAA70A1'},
        comment: 'GoogleService-Info.plist in Resources',
      );
      final phases = (xcode.appTarget.object['buildPhases']! as List)
          .cast<String>();
      final resources = phases.firstWhere(
        (id) => pbx.object(id)!['isa'] == 'PBXResourcesBuildPhase',
      );
      (pbx.object(resources)!['files']! as List<Object>).add(
        'D47943A4E594549467AAF6AB',
      );
      File(p.join(dir.path, pbxprojFile)).writeAsStringSync(xcode.encode());

      final config = withFirebase(configOf(['dev', 'prod']));
      const firebase = FirebaseGenerator(environment: {});
      expect(
        firebase.check(contextFor(dir), config).map((i) => i.message),
        contains(contains('Multiple commands produce')),
      );

      final changes = await plan(dir, config, generators: generators);
      final after = XcodeProject.parse(changes.read(pbxprojFile)!);
      expect(after.pbx.object('D47943A4E594549467AAF6AB'), isNull);
      expect(
        (after.pbx.object(resources)!['files']! as List),
        isNot(contains('D47943A4E594549467AAF6AB')),
      );
      expect(
        after.pbx.object('AACED6046613BEEFAFAA70A1'),
        isNotNull,
        reason: 'file reference kept',
      );
      expect(after.scriptPhaseNamed(copyPlistPhaseName), isNotNull);

      changes.apply();
      fakeFlutterfireOutputs(dir, ['dev', 'prod']);
      final again = await plan(
        dir,
        config,
        previous: config,
        generators: generators,
      );
      expect(
        again.changes.where((c) => c.path == pbxprojFile),
        isEmpty,
        reason: 'idempotent',
      );
    },
  );
}
