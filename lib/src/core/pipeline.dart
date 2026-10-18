import '../android/android_generator.dart';
import '../config/easy_flavor_config.dart';
import '../dart_code/dart_code_generator.dart';
import '../firebase/firebase_generator.dart';
import '../ide/ide_generator.dart';
import '../ios/ios_generator.dart';
import 'backup.dart';
import 'change_set.dart';
import 'generator.dart';
import 'project_context.dart';

/// Generators in the order they run. Firebase runs after the platforms
/// because it adds files into the folders they create.
const defaultGenerators = <Generator>[
  DartCodeGenerator(),
  AndroidGenerator(),
  IosGenerator(),
  FirebaseGenerator(),
  IdeGenerator(),
];

/// Runs every applicable generator and returns the combined plan, including
/// the updated easy_flavor.yaml. Nothing is written to disk.
Future<ChangeSet> planChanges({
  required ProjectContext context,
  required EasyFlavorConfig config,
  EasyFlavorConfig? previous,
  List<Generator> generators = defaultGenerators,
}) async {
  final changes = ChangeSet(context.root);
  final request = PlanRequest(
    context: context,
    config: config,
    previous: previous,
    changes: changes,
  );
  for (final g in generators) {
    if (!g.isApplicable(request)) {
      context.logger.detail('Skipping ${g.name}.');
      continue;
    }
    context.logger.detail('Planning ${g.name}...');
    await g.plan(request);
  }
  changes.write(
    EasyFlavorConfig.fileName,
    config.toYaml(),
    reason: 'flavor configuration',
  );
  final gitignore = changes.read('.gitignore');
  if (gitignore != null &&
      !gitignore.split('\n').any((l) => l.trim() == '$backupDirName/')) {
    final sep = gitignore.isEmpty || gitignore.endsWith('\n') ? '' : '\n';
    changes.write(
      '.gitignore',
      '$gitignore$sep\n# easy_flavor backups\n$backupDirName/\n',
      reason: 'ignore easy_flavor backups',
    );
  }
  return changes;
}
