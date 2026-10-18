import '../android/android_project.dart';
import '../core/exceptions.dart';
import '../core/flutter_project.dart';
import 'add_command.dart';
import 'base_command.dart';
import 'setup_flow.dart';

/// `easy_flavor remove <flavor>`.
class RemoveCommand extends EasyFlavorCommand {
  RemoveCommand({required super.logger, super.processRunner}) {
    argParser.addFlag(
      'yes',
      abbr: 'y',
      help: 'Do not ask for confirmation.',
      negatable: false,
    );
    addSafetyOptions(argParser);
  }

  @override
  String get name => 'remove';

  @override
  String get description =>
      'Remove a flavor and its generated files (Firebase config files are kept).';

  @override
  String get invocation => 'easy_flavor remove <flavor> [options]';

  @override
  Future<int> run() async {
    final flavor = singleRest('flavor name');
    final root = requireFlutterProject(projectDirArg);
    final current = requireAppliedConfig(root);
    if (current.flavor(flavor) == null) {
      throw UsageError(
        'Flavor "$flavor" does not exist.',
        hint: 'Configured flavors: ${current.flavorNames.join(', ')}.',
      );
    }
    if (current.flavors.length == 1) {
      throw UsageError('Cannot remove the only flavor.');
    }
    final gradle = readAppGradleFile(contextFor(root));
    if (gradle != null && gradle.unmanagedFlavors.contains(flavor)) {
      throw UsageError(
        '"$flavor" is declared in your own productFlavors in ${gradle.path}.',
        hint: 'Delete it there first, then run `easy_flavor remove $flavor`.',
      );
    }

    final config = current.copyWith(
      flavors: [
        for (final f in current.flavors)
          if (f.name != flavor) f,
      ],
    );
    return runSetup(
      context: contextFor(root),
      config: config,
      previous: current,
      confirm: !args.flag('yes'),
      force: args.flag('force'),
    );
  }
}
