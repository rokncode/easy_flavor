import '../core/project_context.dart';
import 'ios_files.dart';
import 'xcode_project.dart';

XcodeProject? readXcodeProject(
  ProjectContext context, {
  String? Function(String path)? read,
}) {
  final source = (read ?? context.readOrNull)(pbxprojFile);
  return source == null ? null : XcodeProject.parse(source);
}

/// Reads `PRODUCT_BUNDLE_IDENTIFIER` of the Runner target (Release config).
String? detectBundleIdentifier(ProjectContext context) =>
    readXcodeProject(context)?.bundleIdentifier;

/// Flavors easy_flavor manages: those with a generated
/// `ios/Flutter/<Config>-<flavor>.xcconfig`.
Set<String> managedIosFlavors(
  ProjectContext context, {
  String? Function(String path)? read,
}) {
  read ??= context.readOrNull;
  final dir = context.dir('ios/Flutter');
  if (!dir.existsSync()) return {};
  final result = <String>{};
  for (final entity in dir.listSync()) {
    final name = entity.uri.pathSegments.last;
    final match = RegExp(
      r'^(Debug|Release|Profile)-(\w+)\.xcconfig$',
    ).firstMatch(name);
    if (match == null) continue;
    final content = read('ios/Flutter/$name');
    if (content != null && content.startsWith(generatedXcconfigHeader)) {
      result.add(match.group(2)!);
    }
  }
  return result;
}

/// Flavors inferred from `<Config>-<flavor>` build configurations that
/// easy_flavor did not create.
List<String> detectExistingIosFlavors(ProjectContext context) {
  final project = readXcodeProject(context);
  if (project == null) return const [];
  final managed = managedIosFlavors(context);
  return {
    for (final name in project.appConfigurationNames)
      if (flavorConfigPattern.firstMatch(name)?.group(2) case final f?)
        if (!managed.contains(f)) f,
  }.toList();
}
