import 'dart:io';

import 'package:easy_flavor/src/ios/deployment_target.dart';
import 'package:easy_flavor/src/ios/ios_files.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  test('parses xcodebuild -version', () {
    expect(parseXcodeMajor('Xcode 27.0\nBuild version 27A266a'), 27);
    expect(parseXcodeMajor('nope'), isNull);
  });

  test('minimum per Xcode version', () {
    expect(minimumDeploymentTarget(16), isNull);
    expect(minimumDeploymentTarget(27), '15.0');
    expect(minimumDeploymentTarget(28), '15.0');
  });

  test('Flutter template targets (13.0) fail on Xcode 27 only', () {
    final dir = copyFixture('fresh_kts');
    expect(deploymentTargetIssues(contextFor(dir), 16), isEmpty);
    final issues = deploymentTargetIssues(contextFor(dir), 27);
    expect(issues.single.message, contains('13.0 is below 15.0'));
  });

  test('checks the Podfile platform line', () {
    final dir = copyFixture('cocoapods');
    // The fixture's project already targets 15.0; only the Podfile is low.
    File('${dir.path}/$podfile').writeAsStringSync("platform :ios, '13.0'\n");
    final issues = deploymentTargetIssues(contextFor(dir), 27);
    expect(issues.single.message, contains("platform :ios, '13.0'"));
  });
}
