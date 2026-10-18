import '../config/easy_flavor_config.dart';
import 'change_set.dart';
import 'project_context.dart';

/// Input for a [Generator] run.
class PlanRequest {
  PlanRequest({
    required this.context,
    required this.config,
    required this.changes,
    this.previous,
  });

  final ProjectContext context;

  /// The desired end state.
  final EasyFlavorConfig config;

  /// The config easy_flavor applied last time (from easy_flavor.yaml), if any.
  /// Lets generators clean up flavors that were removed.
  final EasyFlavorConfig? previous;

  /// Where generators record their edits. Read through it, not from disk, so
  /// a generator sees edits planned by the ones before it.
  final ChangeSet changes;
}

/// One platform/area of the flavor setup (Dart entry points, Gradle, Xcode,
/// Firebase, IDE configs).
///
/// Generators are declarative: given [PlanRequest.config] they make the
/// project match it. Running one against an already-converged project must
/// record no changes, which is how commands stay idempotent.
abstract interface class Generator {
  /// Short label for logs, e.g. "android".
  String get name;

  /// Whether this generator applies to the project (e.g. no `ios/` folder
  /// means the iOS generator is skipped).
  bool isApplicable(PlanRequest request);

  Future<void> plan(PlanRequest request);
}

/// Something found by `doctor` or a pre-flight check.
class Issue {
  const Issue(this.severity, this.message, {this.fix});

  final Severity severity;
  final String message;

  /// Suggested command or manual step.
  final String? fix;
}

enum Severity { info, warning, error }

/// Implemented by generators that can check an existing setup.
abstract interface class Checker {
  String get name;

  List<Issue> check(ProjectContext context, EasyFlavorConfig config);
}
