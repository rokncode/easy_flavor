import 'package:path/path.dart' as p;

import '../core/exceptions.dart';
import 'pbxproj.dart';

const pbxprojFile = 'ios/Runner.xcodeproj/project.pbxproj';

/// The configurations Flutter creates; flavors get `<base>-<flavor>` copies.
const baseConfigurations = ['Debug', 'Release', 'Profile'];

final flavorConfigPattern = RegExp(r'^(Debug|Release|Profile)-(.+)$');

/// A target or the project, with its build configuration list.
class ConfigOwner {
  ConfigOwner(this.id, this.object, this.listId);

  final String id;
  final PbxObject object;
  final String listId;

  String get name => object['name'] as String? ?? 'project';
  bool get isProject => object['isa'] == 'PBXProject';
}

/// Flavor-related operations on a parsed `project.pbxproj`.
class XcodeProject {
  XcodeProject(this.pbx);

  factory XcodeProject.parse(String source) {
    try {
      return XcodeProject(PbxProject.parse(source));
    } on PbxParseException catch (e) {
      throw ProjectError(
        'Could not parse $pbxprojFile: ${e.message} (offset ${e.offset}).',
      );
    } on FormatException catch (e) {
      throw ProjectError('Could not parse $pbxprojFile: ${e.message}.');
    }
  }

  final PbxProject pbx;

  String encode() => pbx.encode();

  /// The project and every native target, in that order.
  List<ConfigOwner> get configOwners {
    final project = pbx.rootObject;
    return [
      ConfigOwner(
        pbx.rootObjectId,
        project,
        project['buildConfigurationList']! as String,
      ),
      for (final id
          in (project['targets'] as List<Object>? ?? const []).cast<String>())
        if (pbx.object(id) case final t?
            when t['buildConfigurationList'] is String)
          ConfigOwner(id, t, t['buildConfigurationList']! as String),
    ];
  }

  /// The iOS app target (`Runner` in Flutter projects).
  ConfigOwner get appTarget {
    final apps = [
      for (final o in configOwners)
        if (o.object['productType'] == 'com.apple.product-type.application') o,
    ];
    if (apps.isEmpty) {
      throw ProjectError('No application target in $pbxprojFile.');
    }
    return apps.firstWhere((o) => o.name == 'Runner', orElse: () => apps.first);
  }

  List<String> configIds(String listId) =>
      ((pbx.object(listId)?['buildConfigurations'] as List<Object>?) ??
              const [])
          .cast<String>();

  /// Configuration name -> id for list [listId].
  Map<String, String> configsByName(String listId) => {
    for (final id in configIds(listId))
      if (pbx.object(id)?['name'] case final String name) name: id,
  };

  PbxObject config(String id) => pbx.object(id)!;

  Map<String, Object> buildSettings(String configId) =>
      config(configId)['buildSettings']! as Map<String, Object>;

  /// Configuration names on the app target, e.g. Debug, Release-dev.
  List<String> get appConfigurationNames =>
      configsByName(appTarget.listId).keys.toList();

  /// `PRODUCT_BUNDLE_IDENTIFIER` of the app target's Release configuration,
  /// if it is a literal.
  String? get bundleIdentifier {
    final configs = configsByName(appTarget.listId);
    final id =
        configs['Release'] ?? (configs.isEmpty ? null : configs.values.first);
    if (id == null) return null;
    final value = buildSettings(id)['PRODUCT_BUNDLE_IDENTIFIER'];
    return value is String && !value.contains(r'$') ? value : null;
  }

  /// Adds configuration [name] to list [listId] as a deep copy of [fromId]
  /// and returns its id. The new id is derived from the list and name so
  /// re-running yields the same project file.
  String copyConfiguration(String listId, String fromId, String name) {
    final source = config(fromId);
    final copy = _deepCopy(source) as PbxObject;
    copy['name'] = name;
    final id = pbx.newId('easy_flavor:config:$listId:$name');
    pbx.add(id, copy, comment: name);
    (pbx.object(listId)!['buildConfigurations']! as List<Object>).add(id);
    return id;
  }

  void removeConfiguration(String listId, String configId) {
    (pbx.object(listId)!['buildConfigurations']! as List<Object>).remove(
      configId,
    );
    pbx.remove(configId);
  }

  /// The file reference used as `baseConfigurationReference` by the app
  /// target's [configName], if any.
  String? baseConfigurationRef(String configName) {
    final id = configsByName(appTarget.listId)[configName];
    if (id == null) return null;
    return config(id)['baseConfigurationReference'] as String?;
  }

  /// Finds a file reference whose path's basename is [fileName].
  String? fileRefNamed(String fileName) {
    for (final e in pbx.ofType('PBXFileReference')) {
      final path = e.value['path'];
      if (path is String && p.posix.basename(path) == fileName) return e.key;
    }
    return null;
  }

  /// Adds a reference to [fileName] next to the existing reference
  /// [siblingId] (same group and directory) and returns its id. Returns the
  /// existing reference if there is one.
  String addSiblingFileRef(String siblingId, String fileName) {
    final existing = fileRefNamed(fileName);
    if (existing != null) return existing;

    final sibling = pbx.object(siblingId)!;
    final siblingPath = sibling['path']! as String;
    final dir = p.posix.dirname(siblingPath);
    final ref = <String, Object>{
      'isa': 'PBXFileReference',
      'lastKnownFileType': 'text.xcconfig',
      if (sibling.containsKey('name')) 'name': fileName,
      'path': dir == '.' ? fileName : '$dir/$fileName',
      'sourceTree': sibling['sourceTree'] ?? '<group>',
    };
    final id = pbx.newId('easy_flavor:fileref:$fileName');
    pbx.add(id, ref, comment: fileName);

    final group = groupContaining(siblingId);
    if (group != null) {
      final children = pbx.object(group)!['children']! as List<Object>;
      children.insert(children.indexOf(siblingId) + 1, id);
    }
    return id;
  }

  /// Removes a file reference and its group membership.
  void removeFileRef(String id) {
    final group = groupContaining(id);
    if (group != null) {
      (pbx.object(group)!['children']! as List<Object>).remove(id);
    }
    pbx.remove(id);
  }

  String? groupContaining(String childId) {
    for (final e in pbx.ofType('PBXGroup')) {
      final children = e.value['children'];
      if (children is List && children.contains(childId)) return e.key;
    }
    return null;
  }

  /// Id of the shell script phase named [name] on the app target, if any.
  String? scriptPhaseNamed(String name) {
    for (final id in _appBuildPhaseIds) {
      final phase = pbx.object(id);
      if (phase?['isa'] == 'PBXShellScriptBuildPhase' &&
          phase?['name'] == name) {
        return id;
      }
    }
    return null;
  }

  /// Adds (or updates) a shell script phase on the app target, right after
  /// its Resources phase.
  void setScriptPhase({
    required String name,
    required String script,
    List<String> inputPaths = const [],
    List<String> outputPaths = const [],
  }) {
    final phase = <String, Object>{
      'isa': 'PBXShellScriptBuildPhase',
      'buildActionMask': '2147483647',
      'files': <Object>[],
      'inputFileListPaths': <Object>[],
      'inputPaths': <Object>[...inputPaths],
      'name': name,
      'outputFileListPaths': <Object>[],
      'outputPaths': <Object>[...outputPaths],
      'runOnlyForDeploymentPostprocessing': '0',
      'shellPath': '/bin/sh',
      'shellScript': script,
    };
    final existing = scriptPhaseNamed(name);
    if (existing != null) {
      pbx.add(existing, phase, comment: name);
      return;
    }
    final id = pbx.newId('easy_flavor:phase:$name');
    pbx.add(id, phase, comment: name);
    final phases = _appBuildPhases;
    final resources = phases.indexWhere(
      (p) => pbx.object(p as String)?['isa'] == 'PBXResourcesBuildPhase',
    );
    phases.insert(resources == -1 ? phases.length : resources + 1, id);
  }

  void removeScriptPhase(String name) {
    final id = scriptPhaseNamed(name);
    if (id == null) return;
    _appBuildPhases.remove(id);
    pbx.remove(id);
  }

  /// The app target's build phase ids (the live list, for editing).
  List<Object> get _appBuildPhases =>
      appTarget.object['buildPhases']! as List<Object>;

  List<String> get _appBuildPhaseIds => _appBuildPhases.cast<String>();

  /// Sets build setting [key] on [configId], inserting new keys in
  /// alphabetical position as Xcode does.
  void setBuildSetting(String configId, String key, Object value) {
    final settings = buildSettings(configId);
    if (settings.containsKey(key)) {
      settings[key] = value;
      return;
    }
    final entries = settings.entries.toList();
    final at = entries.indexWhere((e) => e.key.compareTo(key) > 0);
    entries.insert(at == -1 ? entries.length : at, MapEntry(key, value));
    settings
      ..clear()
      ..addEntries(entries);
  }

  static Object _deepCopy(Object value) => switch (value) {
    final Map<String, Object> m => <String, Object>{
      for (final e in m.entries) e.key: _deepCopy(e.value),
    },
    final List<Object> l => <Object>[for (final v in l) _deepCopy(v)],
    _ => value,
  };
}
