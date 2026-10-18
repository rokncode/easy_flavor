import 'dart:io';

import 'package:path/path.dart' as p;

/// Creates a minimal Flutter project in a temp dir (just enough for the
/// commands' project checks). Platform fixtures arrive with steps 2 and 3.
Directory createMinimalFlutterProject({
  String name = 'my_app',
  String? easyFlavorYaml,
}) {
  final dir = Directory.systemTemp.createTempSync('easy_flavor_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $name
environment:
  sdk: ^3.8.0
dependencies:
  flutter:
    sdk: flutter
''');
  if (easyFlavorYaml != null) {
    File(
      p.join(dir.path, 'easy_flavor.yaml'),
    ).writeAsStringSync(easyFlavorYaml);
  }
  return dir;
}
