import '../config/easy_flavor_config.dart';
import '../config/flavor_spec.dart';
import '../core/change_set.dart';
import '../core/exceptions.dart';
import '../core/generator.dart';
import '../core/project_context.dart';
import '../dart_code/templates.dart' show defaultFlavor;
import 'ios_files.dart';
import 'ios_project.dart';
import 'xcode_project.dart';

/// Xcode build configurations, xcconfig files, schemes, Info.plist display
/// name and the Podfile configuration map.
class IosGenerator implements Generator, Checker {
  const IosGenerator();

  @override
  String get name => 'ios';

  @override
  bool isApplicable(PlanRequest request) => request.context.exists(pbxprojFile);

  @override
  Future<void> plan(PlanRequest request) async {
    final context = request.context;
    final changes = request.changes;
    final config = request.config;
    final xcode = XcodeProject.parse(changes.read(pbxprojFile)!);
    final app = xcode.appTarget;

    // Flavors with easy_flavor xcconfigs. Configurations of other flavors
    // belong to the project (adopted in merge mode).
    final managedOnDisk = managedIosFlavors(context, read: changes.read);
    final appConfigs = xcode.configsByName(app.listId);
    final unmanaged = {
      for (final name in appConfigs.keys)
        if (flavorConfigPattern.firstMatch(name)?.group(2) case final f?)
          if (!managedOnDisk.contains(f)) f,
    };
    final managed = {...managedOnDisk, ...?request.previous?.flavorNames};
    if (unmanaged.isNotEmpty && !config.mergeExisting) {
      throw ProjectError(
        'The Xcode project already has flavor configurations '
        '(${unmanaged.join(', ')}) that easy_flavor does not manage.',
        hint:
            'Remove them, or re-run `easy_flavor init --merge` to adopt them.',
      );
    }
    final bases = [
      for (final b in baseConfigurations)
        if (appConfigs.containsKey(b)) b,
    ];
    if (bases.isEmpty) {
      throw ProjectError(
        'The Runner target has no Debug/Release/Profile configurations.',
      );
    }

    // Removed flavors first, so their names can be reused.
    final removed = managed.difference(config.flavorNames.toSet());
    for (final f in removed) {
      _removeFlavor(xcode, changes, f);
    }

    for (final f in config.flavors) {
      _addFlavor(
        xcode,
        changes,
        app,
        bases,
        f,
        adopted: unmanaged.contains(f.name),
      );
    }

    _planInfoPlist(xcode, changes, app, config);
    changes.write(pbxprojFile, xcode.encode(), reason: 'build configurations');

    _planSchemes(changes, config, removed);
    _planPodfile(changes, xcode, context);
  }

  void _addFlavor(
    XcodeProject xcode,
    ChangeSet changes,
    ConfigOwner app,
    List<String> bases,
    FlavorSpec flavor, {
    bool adopted = false,
  }) {
    for (final base in bases) {
      final configName = '$base-${flavor.name}';
      final existingId = xcode.configsByName(app.listId)[configName];
      if (adopted && existingId != null) {
        // The project's own configuration (merge mode): keep its xcconfig
        // and set the flavor values directly.
        xcode
          ..setBuildSetting(
            existingId,
            'PRODUCT_BUNDLE_IDENTIFIER',
            flavor.iosBundleId,
          )
          ..setBuildSetting(existingId, displayNameSetting, flavor.appName)
          ..setBuildSetting(existingId, flavorSetting, flavor.name);
        _copyToOtherOwners(xcode, app, base, configName);
        continue;
      }
      changes.write(
        xcconfigPath(base, flavor.name),
        renderXcconfig(base, flavor, podsTarget: app.name),
        reason: 'bundle id and display name',
      );

      final template = xcode.baseConfigurationRef(base);
      if (template == null) {
        throw ProjectError(
          'The Runner $base configuration has no base .xcconfig file.',
          hint:
              'Flutter projects set Flutter/Debug.xcconfig or Flutter/Release.xcconfig there.',
        );
      }
      final fileRef = xcode.addSiblingFileRef(
        template,
        xcconfigFileName(base, flavor.name),
      );

      for (final owner in xcode.configOwners) {
        final configs = xcode.configsByName(owner.listId);
        final from = configs[base];
        if (from == null) continue;
        final id =
            configs[configName] ??
            xcode.copyConfiguration(owner.listId, from, configName);
        if (owner.id == app.id) {
          final c = xcode.config(id);
          c['baseConfigurationReference'] = fileRef;
          // Let the xcconfig values win over target-level settings.
          xcode.buildSettings(id)
            ..remove('PRODUCT_BUNDLE_IDENTIFIER')
            ..remove(displayNameSetting)
            ..remove(flavorSetting);
          _moveBaseConfigurationRefFirst(c);
        }
      }
    }
  }

  /// Ensures the project and other targets also have [configName].
  void _copyToOtherOwners(
    XcodeProject xcode,
    ConfigOwner app,
    String base,
    String configName,
  ) {
    for (final owner in xcode.configOwners) {
      if (owner.id == app.id) continue;
      final configs = xcode.configsByName(owner.listId);
      final from = configs[base];
      if (from != null && !configs.containsKey(configName)) {
        xcode.copyConfiguration(owner.listId, from, configName);
      }
    }
  }

  void _removeFlavor(XcodeProject xcode, ChangeSet changes, String flavor) {
    for (final owner in xcode.configOwners) {
      xcode.configsByName(owner.listId).forEach((name, id) {
        if (flavorConfigPattern.firstMatch(name)?.group(2) == flavor) {
          xcode.removeConfiguration(owner.listId, id);
        }
      });
    }
    for (final base in baseConfigurations) {
      final ref = xcode.fileRefNamed(xcconfigFileName(base, flavor));
      if (ref != null) xcode.removeFileRef(ref);
      changes.delete(xcconfigPath(base, flavor), reason: 'flavor removed');
    }
    final scheme = changes.read(schemePath(flavor));
    if (scheme != null && isFlavorScheme(scheme, flavor)) {
      changes.delete(schemePath(flavor), reason: 'flavor removed');
    }
  }

  /// Xcode writes `isa`, then `baseConfigurationReference`, then
  /// `buildSettings`; keep that order for new entries.
  void _moveBaseConfigurationRefFirst(PbxObjectMap c) {
    final entries = c.entries.toList();
    c.clear();
    for (final key in ['isa', 'baseConfigurationReference']) {
      final e = entries.where((e) => e.key == key).firstOrNull;
      if (e != null) c[e.key] = e.value;
    }
    for (final e in entries) {
      c.putIfAbsent(e.key, () => e.value);
    }
  }

  /// Info.plist reads the display name from the build setting; the base
  /// configurations (used without a flavor) get the default flavor's name.
  void _planInfoPlist(
    XcodeProject xcode,
    ChangeSet changes,
    ConfigOwner app,
    EasyFlavorConfig config,
  ) {
    final plist = changes.read(infoPlistFile);
    if (plist == null) return;
    final (updated, _) = withDisplayNameSetting(plist);
    changes.write(
      infoPlistFile,
      updated,
      reason: 'CFBundleDisplayName = \$($displayNameSetting)',
    );
    final fallback = config.flavor(defaultFlavor(config))!;
    xcode.configsByName(app.listId).forEach((configName, id) {
      if (baseConfigurations.contains(configName)) {
        xcode
          ..setBuildSetting(id, displayNameSetting, fallback.appName)
          ..setBuildSetting(id, flavorSetting, fallback.name);
      }
    });
  }

  void _planSchemes(
    ChangeSet changes,
    EasyFlavorConfig config,
    Set<String> removed,
  ) {
    final runner = changes.read(runnerScheme);
    if (runner == null) {
      throw ProjectError(
        '$runnerScheme not found.',
        hint:
            'In Xcode: Product > Scheme > Manage Schemes, tick "Shared" for '
            'Runner. Or copy it from a fresh `flutter create`.',
      );
    }
    for (final f in config.flavorNames) {
      final path = schemePath(f);
      final existing = changes.read(path);
      if (existing != null && !isFlavorScheme(existing, f)) {
        throw ProjectError(
          '$path exists and does not use the $f configurations.',
          hint: 'Rename or delete that scheme, then re-run.',
        );
      }
      // Keep a scheme the user customised in Xcode; only create missing ones.
      if (existing == null) {
        changes.write(path, renderScheme(runner, f), reason: 'scheme');
      }
    }
  }

  void _planPodfile(
    ChangeSet changes,
    XcodeProject xcode,
    ProjectContext context,
  ) {
    final source = changes.read(podfile);
    if (source == null) {
      context.logger.detail(
        'No ios/Podfile (Swift Package Manager project); skipping.',
      );
      return;
    }
    changes.write(
      podfile,
      withPodfileConfigurations(source, xcode.appConfigurationNames),
      reason: 'configuration map',
    );
  }

  @override
  List<Issue> check(ProjectContext context, EasyFlavorConfig config) {
    final source = context.readOrNull(pbxprojFile);
    if (source == null) return const [];
    final XcodeProject xcode;
    try {
      xcode = XcodeProject.parse(source);
    } on ProjectError catch (e) {
      return [Issue(Severity.error, e.message)];
    }
    final issues = <Issue>[];
    final appConfigs = xcode.configsByName(xcode.appTarget.listId);
    for (final f in config.flavorNames) {
      for (final base in baseConfigurations) {
        if (!appConfigs.containsKey(base)) continue;
        final name = '$base-$f';
        if (!appConfigs.containsKey(name)) {
          issues.add(
            Issue(
              Severity.error,
              'Xcode configuration $name is missing.',
              fix: 'Run `easy_flavor init`.',
            ),
          );
        }
        final adoptedOk =
            config.mergeExisting &&
            appConfigs[name] != null &&
            xcode.buildSettings(
                  appConfigs[name]!,
                )['PRODUCT_BUNDLE_IDENTIFIER'] ==
                config.flavor(f)!.iosBundleId;
        if (!adoptedOk && !context.exists(xcconfigPath(base, f))) {
          issues.add(
            Issue(
              Severity.error,
              '${xcconfigPath(base, f)} is missing.',
              fix: 'Run `easy_flavor init`.',
            ),
          );
        }
      }
      if (!context.exists(schemePath(f))) {
        issues.add(
          Issue(
            Severity.error,
            'Xcode scheme "$f" is missing.',
            fix: 'Run `easy_flavor init`.',
          ),
        );
      }
    }
    final pods = context.readOrNull(podfile);
    if (pods != null) {
      for (final name in appConfigs.keys) {
        if (!pods.contains("'$name'")) {
          issues.add(
            Issue(
              Severity.warning,
              'Podfile does not map configuration $name; CocoaPods will treat it as release.',
              fix: 'Run `easy_flavor init`.',
            ),
          );
        }
      }
    }
    final plist = context.readOrNull(infoPlistFile);
    if (plist != null && !plist.contains('\$($displayNameSetting)')) {
      issues.add(
        const Issue(
          Severity.warning,
          'Info.plist CFBundleDisplayName does not use \$($displayNameSetting); flavor app names are ignored on iOS.',
          fix: 'Run `easy_flavor init`.',
        ),
      );
    }
    return issues;
  }
}

typedef PbxObjectMap = Map<String, Object>;
