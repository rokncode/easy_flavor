import 'package:easy_flavor/src/android/android_manifest.dart';
import 'package:easy_flavor/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  test('replaces the application label in the fresh manifest only', () {
    final dir = copyFixture('fresh_kts');
    final manifest = read(dir, manifestFile);
    final out = withAppNameLabel(manifest);
    expect(applicationLabel(manifest), 'fresh_app');
    expect(applicationLabel(out), '@string/app_name');
    expect(
      out.replaceFirst(
        'android:label="@string/app_name"',
        'android:label="fresh_app"',
      ),
      manifest,
    );
    expect(withAppNameLabel(out), out, reason: 'idempotent');
  });

  test('does not touch activity labels', () {
    const src =
        '<manifest><application android:icon="@mipmap/x">'
        '<activity android:label="Act"/></application></manifest>';
    final out = withAppNameLabel(src);
    expect(
      out,
      contains('<application android:label="@string/app_name" android:icon'),
    );
    expect(out, contains('<activity android:label="Act"/>'));
  });

  test('adds the label on its own line when attributes are multi-line', () {
    const src =
        '<application\n        android:name="x"\n        android:icon="y">';
    expect(
      withAppNameLabel(src),
      '<application\n        android:label="@string/app_name"\n        android:name="x"\n        android:icon="y">',
    );
  });

  test('handles ">" inside attribute values and single quotes', () {
    const src = "<application android:label='a>b' android:name=\"x\">";
    expect(
      withAppNameLabel(src),
      '<application android:label="@string/app_name" android:name="x">',
    );
  });

  test('requires an application element', () {
    expect(() => withAppNameLabel('<manifest/>'), throwsA(isA<ProjectError>()));
  });
}
