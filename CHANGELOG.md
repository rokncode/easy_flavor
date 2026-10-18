## 0.1.0

Initial release.

- Commands: `create`, `init`, `add`, `remove`, `doctor`, `restore`.
- `easy_flavor.yaml` holds the whole setup; flags override it. Interactive
  prompts, or fully non-interactive for CI.
- Dart: `lib/flavors.dart` (`Flavor` enum and `FlavorConfig`),
  `lib/main_<flavor>.dart` entry points, `lib/main.dart` refactored into
  `runMainApp()` with a `main()` that starts the default flavor, and
  `flutter: default-flavor` in `pubspec.yaml`.
- Android: a managed `productFlavors` block for Groovy and Kotlin DSL with
  `applicationId` and `resValue` app names (or per-flavor `strings.xml` when
  `app_name` already exists), `@string/app_name` manifest label, and
  `src/<flavor>/` folders.
- iOS: a Dart `project.pbxproj` parser/writer that round-trips Xcode's
  formatting, `Debug/Release/Profile-<flavor>` configurations, per-flavor
  xcconfig files (bundle id, display name, CocoaPods include), shared
  schemes, `CFBundleDisplayName = $(APP_DISPLAY_NAME)`, and the Podfile
  configuration map.
- Firebase (`--firebase`): tool and login checks, `flutterfire configure`
  per flavor, `firebase_core`, Firebase initialisation per entry point, and
  an Xcode build phase that copies the flavor's `GoogleService-Info.plist`.
- Existing projects: git status check, backups in `.easy_flavor_backup/`,
  `restore`, `--dry-run` with diffs (`--verbose`), idempotent re-runs, and
  `init --merge` to adopt flavors the project already declares.
- IDE: VS Code `launch.json` entries and Android Studio run configurations.
- `doctor` validates the whole setup, including the iOS deployment target
  against the installed Xcode.
