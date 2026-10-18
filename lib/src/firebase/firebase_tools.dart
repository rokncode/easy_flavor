import 'dart:io';

import '../core/exceptions.dart';
import '../core/process_runner.dart';

/// Checks that the tools `flutterfire configure` needs are installed (and,
/// unless CI credentials are provided, that the Firebase CLI is logged in).
/// Throws [ToolError] with install instructions otherwise.
Future<void> requireFirebaseTools(
  ProcessRunner runner, {
  required bool ios,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final missing = <String>[];
  if (!await runner.isAvailable('firebase')) {
    missing.add(
      'Firebase CLI:   npm install -g firebase-tools   (or: curl -sL https://firebase.tools | bash)',
    );
  }
  if (!await runner.isAvailable('flutterfire')) {
    missing.add('FlutterFire CLI: dart pub global activate flutterfire_cli');
  }
  if (missing.isNotEmpty) {
    throw ToolError(
      'Firebase setup needs tools that are not installed.',
      hint:
          'Install them, make sure they are on your PATH, then re-run:\n'
          '  ${missing.join('\n  ')}',
    );
  }

  if (firebaseCredentialArgs(env).isEmpty) {
    final result = await runner.run('firebase', [
      'login:list',
      '--non-interactive',
    ]);
    final out = '${result.stdout}${result.stderr}';
    if (result.exitCode != 0 || out.contains('No authorized accounts')) {
      throw ToolError(
        'The Firebase CLI is not logged in.',
        hint:
            'Run `firebase login`, or on CI set FIREBASE_TOKEN or '
            'GOOGLE_APPLICATION_CREDENTIALS.',
      );
    }
  }

  // On macOS, flutterfire configures iOS through the Ruby xcodeproj gem
  // (easy_flavor reverts those Xcode edits and adds its own build phase,
  // but flutterfire fails without the gem).
  if (ios && Platform.isMacOS) {
    final result = await runner.run('ruby', ['-e', "require 'xcodeproj'"]);
    if (result.exitCode != 0) {
      throw ToolError(
        'flutterfire needs the Ruby "xcodeproj" gem to configure iOS.',
        hint:
            'Install it with `gem install xcodeproj` (or `sudo gem install '
            'xcodeproj` with the system Ruby). CocoaPods users already have it.',
      );
    }
  }
}

/// `--token` / `--service-account` for flutterfire from CI environment
/// variables.
List<String> firebaseCredentialArgs(Map<String, String> env) => [
  if (env['FIREBASE_TOKEN'] case final t? when t.isNotEmpty) '--token=$t',
  if (env['GOOGLE_APPLICATION_CREDENTIALS'] case final c? when c.isNotEmpty)
    '--service-account=$c',
];
