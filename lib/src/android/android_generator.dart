import '../config/easy_flavor_config.dart';
import '../core/generator.dart';
import '../core/project_context.dart';

/// Gradle productFlavors, resValue app_name, AndroidManifest label, `src/<flavor>/` folders.
class AndroidGenerator implements Generator, Checker {
  const AndroidGenerator();

  @override
  String get name => 'android';

  @override
  bool isApplicable(PlanRequest request) => request.context.exists('android');

  @override
  Future<void> plan(PlanRequest request) async {
    // TODO(step 2): implement.
  }

  @override
  List<Issue> check(ProjectContext context, EasyFlavorConfig config) =>
      const [];
}
