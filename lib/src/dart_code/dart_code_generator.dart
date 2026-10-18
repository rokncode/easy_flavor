import '../config/easy_flavor_config.dart';
import '../core/generator.dart';
import '../core/project_context.dart';

/// Dart entry points (`lib/flavors.dart`, `lib/main_<flavor>.dart`).
class DartCodeGenerator implements Generator, Checker {
  const DartCodeGenerator();

  @override
  String get name => 'dart';

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
