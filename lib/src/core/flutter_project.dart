import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'exceptions.dart';

/// Finds the Flutter project root starting at [start] and returns its
/// absolute path. Throws [ProjectError] if [start] is not a Flutter app.
String requireFlutterProject(String start) {
  final root = p.normalize(p.absolute(start));
  final pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw ProjectError(
      'No pubspec.yaml found in $root.',
      hint:
          'Run this command from the root of a Flutter project, or pass --project-dir.',
    );
  }
  final doc = loadYaml(pubspec.readAsStringSync());
  final deps = doc is YamlMap ? doc['dependencies'] : null;
  if (deps is! YamlMap || !deps.containsKey('flutter')) {
    throw ProjectError(
      '$root is not a Flutter project (no flutter dependency in pubspec.yaml).',
    );
  }
  return root;
}

/// The `name:` field of pubspec.yaml in [root].
String readPackageName(String root) {
  final doc = loadYaml(File(p.join(root, 'pubspec.yaml')).readAsStringSync());
  final name = doc is YamlMap ? doc['name'] : null;
  if (name is! String) throw ProjectError('pubspec.yaml has no "name".');
  return name;
}

/// Valid Dart package name, as `flutter create` requires.
final dartPackageName = RegExp(r'^[a-z][a-z0-9_]*$');
