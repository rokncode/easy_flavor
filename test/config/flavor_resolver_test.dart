import 'package:easy_flavor/easy_flavor.dart';
import 'package:easy_flavor/src/config/cli_overrides.dart';
import 'package:easy_flavor/src/config/easy_flavor_config.dart';
import 'package:easy_flavor/src/config/flavor_resolver.dart';
import 'package:test/test.dart';

void main() {
  EasyFlavorConfig resolve({
    String file = '',
    PartialConfig cli = const PartialConfig(),
    String baseId = 'com.company.myapp',
    String? iosBaseId,
  }) => resolveConfig(
    file: EasyFlavorConfig.parse(file),
    cli: cli,
    baseId: baseId,
    iosBaseId: iosBaseId,
    baseAppName: 'My App',
  );

  test('generates defaults: prod has no suffix', () {
    final c = resolve(
      cli: parseCliOverrides(flavors: ['dev', 'staging', 'prod']),
    );
    expect(
      [for (final f in c.flavors) (f.appName, f.androidId, f.iosBundleId)],
      [
        ('My App Dev', 'com.company.myapp.dev', 'com.company.myapp.dev'),
        (
          'My App Staging',
          'com.company.myapp.staging',
          'com.company.myapp.staging',
        ),
        ('My App', 'com.company.myapp', 'com.company.myapp'),
      ],
    );
    expect(c.firebase, isFalse);
    expect(c.ide, IdeTarget.values);
  });

  test('uses a separate iOS base id when given', () {
    final c = resolve(
      cli: parseCliOverrides(flavors: ['dev', 'prod']),
      baseId: 'com.a.android',
      iosBaseId: 'com.a.ios',
    );
    expect(c.flavor('dev')!.iosBundleId, 'com.a.ios.dev');
    expect(c.flavor('prod')!.androidId, 'com.a.android');
  });

  test('flags override the file, file overrides defaults', () {
    final c = resolve(
      file: '''
flavors:
  dev:
    app_name: File Dev
    android_id: com.file.dev
  prod:
firebase: true
''',
      cli: parseCliOverrides(appNames: ['dev=Cli Dev'], firebase: false),
    );
    final dev = c.flavor('dev')!;
    expect(dev.appName, 'Cli Dev');
    expect(dev.androidId, 'com.file.dev');
    expect(dev.iosBundleId, 'com.company.myapp.dev');
    expect(c.firebase, isFalse);
  });

  test('--flavors replaces the file flavor list but keeps file values', () {
    final c = resolve(
      file: 'flavors:\n  dev:\n    app_name: Keep\n  qa:\n  prod:\n',
      cli: parseCliOverrides(flavors: ['dev', 'prod']),
    );
    expect(c.flavorNames, ['dev', 'prod']);
    expect(c.flavor('dev')!.appName, 'Keep');
  });

  test('overrides for unknown flavors without --flavors are errors', () {
    expect(
      () => resolve(
        file: 'flavors:\n  dev:\n',
        cli: parseCliOverrides(appNames: ['qa=Q']),
      ),
      throwsA(isA<UsageError>()),
    );
  });

  test('requires at least one flavor', () {
    expect(() => resolve(), throwsA(isA<UsageError>()));
  });

  test('rejects duplicate identifiers', () {
    expect(
      () => resolve(
        cli: parseCliOverrides(
          flavors: ['dev', 'prod'],
          bundleIds: ['dev=com.company.myapp'],
        ),
      ),
      throwsA(isA<UsageError>()),
    );
  });

  test('name helpers', () {
    expect(titleCaseFromPackage('my_cool_app'), 'My Cool App');
    expect(bundleSegmentFromPackage('my_cool_app'), 'mycoolapp');
    expect(defaultBundleId('com.a', 'production'), 'com.a');
    expect(defaultAppName('A', 'qa'), 'A Qa');
    expect(
      iosBundleIdFromAndroid('com.acme_co.my_cool_app'),
      'com.acmeCo.myCoolApp',
    );
    expect(iosBundleIdFromAndroid('com.acme.app'), 'com.acme.app');
  });
}
