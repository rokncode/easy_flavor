import 'package:easy_flavor/easy_flavor.dart';
import 'package:easy_flavor/src/android/gradle_file.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  const flavors = [
    FlavorSpec(
      name: 'dev',
      appName: 'App Dev',
      androidId: 'com.a.dev',
      iosBundleId: 'com.a.dev',
    ),
    FlavorSpec(
      name: 'prod',
      appName: 'App',
      androidId: 'com.a',
      iosBundleId: 'com.a',
    ),
  ];

  test('renders the Kotlin DSL block', () {
    expect(
      renderFlavorBlock(flavors, GradleDsl.kotlin, AppNameSource.resValue),
      '''
    // easy_flavor:begin (generated from easy_flavor.yaml; edits here are overwritten)
    buildFeatures {
        resValues = true
    }
    flavorDimensions += "flavor"
    productFlavors {
        create("dev") {
            dimension = "flavor"
            applicationId = "com.a.dev"
            resValue("string", "app_name", "App Dev")
        }
        create("prod") {
            dimension = "flavor"
            applicationId = "com.a"
            resValue("string", "app_name", "App")
        }
    }
    // easy_flavor:end
''',
    );
  });

  test('renders the Groovy block; strings.xml mode omits resValue', () {
    final block = renderFlavorBlock(
      flavors.take(1).toList(),
      GradleDsl.groovy,
      AppNameSource.flavorStringsXml,
      indent: '  ',
    );
    expect(block, '''
  // easy_flavor:begin (generated from easy_flavor.yaml; edits here are overwritten)
  flavorDimensions "flavor"
  productFlavors {
      dev {
          dimension "flavor"
          applicationId "com.a.dev"
      }
  }
  // easy_flavor:end
''');
  });

  test('escapes app names for Gradle and Android resources', () {
    expect(gradleResValueString("Bob's"), r"Bob\\'s");
    expect(gradleResValueString('Say "Hi"'), r'Say \\\"Hi\\\"');
    expect(gradleResValueString(r'$5'), r'\$5');
    expect(gradleResValueString(r'a\b'), r'a\\\\b');
  });

  group('fresh_kts fixture', () {
    late GradleFile gradle;
    setUp(() {
      final dir = copyFixture('fresh_kts');
      gradle = GradleFile(kotlinBuildFile, read(dir, kotlinBuildFile));
    });

    test('detects DSL and applicationId', () {
      expect(gradle.dsl, GradleDsl.kotlin);
      expect(gradle.applicationId, 'com.acme.fresh_app');
      expect(gradle.unmanagedFlavors, isEmpty);
      expect(gradle.managedRange, isNull);
    });

    test('inserts the block after defaultConfig, then replaces it in place', () {
      final once = gradle.withFlavors(flavors, AppNameSource.resValue);
      expect(
        once,
        contains(
          '        versionName = flutter.versionName\n    }\n\n    // easy_flavor:begin',
        ),
      );
      final reparsed = GradleFile(kotlinBuildFile, once);
      expect(reparsed.managedFlavors, ['dev', 'prod']);
      expect(reparsed.unmanagedFlavors, isEmpty);
      expect(reparsed.applicationId, 'com.acme.fresh_app');

      expect(
        reparsed.withFlavors(flavors, AppNameSource.resValue),
        once,
        reason: 'idempotent',
      );

      final fewer = reparsed.withFlavors(
        flavors.skip(1).toList(),
        AppNameSource.resValue,
      );
      expect(GradleFile(kotlinBuildFile, fewer).managedFlavors, ['prod']);
      expect(fewer, isNot(contains('com.a.dev')));
      expect('easy_flavor:begin'.allMatches(fewer), hasLength(1));
    });
  });

  test('groovy fixture: applicationId without "="', () {
    final dir = copyFixture('groovy');
    final gradle = GradleFile(groovyBuildFile, read(dir, groovyBuildFile));
    expect(gradle.dsl, GradleDsl.groovy);
    expect(gradle.applicationId, 'com.legacy.legacy_app');
    final out = gradle.withFlavors(flavors, AppNameSource.resValue);
    expect(
      out,
      contains(
        '        dev {\n            dimension "flavor"\n            applicationId "com.a.dev"',
      ),
    );
    expect(GradleFile(groovyBuildFile, out).managedFlavors, ['dev', 'prod']);
  });

  test(
    'existing_flavors fixture: unmanaged flavors are detected and refused',
    () {
      final dir = copyFixture('existing_flavors');
      final gradle = GradleFile(groovyBuildFile, read(dir, groovyBuildFile));
      expect(gradle.unmanagedFlavors, ['dev', 'prod']);
      expect(
        () => gradle.withFlavors(flavors, AppNameSource.resValue),
        throwsA(
          isA<ProjectError>().having(
            (e) => e.hint,
            'hint',
            contains('--merge'),
          ),
        ),
      );
    },
  );

  test('inserts at the end of android {} when there is no defaultConfig', () {
    const src = 'android {\n    namespace = "x"\n}\n';
    final out = GradleFile(
      kotlinBuildFile,
      src,
    ).withFlavors(flavors, AppNameSource.resValue);
    expect(
      out,
      startsWith('android {\n    namespace = "x"\n\n    // easy_flavor:begin'),
    );
    expect(out, endsWith('    // easy_flavor:end\n}\n'));
  });

  test('applicationId set from a variable is not detected', () {
    const src =
        'android {\n  defaultConfig {\n    applicationId = appId\n  }\n}\n';
    expect(GradleFile(kotlinBuildFile, src).applicationId, isNull);
  });

  test('a begin marker without an end marker is an error', () {
    const src = 'android {\n    // easy_flavor:begin\n}\n';
    expect(
      () => GradleFile(
        kotlinBuildFile,
        src,
      ).withFlavors(flavors, AppNameSource.resValue),
      throwsA(isA<ProjectError>()),
    );
  });

  test('missing android block and parse errors are project errors', () {
    expect(
      () => GradleFile(
        kotlinBuildFile,
        'plugins {}\n',
      ).withFlavors(flavors, AppNameSource.resValue),
      throwsA(isA<ProjectError>()),
    );
    expect(
      () => GradleFile(kotlinBuildFile, 'android {'),
      throwsA(isA<ProjectError>()),
    );
  });
}
