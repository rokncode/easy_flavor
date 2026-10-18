import '../config/easy_flavor_config.dart';
import '../core/generator.dart';
import '../core/project_context.dart';

/// Xcode build configurations, schemes, xcconfig files and Podfile mapping.
class IosGenerator implements Generator, Checker {
  const IosGenerator();

  @override
  String get name => 'ios';

  @override
  bool isApplicable(PlanRequest request) => request.context.exists('ios');

  @override
  Future<void> plan(PlanRequest request) async {
    // TODO(step 3): implement.
  }

  @override
  List<Issue> check(ProjectContext context, EasyFlavorConfig config) =>
      const [];
}
