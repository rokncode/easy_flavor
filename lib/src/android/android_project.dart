import '../core/project_context.dart';

/// Reads the current `applicationId` from `android/app/build.gradle(.kts)`.
String? detectApplicationId(ProjectContext context) {
  // TODO(step 2): implement for Groovy and Kotlin DSL.
  return null;
}

/// Names of `productFlavors` already declared in the app Gradle file.
List<String> detectExistingAndroidFlavors(ProjectContext context) {
  // TODO(step 2): implement.
  return const [];
}
