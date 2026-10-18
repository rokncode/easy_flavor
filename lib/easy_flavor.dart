/// Set up Flutter flavors for Android and iOS.
///
/// This library exposes the command runner so the CLI can be embedded or
/// tested; the stable interface is the `easy_flavor` executable.
library;

export 'src/command_runner.dart' show EasyFlavorCommandRunner, executableName;
export 'src/config/easy_flavor_config.dart' show EasyFlavorConfig, IdeTarget;
export 'src/config/flavor_spec.dart' show FlavorSpec;
export 'src/core/exceptions.dart';
