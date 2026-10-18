import 'package:easy_flavor/src/config/validators.dart';
import 'package:easy_flavor/src/core/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('validateFlavorName', () {
    for (final ok in ['dev', 'staging', 'prod', 'qa2', 'devLocal']) {
      test('accepts $ok', () => validateFlavorName(ok));
    }
    for (final bad in [
      'Dev', '2dev', 'dev-1', 'dev_1', '', 'main', 'test', 'androidTest', //
      'debug', 'release', 'profile', 'values', 'class', 'name',
    ]) {
      test('rejects "$bad"', () {
        expect(() => validateFlavorName(bad), throwsA(isA<UsageError>()));
      });
    }
  });

  test('Android ids', () {
    validateAndroidId('dev', 'com.company.my_app.dev');
    for (final bad in [
      'com',
      'com.1abc',
      'com.my-app',
      'com..app',
      '.com.app',
    ]) {
      expect(
        () => validateAndroidId('dev', bad),
        throwsA(isA<UsageError>()),
        reason: bad,
      );
    }
  });

  test('iOS bundle ids', () {
    validateIosBundleId('dev', 'com.company.my-app.dev');
    for (final bad in ['com', 'com.my_app', 'com..app']) {
      expect(
        () => validateIosBundleId('dev', bad),
        throwsA(isA<UsageError>()),
        reason: bad,
      );
    }
  });
}
