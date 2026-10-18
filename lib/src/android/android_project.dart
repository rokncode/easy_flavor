import '../core/exceptions.dart';
import '../core/project_context.dart';
import 'gradle_file.dart';

/// Reads the app module build script, preferring Kotlin DSL when both exist
/// (Gradle itself would error in that case, which `doctor` reports).
///
/// [read] lets callers read through a ChangeSet; defaults to disk.
GradleFile? readAppGradleFile(
  ProjectContext context, {
  String? Function(String path)? read,
}) {
  read ??= context.readOrNull;
  for (final path in [kotlinBuildFile, groovyBuildFile]) {
    final source = read(path);
    if (source != null) return GradleFile(path, source);
  }
  return null;
}

GradleFile requireAppGradleFile(
  ProjectContext context, {
  String? Function(String path)? read,
}) =>
    readAppGradleFile(context, read: read) ??
    (throw ProjectError(
      'Neither $kotlinBuildFile nor $groovyBuildFile exists.',
      hint: 'Is this a Flutter app with an Android folder?',
    ));

/// Reads the current `applicationId` from `android/app/build.gradle(.kts)`.
String? detectApplicationId(ProjectContext context) =>
    readAppGradleFile(context)?.applicationId;

/// Names of `productFlavors` declared outside easy_flavor's managed block.
List<String> detectExistingAndroidFlavors(ProjectContext context) =>
    readAppGradleFile(context)?.unmanagedFlavors ?? const [];
