import '../core/generator.dart';
import '../core/project_context.dart';
import 'ios_files.dart';
import 'xcode_project.dart';

/// Lowest iOS deployment target each Xcode major version accepts, where it
/// is above Flutter's template default (13.0). Xcode 27 rejects anything
/// below 15.0 ("range of supported deployment target versions is 15.0 to
/// 27.0.x").
const _minimumByXcode = {27: '15.0'};

String? minimumDeploymentTarget(int xcodeMajor) {
  String? result;
  for (final e in _minimumByXcode.entries) {
    if (xcodeMajor >= e.key) result = e.value;
  }
  return result;
}

/// `Xcode 27.0` -> 27.
int? parseXcodeMajor(String xcodebuildVersionOutput) => int.tryParse(
  RegExp(r'Xcode (\d+)').firstMatch(xcodebuildVersionOutput)?.group(1) ?? '',
);

/// Warns about deployment targets the installed Xcode will refuse to build.
List<Issue> deploymentTargetIssues(ProjectContext context, int xcodeMajor) {
  final minimum = minimumDeploymentTarget(xcodeMajor);
  final source = context.readOrNull(pbxprojFile);
  if (minimum == null || source == null) return const [];

  final xcode = XcodeProject.parse(source);
  final low = <String>{};
  for (final owner in xcode.configOwners) {
    for (final id in xcode.configIds(owner.listId)) {
      final value = xcode.buildSettings(id)['IPHONEOS_DEPLOYMENT_TARGET'];
      if (value is String && _less(value, minimum)) low.add(value);
    }
  }
  final pods = context.readOrNull(podfile);
  final platform = pods == null
      ? null
      : RegExp(
          r'''^\s*platform\s*:ios\s*,\s*['"]([\d.]+)['"]''',
          multiLine: true,
        ).firstMatch(pods)?.group(1);
  return [
    if (low.isNotEmpty)
      Issue(
        Severity.warning,
        'iOS deployment target ${low.join(', ')} is below $minimum, which Xcode '
        '$xcodeMajor requires; iOS builds will fail.',
        fix:
            'Set IPHONEOS_DEPLOYMENT_TARGET to $minimum (Runner project and '
            'target, all configurations) in Xcode.',
      ),
    if (platform != null && _less(platform, minimum))
      Issue(
        Severity.warning,
        "ios/Podfile uses platform :ios, '$platform', below Xcode $xcodeMajor's minimum $minimum.",
        fix: "Change it to platform :ios, '$minimum' and run `pod install`.",
      ),
  ];
}

bool _less(String a, String b) {
  final x = a.split('.').map(int.tryParse).toList();
  final y = b.split('.').map(int.tryParse).toList();
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? (x[i] ?? 0) : 0;
    final q = i < y.length ? (y[i] ?? 0) : 0;
    if (p != q) return p < q;
  }
  return false;
}
