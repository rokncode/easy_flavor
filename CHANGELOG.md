## 0.1.0-dev

- Initial scaffold: `create`, `init`, `add`, `remove` and `doctor` commands,
  `easy_flavor.yaml` config with flag overrides, `--dry-run` planning.
- Dart: generates `lib/flavors.dart` (`Flavor` enum + `FlavorConfig`) and
  `lib/main_<flavor>.dart`; refactors `main()` into `runMainApp()` while
  keeping `lib/main.dart` as the default-flavor entry point; sets
  `flutter: default-flavor` in pubspec.yaml.
- Android: managed `productFlavors` block for Groovy and Kotlin DSL,
  `resValue` app names (or per-flavor `strings.xml` when `app_name` already
  exists), `@string/app_name` manifest label, `src/<flavor>/` folders.
- IDE: VS Code `launch.json` entries and Android Studio `.run/` configs.
- iOS: Dart `project.pbxproj` parser/writer (byte-identical round trips),
  `Debug/Release/Profile-<flavor>` configurations in every configuration
  list, per-configuration xcconfig files (bundle id, display name, CocoaPods
  include), shared schemes per flavor, `CFBundleDisplayName =
  $(APP_DISPLAY_NAME)`, and the Podfile configuration map.
- Firebase (`--firebase`): checks for the Firebase and FlutterFire CLIs
  (with install instructions) and login (or CI credentials), runs
  `flutterfire configure` per flavor into `lib/firebase/`,
  `android/app/src/<flavor>/` and `ios/config/<flavor>/`, adds
  `firebase_core`, initialises Firebase in each entry point, and copies the
  flavor's `GoogleService-Info.plist` with an easy_flavor Run Script phase
  (FlutterFire's own Xcode edits are reverted). Per-flavor Firebase projects
  via `--firebase-projects` or `firebase_project` in easy_flavor.yaml.
- `lib/main.dart`'s `main()` delegates to the default flavor's entry point.
- `doctor` warns when the iOS deployment target is below what the installed
  Xcode supports.
- Safety for existing projects: git status check (uncommitted changes need
  confirmation or `--force`), backups of every touched file in
  `.easy_flavor_backup/<timestamp>/` (added to `.gitignore`), and
  `easy_flavor restore [<backup>]` / `restore --list` to undo a run.
- `init`, `add` and `remove` now write changes.
- `init --merge` adopts flavors the project already declares: their names
  and ids are imported into easy_flavor.yaml (`merge_existing: true`),
  Gradle flavors are configured on top of the project's own
  `productFlavors` (same dimension, custom settings kept), and existing
  Xcode configurations get the flavor values directly.
- `--dry-run --verbose` prints a unified diff of every file.
- `create` runs `flutter create` and writes the flavor setup.
