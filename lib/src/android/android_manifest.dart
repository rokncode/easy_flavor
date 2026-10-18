import '../core/exceptions.dart';

const manifestFile = 'android/app/src/main/AndroidManifest.xml';
const appNameLabel = '@string/app_name';

/// Returns [manifest] with `<application android:label>` set to
/// `@string/app_name`, adding the attribute if missing.
///
/// Only the `<application ...>` start tag is touched, located by scanning for
/// the tag and its quote-aware end, so other `android:label` attributes (on
/// activities, for example) are left alone.
String withAppNameLabel(String manifest) {
  final tag = _applicationTag(manifest);
  final attrs = manifest.substring(tag.$1, tag.$2);
  final label = RegExp(r'''android:label\s*=\s*("[^"]*"|'[^']*')''');
  final match = label.firstMatch(attrs);
  final String newAttrs;
  if (match != null) {
    newAttrs = attrs.replaceRange(
      match.start,
      match.end,
      'android:label="$appNameLabel"',
    );
  } else {
    // Insert right after "<application", matching the next attribute's
    // indentation when attributes are on their own lines.
    const name = '<application';
    final rest = attrs.substring(name.length);
    final ws = RegExp(r'^\s*').stringMatch(rest)!;
    final sep = ws.contains('\n') ? ws : ' ';
    newAttrs = '$name${sep}android:label="$appNameLabel"$rest';
  }
  return manifest.replaceRange(tag.$1, tag.$2, newAttrs);
}

/// Current value of `<application android:label>`, or null.
String? applicationLabel(String manifest) {
  final tag = _applicationTag(manifest);
  final match = RegExp(
    r'''android:label\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  ).firstMatch(manifest.substring(tag.$1, tag.$2));
  return match == null ? null : match.group(1) ?? match.group(2);
}

/// Start and end (exclusive, before `>` or `/>`) of the application tag.
(int, int) _applicationTag(String manifest) {
  final start = RegExp(r'<application(?=[\s>/])').firstMatch(manifest)?.start;
  if (start == null) {
    throw ProjectError('No <application> element in $manifestFile.');
  }
  String? quote;
  for (var i = start; i < manifest.length; i++) {
    final c = manifest[i];
    if (quote != null) {
      if (c == quote) quote = null;
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (c == '>') {
      return (start, manifest[i - 1] == '/' ? i - 1 : i);
    }
  }
  throw ProjectError('Unterminated <application> tag in $manifestFile.');
}
