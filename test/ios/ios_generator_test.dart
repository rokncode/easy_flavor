import 'dart:io';

import 'package:easy_flavor/src/core/exceptions.dart';
import 'package:easy_flavor/src/ios/ios_files.dart';
import 'package:easy_flavor/src/ios/ios_generator.dart';
import 'package:easy_flavor/src/ios/ios_project.dart';
import 'package:easy_flavor/src/ios/xcode_project.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  const ios = [IosGenerator()];

  XcodeProject project(Directory dir) =>
      XcodeProject.parse(read(dir, pbxprojFile));

  for (final fixture in ['fresh_kts', 'cocoapods']) {
    group(fixture, () {
      test('adds configurations, xcconfigs and schemes; idempotent', () async {
        final dir = copyFixture(fixture);
        await applyAndExpectIdempotent(
          dir,
          configOf(['dev', 'prod']),
          generators: ios,
        );
        final xcode = project(dir);

        for (final owner in xcode.configOwners) {
          expect(
            xcode.configsByName(owner.listId).keys,
            containsAll([
              'Debug-dev',
              'Release-dev',
              'Profile-dev',
              'Debug-prod',
              'Release-prod',
              'Profile-prod',
            ]),
            reason: owner.name,
          );
        }
        final app = xcode.configsByName(xcode.appTarget.listId);
        final devDebug = xcode.config(app['Debug-dev']!);
        expect(
          xcode.pbx.object(
            devDebug['baseConfigurationReference']! as String,
          )!['path'],
          'Flutter/Debug-dev.xcconfig',
        );
        expect(
          xcode.buildSettings(app['Debug-dev']!),
          isNot(contains('PRODUCT_BUNDLE_IDENTIFIER')),
        );
        expect(xcode.buildSettings(app['Debug']!)['APP_DISPLAY_NAME'], 'App');
        expect(
          xcode.buildSettings(app['Debug']!)['PRODUCT_BUNDLE_IDENTIFIER'],
          isNotNull,
          reason: 'base untouched',
        );
        expect(
          read(dir, 'ios/Flutter/Release-dev.xcconfig'),
          contains('PRODUCT_BUNDLE_IDENTIFIER = com.acme.app.dev'),
        );
        expect(
          read(dir, schemePath('dev')),
          contains('buildConfiguration = "Release-dev"'),
        );
        expect(read(dir, infoPlistFile), contains(r'$(APP_DISPLAY_NAME)'));
        expect(managedIosFlavors(contextFor(dir)), {'dev', 'prod'});
        expect(detectExistingIosFlavors(contextFor(dir)), isEmpty);
        expect(
          const IosGenerator().check(
            contextFor(dir),
            configOf(['dev', 'prod']),
          ),
          isEmpty,
        );
      });

      test('removing a flavor removes everything it added', () async {
        final dir = copyFixture(fixture);
        final original = read(dir, pbxprojFile);
        final before = configOf(['dev', 'prod']);
        await applyAndExpectIdempotent(dir, before, generators: ios);
        await applyAndExpectIdempotent(
          dir,
          configOf(['prod']),
          previous: before,
          generators: ios,
        );

        expect(read(dir, pbxprojFile), isNot(contains('-dev')));
        expect(exists(dir, 'ios/Flutter/Debug-dev.xcconfig'), isFalse);
        expect(exists(dir, schemePath('dev')), isFalse);
        expect(exists(dir, schemePath('prod')), isTrue);

        // Only prod's additions remain on top of the original project.
        await applyAndExpectIdempotent(
          dir,
          configOf(['dev']),
          previous: configOf(['prod']),
          generators: ios,
        );
        expect(read(dir, pbxprojFile), isNot(contains('-prod')));
        expect(read(dir, pbxprojFile).length, greaterThan(original.length));
      });
    });
  }

  test(
    'add + remove equals never having added (pbxproj, Podfile, plist)',
    () async {
      final both = copyFixture('cocoapods');
      await applyAndExpectIdempotent(
        both,
        configOf(['dev', 'prod']),
        generators: ios,
      );
      await applyAndExpectIdempotent(
        both,
        configOf(['prod']),
        previous: configOf(['dev', 'prod']),
        generators: ios,
      );
      final onlyProd = copyFixture('cocoapods');
      await applyAndExpectIdempotent(
        onlyProd,
        configOf(['prod']),
        generators: ios,
      );
      for (final file in [pbxprojFile, podfile, infoPlistFile]) {
        expect(read(both, file), read(onlyProd, file), reason: file);
      }
    },
  );

  test('cocoapods: Podfile maps every configuration', () async {
    final dir = copyFixture('cocoapods');
    await applyAndExpectIdempotent(
      dir,
      configOf(['dev', 'prod']),
      generators: ios,
    );
    final podfileText = read(dir, podfile);
    for (final c in ['Debug-dev', 'Release-prod', 'Profile-dev']) {
      expect(podfileText, contains("'$c' =>"));
    }
    expect(podfileText, contains("'Debug-dev' => :debug"));
  });

  test('detects the existing bundle identifier', () {
    expect(
      detectBundleIdentifier(contextFor(copyFixture('fresh_kts'))),
      'com.acme.freshApp',
    );
  });

  test('refuses flavor configurations it does not manage', () async {
    final dir = copyFixture('fresh_kts');
    final xcode = project(dir);
    final app = xcode.appTarget;
    xcode.copyConfiguration(
      app.listId,
      xcode.configsByName(app.listId)['Debug']!,
      'Debug-qa',
    );
    File('${dir.path}/$pbxprojFile').writeAsStringSync(xcode.encode());

    expect(detectExistingIosFlavors(contextFor(dir)), ['qa']);
    expect(
      () => plan(dir, configOf(['dev']), generators: ios),
      throwsA(isA<ProjectError>()),
    );
  });

  test('keeps a scheme the user customised', () async {
    final dir = copyFixture('fresh_kts');
    await applyAndExpectIdempotent(dir, configOf(['dev']), generators: ios);
    final customised = '${read(dir, schemePath('dev'))}<!-- mine -->';
    File('${dir.path}/${schemePath('dev')}').writeAsStringSync(customised);
    await applyAndExpectIdempotent(
      dir,
      configOf(['dev']),
      previous: configOf(['dev']),
      generators: ios,
    );
    expect(read(dir, schemePath('dev')), customised);
  });

  test('doctor reports missing pieces', () async {
    final dir = copyFixture('fresh_kts');
    final messages = const IosGenerator()
        .check(contextFor(dir), configOf(['dev']))
        .map((i) => i.message);
    expect(messages, contains('Xcode configuration Debug-dev is missing.'));
    expect(messages, contains('Xcode scheme "dev" is missing.'));
  });
}
