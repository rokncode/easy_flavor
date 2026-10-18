import '../android/android_project.dart';
import '../config/easy_flavor_config.dart';
import '../ios/ios_project.dart';
import 'project_context.dart';

/// Flavors the project already declares in Gradle or Xcode outside
/// easy_flavor, with the values that can be read from them. Identifiers
/// shared by several flavors are left out, so distinct defaults are
/// generated instead.
PartialConfig detectExistingFlavorConfig(ProjectContext context) {
  final android = readAppGradleFile(context)?.existingFlavors ?? const [];
  final xcode = readXcodeProject(context);
  final iosNames = detectExistingIosFlavors(context);

  final names = [
    for (final f in android) f.name,
    for (final n in iosNames)
      if (!android.any((f) => f.name == n)) n,
  ];
  if (names.isEmpty) return const PartialConfig();

  String? iosId(String flavor) {
    if (xcode == null) return null;
    final configs = xcode.configsByName(xcode.appTarget.listId);
    final id = configs['Release-$flavor'] ?? configs['Debug-$flavor'];
    final value = id == null
        ? null
        : xcode.buildSettings(id)['PRODUCT_BUNDLE_IDENTIFIER'];
    return value is String && !value.contains(r'$') ? value : null;
  }

  final androidIds = {
    for (final f in android)
      if (f.applicationId != null) f.name: f.applicationId!,
  };
  final iosIds = <String, String>{for (final n in names) n: ?iosId(n)};
  return PartialConfig(
    hasFlavorList: true,
    flavors: [
      for (final n in names)
        PartialFlavor(
          name: n,
          appName: android.where((f) => f.name == n).firstOrNull?.appName,
          androidId: _unique(androidIds, n),
          iosBundleId: _unique(iosIds, n),
        ),
    ],
  );
}

String? _unique(Map<String, String> ids, String flavor) {
  final id = ids[flavor];
  if (id == null) return null;
  return ids.values.where((v) => v == id).length == 1 ? id : null;
}

/// [top] layered over [base]: [top]'s flavor list wins if it has one; per
/// flavor, [top]'s values win.
PartialConfig layerConfig(PartialConfig base, PartialConfig top) {
  final baseByName = {for (final f in base.flavors) f.name: f};
  final topByName = {for (final f in top.flavors) f.name: f};
  final names = top.hasFlavorList
      ? [for (final f in top.flavors) f.name]
      : [
          for (final f in base.flavors) f.name,
          for (final f in top.flavors)
            if (!baseByName.containsKey(f.name)) f.name,
        ];
  return PartialConfig(
    hasFlavorList: base.hasFlavorList || top.hasFlavorList,
    firebase: top.firebase ?? base.firebase,
    ide: top.ide ?? base.ide,
    mergeExisting: top.mergeExisting ?? base.mergeExisting,
    flavors: [
      for (final n in names)
        switch ((baseByName[n], topByName[n])) {
          (final b?, final t?) => b.merge(t),
          (final b?, null) => b,
          (null, final t?) => t,
          (null, null) => PartialFlavor(name: n),
        },
    ],
  );
}
