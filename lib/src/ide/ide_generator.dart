import '../config/easy_flavor_config.dart';
import '../core/generator.dart';
import '../core/project_context.dart';

/// .vscode/launch.json and Android Studio run configurations.
class IdeGenerator implements Generator, Checker {
  const IdeGenerator();

  @override
  String get name => 'ide';

  @override
  bool isApplicable(PlanRequest request) => true;

  @override
  Future<void> plan(PlanRequest request) async {
    // TODO(step 2): implement.
  }

  @override
  List<Issue> check(ProjectContext context, EasyFlavorConfig config) =>
      const [];
}
