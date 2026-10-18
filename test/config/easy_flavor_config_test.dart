import 'package:easy_flavor/easy_flavor.dart';
import 'package:test/test.dart';

void main() {
  const yaml = '''
flavors:
  dev:
    app_name: "MyApp Dev"
    android_id: com.company.myapp.dev
    ios_bundle_id: com.company.myapp.dev
    firebase_project: myapp-dev
  prod:
    app_name: "MyApp"
    android_id: com.company.myapp
    ios_bundle_id: com.company.myapp
firebase: true
''';

  test('parses the documented format', () {
    final c = EasyFlavorConfig.parse(yaml);
    expect(c.firebase, isTrue);
    expect(c.ide, isNull);
    expect(c.hasFlavorList, isTrue);
    expect(c.flavors.map((f) => f.name), ['dev', 'prod']);
    expect(c.flavors.first.appName, 'MyApp Dev');
    expect(c.flavors.first.firebaseProjectId, 'myapp-dev');
    expect(c.flavors.last.iosBundleId, 'com.company.myapp');
  });

  test('allows flavors without settings', () {
    final c = EasyFlavorConfig.parse('flavors:\n  dev:\n  prod:\n');
    expect(c.flavors.map((f) => f.name), ['dev', 'prod']);
    expect(c.flavors.first.appName, isNull);
  });

  test('empty file is an empty config', () {
    expect(EasyFlavorConfig.parse('').isEmpty, isTrue);
  });

  test('toYaml round-trips, including names that need quoting', () {
    const config = EasyFlavorConfig(
      flavors: [
        FlavorSpec(
          name: 'dev',
          appName: 'My "App": Dev',
          androidId: 'com.a.dev',
          iosBundleId: 'com.a.dev',
          firebaseProjectId: 'a-dev',
        ),
        FlavorSpec(
          name: 'prod',
          appName: 'true',
          androidId: 'com.a',
          iosBundleId: 'com.a',
        ),
      ],
      firebase: true,
      ide: [IdeTarget.vscode],
    );
    final parsed = EasyFlavorConfig.parse(config.toYaml());
    expect(parsed.firebase, isTrue);
    expect(parsed.ide, [IdeTarget.vscode]);
    expect(parsed.flavors.first.appName, 'My "App": Dev');
    expect(parsed.flavors.last.appName, 'true');
    expect(parsed.flavors.first.firebaseProjectId, 'a-dev');
  });

  group('rejects', () {
    for (final (label, source) in [
      ('non-map root', '- a'),
      ('non-bool firebase', 'firebase: maybe'),
      ('list flavors', 'flavors: [dev, prod]'),
      ('scalar flavor', 'flavors:\n  dev: 1'),
      ('unknown ide', 'ide: [xcode]'),
      ('invalid yaml', 'flavors: {'),
    ]) {
      test(label, () {
        expect(
          () => EasyFlavorConfig.parse(source),
          throwsA(isA<UsageError>()),
        );
      });
    }
  });
}
