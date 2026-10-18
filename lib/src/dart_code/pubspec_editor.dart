import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Returns [pubspec] with `flutter: default-flavor:` set to [flavor], so
/// `flutter run` without `--flavor` builds that flavor (Flutter 3.22+).
/// Comments and formatting elsewhere are preserved.
String withDefaultFlavor(String pubspec, String flavor) {
  final editor = YamlEditor(pubspec);
  final flutter = loadYaml(pubspec) is YamlMap
      ? (loadYaml(pubspec) as YamlMap)['flutter']
      : null;
  if (flutter is YamlMap) {
    if (flutter['default-flavor'] == flavor) return pubspec;
    editor.update(['flutter', 'default-flavor'], flavor);
  } else {
    editor.update(['flutter'], {'default-flavor': flavor});
  }
  return editor.toString();
}

/// `flutter: default-flavor:` from [pubspec], or null.
String? readDefaultFlavor(String pubspec) {
  final doc = loadYaml(pubspec);
  if (doc is! YamlMap) return null;
  final flutter = doc['flutter'];
  return flutter is YamlMap ? flutter['default-flavor']?.toString() : null;
}
