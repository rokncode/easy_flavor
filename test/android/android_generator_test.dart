import 'dart:io';

import 'package:easy_flavor/src/android/android_generator.dart';
import 'package:easy_flavor/src/android/android_resources.dart';
import 'package:easy_flavor/src/android/gradle_file.dart';
import 'package:easy_flavor/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  const android = [AndroidGenerator()];

  for (final (fixture, buildFile) in [
    ('fresh_kts', kotlinBuildFile),
    ('groovy', groovyBuildFile),
  ]) {
    group(fixture, () {
      test('configures flavors and is idempotent', () async {
        final dir = copyFixture(fixture);
        final config = configOf(['dev', 'staging', 'prod']);
        final changes = await applyAndExpectIdempotent(
          dir,
          config,
          generators: android,
        );

        expect(
          changes.changes.map((c) => c.path),
          containsAll([
            buildFile,
            'android/app/src/main/AndroidManifest.xml',
            'android/app/src/dev/.gitkeep',
            'android/app/src/staging/.gitkeep',
            'android/app/src/prod/.gitkeep',
          ]),
        );
        final gradle = GradleFile(buildFile, read(dir, buildFile));
        expect(gradle.managedFlavors, ['dev', 'staging', 'prod']);
        expect(read(dir, buildFile), contains('com.acme.app.staging'));
        expect(read(dir, buildFile), contains('App STAGING'));
        expect(
          read(dir, 'android/app/src/main/AndroidManifest.xml'),
          contains('android:label="@string/app_name"'),
        );
      });

      test('removing a flavor drops it and its folder placeholder', () async {
        final dir = copyFixture(fixture);
        final before = configOf(['dev', 'staging', 'prod']);
        await applyAndExpectIdempotent(dir, before, generators: android);
        final after = configOf(['dev', 'prod']);
        await applyAndExpectIdempotent(
          dir,
          after,
          previous: before,
          generators: android,
        );

        expect(GradleFile(buildFile, read(dir, buildFile)).managedFlavors, [
          'dev',
          'prod',
        ]);
        expect(exists(dir, 'android/app/src/staging'), isFalse);
      });
    });
  }

  test('removing a flavor keeps user files in its source set', () async {
    final dir = copyFixture('fresh_kts');
    final before = configOf(['dev', 'prod']);
    await applyAndExpectIdempotent(dir, before, generators: android);
    final json = '${dir.path}/android/app/src/dev/google-services.json';
    await File(json).writeAsString('{}');
    await applyAndExpectIdempotent(
      dir,
      configOf(['prod']),
      previous: before,
      generators: android,
    );
    expect(File(json).existsSync(), isTrue);
  });

  test(
    'uses per-flavor strings.xml when main already defines app_name',
    () async {
      final dir = copyFixture('fresh_kts');
      File(
        '${dir.path}/android/app/src/main/res/values/strings.xml',
      ).writeAsStringSync(
        '<resources><string name="app_name">Main</string></resources>',
      );
      final config = configOf(['dev', 'prod'], appName: "Bob's & Co");
      await applyAndExpectIdempotent(dir, config, generators: android);

      expect(read(dir, kotlinBuildFile), isNot(contains('resValue')));
      expect(read(dir, kotlinBuildFile), isNot(contains('resValues = true')));
      expect(
        read(dir, flavorStringsPath('prod')),
        contains(r"Bob\'s &amp; Co"),
      );
      expect(
        read(dir, flavorStringsPath('dev')),
        contains(generatedXmlComment),
      );
    },
  );

  test(
    'switching back to resValue deletes generated strings.xml only',
    () async {
      final dir = copyFixture('fresh_kts');
      final mainStrings =
          File('${dir.path}/android/app/src/main/res/values/strings.xml')
            ..writeAsStringSync(
              '<resources><string name="app_name">Main</string></resources>',
            );
      final config = configOf(['dev', 'prod']);
      await applyAndExpectIdempotent(dir, config, generators: android);
      mainStrings.deleteSync();
      await applyAndExpectIdempotent(
        dir,
        config,
        previous: config,
        generators: android,
      );
      expect(exists(dir, flavorStringsPath('dev')), isFalse);
      expect(read(dir, kotlinBuildFile), contains('resValue('));
    },
  );

  test('existing_flavors: refuses to overwrite unmanaged flavors', () async {
    final dir = copyFixture('existing_flavors');
    expect(
      () => plan(dir, configOf(['dev', 'prod']), generators: android),
      throwsA(isA<ProjectError>()),
    );
  });

  test('doctor check: clean after setup, flags drift', () async {
    final dir = copyFixture('fresh_kts');
    final config = configOf(['dev', 'prod']);
    const generator = AndroidGenerator();
    expect(
      generator.check(contextFor(dir), config).map((i) => i.message),
      contains(contains('no easy_flavor productFlavors block')),
    );
    await applyAndExpectIdempotent(dir, config, generators: android);
    expect(generator.check(contextFor(dir), config), isEmpty);
    expect(
      generator
          .check(contextFor(dir), configOf(['dev', 'qa', 'prod']))
          .single
          .message,
      contains('do not match'),
    );
  });
}
