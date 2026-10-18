import '../core/project_context.dart';

/// Reads `PRODUCT_BUNDLE_IDENTIFIER` of the Runner target (Release config).
String? detectBundleIdentifier(ProjectContext context) {
  // TODO(step 3): implement via the pbxproj parser.
  return null;
}

/// Flavors inferred from existing `<Config>-<flavor>` build configurations.
List<String> detectExistingIosFlavors(ProjectContext context) {
  // TODO(step 3): implement.
  return const [];
}
