import 'package:easy_flavor/src/config/cli_overrides.dart';
import 'package:easy_flavor/src/core/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('parsePairs', () {
    test('parses key=value pairs and strips quotes', () {
      expect(
        parsePairs('--app-names', [
          'dev="MyApp Dev"',
          "stg='Stg'",
          'prod=MyApp',
        ]),
        {'dev': 'MyApp Dev', 'stg': 'Stg', 'prod': 'MyApp'},
      );
    });

    test('keeps "=" inside values', () {
      expect(parsePairs('--x', ['dev=a=b']), {'dev': 'a=b'});
    });

    test('rejects items without a key', () {
      expect(() => parsePairs('--x', ['=v']), throwsA(isA<UsageError>()));
      expect(() => parsePairs('--x', ['novalue']), throwsA(isA<UsageError>()));
      expect(() => parsePairs('--x', ['dev=']), throwsA(isA<UsageError>()));
    });
  });

  group('parseCliOverrides', () {
    test('keeps --flavors order and maps per-flavor values', () {
      final c = parseCliOverrides(
        flavors: ['dev', 'staging', 'prod'],
        bundleIds: ['dev=com.a.dev', 'prod=com.a'],
        iosBundleIds: ['dev=com.a.ios.dev'],
        appNames: ['prod=App'],
        firebaseProjects: ['dev=a-dev'],
        firebase: true,
      );
      expect(c.hasFlavorList, isTrue);
      expect(c.firebase, isTrue);
      expect(c.flavors.map((f) => f.name), ['dev', 'staging', 'prod']);
      final dev = c.flavors[0];
      expect(dev.androidId, 'com.a.dev');
      expect(dev.iosBundleId, 'com.a.ios.dev', reason: 'specific option wins');
      expect(dev.firebaseProjectId, 'a-dev');
      expect(c.flavors[1].androidId, isNull);
      expect(c.flavors[2].appName, 'App');
    });

    test('rejects values for flavors not in --flavors', () {
      expect(
        () => parseCliOverrides(flavors: ['dev'], bundleIds: ['qa=com.a.qa']),
        throwsA(isA<UsageError>()),
      );
    });

    test('rejects duplicate flavors', () {
      expect(
        () => parseCliOverrides(flavors: ['dev', 'dev']),
        throwsA(isA<UsageError>()),
      );
    });

    test('without --flavors, per-flavor values are overrides only', () {
      final c = parseCliOverrides(appNames: ['dev=D']);
      expect(c.hasFlavorList, isFalse);
      expect(c.flavors.single.appName, 'D');
    });
  });
}
