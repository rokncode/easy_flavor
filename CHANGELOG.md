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
- `create` runs `flutter create` and writes the flavor setup.
