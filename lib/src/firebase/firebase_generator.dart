import '../config/easy_flavor_config.dart';
import '../core/generator.dart';
import '../core/project_context.dart';

/// flutterfire configure per flavor, google-services.json / GoogleService-Info.plist placement.
class FirebaseGenerator implements Generator, Checker {
  const FirebaseGenerator();

  @override
  String get name => 'firebase';

  @override
  bool isApplicable(PlanRequest request) => request.config.firebase;

  @override
  Future<void> plan(PlanRequest request) async {
    // TODO(step 4): implement.
  }

  @override
  List<Issue> check(ProjectContext context, EasyFlavorConfig config) =>
      const [];
}
