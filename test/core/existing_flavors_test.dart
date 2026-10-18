import 'dart:io';

import 'package:easy_flavor/src/config/easy_flavor_config.dart';
import 'package:easy_flavor/src/core/existing_flavors.dart';
import 'package:easy_flavor/src/ios/xcode_project.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  test('detects Gradle flavors with effective ids', () {
    final c = detectExistingFlavorConfig(
      contextFor(copyFixture('existing_flavors')),
    );
    expect(c.hasFlavorList, isTrue);
    expect(
      [for (final f in c.flavors) (f.name, f.androidId)],
      [('dev', 'com.legacy.legacy_app.dev'), ('prod', 'com.legacy.legacy_app')],
    );
  });

  test('shared ids are not adopted', () {
    final dir = copyFixture('existing_flavors');
    final gradle = File('${dir.path}/android/app/build.gradle');
    gradle.writeAsStringSync(
      gradle.readAsStringSync().replaceFirst('applicationIdSuffix ".dev"', ''),
    );
    final c = detectExistingFlavorConfig(contextFor(dir));
    expect(c.flavors.map((f) => f.androidId), [null, null]);
  });

  test('detects Xcode-only flavors', () {
    final dir = copyFixture('fresh_kts');
    final xcode = XcodeProject.parse(read(dir, pbxprojFile));
    final list = xcode.appTarget.listId;
    final debug = xcode.configsByName(list)['Debug']!;
    final id = xcode.copyConfiguration(list, debug, 'Release-qa');
    xcode.setBuildSetting(id, 'PRODUCT_BUNDLE_IDENTIFIER', 'com.acme.qa');
    File('${dir.path}/$pbxprojFile').writeAsStringSync(xcode.encode());
    final c = detectExistingFlavorConfig(contextFor(dir));
    expect(c.flavors.single.name, 'qa');
    expect(c.flavors.single.iosBundleId, 'com.acme.qa');
  });

  test('layerConfig: top list and values win', () {
    final base = PartialConfig(
      hasFlavorList: true,
      flavors: const [
        PartialFlavor(name: 'dev', androidId: 'a.dev', appName: 'Dev'),
        PartialFlavor(name: 'prod', androidId: 'a'),
      ],
    );
    final top = PartialConfig(
      mergeExisting: true,
      flavors: const [PartialFlavor(name: 'dev', appName: 'Mine')],
    );
    final layered = layerConfig(base, top);
    expect(layered.flavors.map((f) => f.name), ['dev', 'prod']);
    expect(layered.flavors.first.appName, 'Mine');
    expect(layered.flavors.first.androidId, 'a.dev');
    expect(layered.mergeExisting, isTrue);
  });
}
