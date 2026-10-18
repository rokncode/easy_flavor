# easy_flavor

Set up Flutter flavors (dev, staging, prod, ...) for **Android and iOS** in one
command, in a **new or existing** project, with optional **Firebase per
flavor**.

```sh
easy_flavor init --flavors dev,staging,prod
flutter run --flavor dev -t lib/main_dev.dart
```

- Android `productFlavors` (Groovy or Kotlin DSL), app names, manifest label
- Xcode build configurations, schemes, xcconfig files, Podfile mapping
- Dart entry points and a `FlavorConfig` class
- Optional Firebase per flavor through the FlutterFire CLI
- VS Code and Android Studio run configurations
- Safe for existing projects: dry runs with diffs, git checks, backups,
  `restore`, idempotent re-runs, and merging with flavors you already have

## Contents

- [Install](#install)
- [Quick start](#quick-start)
- [Commands](#commands)
- [easy_flavor.yaml](#easy_flavoryaml)
- [What gets generated](#what-gets-generated)
- [Using flavors in Dart](#using-flavors-in-dart)
- [Firebase](#firebase)
- [Existing projects](#existing-projects)
- [CI](#ci)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)

## Install

```sh
dart pub global activate easy_flavor
```

Make sure `~/.pub-cache/bin` is on your `PATH`. Requirements:

- Dart 3.8 or newer (bundled with Flutter 3.32+)
- Flutter 3.22 or newer (for `default-flavor` support)
- For iOS: macOS with Xcode
- For Firebase: the [Firebase CLI](https://firebase.google.com/docs/cli) and
  the [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup)

## Quick start

**New project:**

```sh
easy_flavor create my_app --org com.company --flavors dev,staging,prod
cd my_app
flutter run --flavor dev -t lib/main_dev.dart
```

**Existing project** (run from the project root):

```sh
easy_flavor init --flavors dev,prod --dry-run --verbose   # preview with diffs
easy_flavor init --flavors dev,prod
```

Plain `flutter run` (no `--flavor`/`-t`) keeps working and starts the default
flavor (the production one: `prod`, `production`, `release` or `live`,
otherwise the first).

## Commands

Options available on every command:

| Option | Description |
| --- | --- |
| `--dry-run` | Print the planned changes (and commands) without writing anything. |
| `-v`, `--verbose` | Detailed output; with `--dry-run`, a unified diff of every file. |
| `--[no-]interactive` | Prompt for missing values. Off automatically when not in a terminal. |
| `-C`, `--project-dir <path>` | Project root (for `create`: the parent directory). |
| `--version` | Print the version. |

### `create`

Runs `flutter create`, then sets up flavors.

```sh
easy_flavor create my_app --org com.company \
  --flavors dev,staging,prod \
  --bundle-ids dev=com.company.myapp.dev,staging=com.company.myapp.stg,prod=com.company.myapp \
  --app-names dev="MyApp Dev",staging="MyApp Stg",prod="MyApp" \
  --firebase --firebase-projects dev=myapp-dev,staging=myapp-stg,prod=myapp-prod
```

| Option | Description |
| --- | --- |
| `--org` | Reverse-DNS organization (default `com.example`). |
| `--description` | pubspec description. |
| `--platforms` | `android`, `ios` (default both). |
| `-f`, `--flavors` | Flavor names, e.g. `dev,staging,prod`. Defaults to `dev,staging,prod` (asked interactively). |
| `--bundle-ids` | `flavor=id` pairs used for Android and iOS. |
| `--android-ids`, `--ios-bundle-ids` | Per-platform ids (override `--bundle-ids`). |
| `--app-names` | `flavor=name` pairs. Quote names with spaces. |
| `--[no-]firebase` | Configure Firebase per flavor. |
| `--firebase-projects` | `flavor=project-id` pairs. |
| `--ide` | `vscode`, `android-studio` (default both). |

Default ids are `<org>.<app>.<flavor>`; the production flavor gets
`<org>.<app>`. Default names are `<App Name> <Flavor>`, and the production
flavor gets `<App Name>`.

### `init`

Adds flavors to an existing project. Takes the same flavor options as
`create`, plus:

| Option | Description |
| --- | --- |
| `--[no-]merge` | The project already has flavors: adopt them instead of stopping (asked interactively). |
| `--force` | Continue even if git has uncommitted changes. |

```sh
easy_flavor init --flavors dev,prod --firebase
```

The existing Android `applicationId` and iOS bundle identifier become the
production ids; other flavors get a `.<flavor>` suffix. Running `init` again
re-applies `easy_flavor.yaml` and changes nothing if the project is up to
date, so it is also how you apply edits you make to the YAML file.

### `add` / `remove`

```sh
easy_flavor add qa --app-name "MyApp QA" --bundle-id com.company.myapp.qa
easy_flavor remove qa
```

`add` options: `--app-name`, `--bundle-id`, `--android-id`,
`--ios-bundle-id`, `--firebase-project`, `--force`. Without them, values are
derived from the production flavor. `remove` options: `-y`/`--yes` (no
confirmation), `--force`.

`remove` deletes everything easy_flavor generated for the flavor (Gradle and
Xcode entries, xcconfig files, scheme, entry point, run configurations).
Files you added (icons, `google-services.json`, `GoogleService-Info.plist`)
are kept.

### `doctor`

```sh
easy_flavor doctor
```

Checks that Gradle flavors, Xcode configurations, schemes, xcconfig files,
the Podfile map, Info.plist, Dart entry points and Firebase files all match
`easy_flavor.yaml`. It also warns when the iOS deployment target is below
what the installed Xcode accepts. Exits non-zero if it finds errors.

### `restore`

Every run that changes an existing project first backs up the files it
touches to `.easy_flavor_backup/<timestamp>/` (and adds that folder to
`.gitignore`).

```sh
easy_flavor restore --list        # list backups
easy_flavor restore               # undo the latest run
easy_flavor restore 20261018-153012
```

## easy_flavor.yaml

All settings live in `easy_flavor.yaml` at the project root, so the setup is
reproducible. Commands read it; flags override it; the file is updated after
each run.

```yaml
flavors:
  dev:
    app_name: "MyApp Dev"
    android_id: com.company.myapp.dev
    ios_bundle_id: com.company.myapp.dev
    firebase_project: myapp-dev      # only used with firebase: true
  prod:
    app_name: "MyApp"
    android_id: com.company.myapp
    ios_bundle_id: com.company.myapp
    firebase_project: myapp-prod
firebase: true
ide: [vscode, android-studio]
merge_existing: true                 # written by `init --merge`
```

Per-flavor fields are optional; missing ones get the defaults described
above. Flavor names must be lowerCamelCase identifiers (`dev`, `staging`,
`qa2`) and cannot be Gradle/Dart reserved words (`main`, `test`, `debug`,
`release`, `profile`, `class`, ...).

## What gets generated

| Area | Files |
| --- | --- |
| Dart | `lib/flavors.dart`, `lib/main_<flavor>.dart`; `lib/main.dart` refactored (see below); `flutter: default-flavor:` in `pubspec.yaml` |
| Android | A marked `productFlavors` block in `android/app/build.gradle(.kts)` with `applicationId` and `resValue` `app_name`; `android:label="@string/app_name"` in `AndroidManifest.xml`; `android/app/src/<flavor>/` |
| iOS | `Debug-`, `Release-`, `Profile-<flavor>` configurations in `ios/Runner.xcodeproj`; `ios/Flutter/<Config>-<flavor>.xcconfig` with `PRODUCT_BUNDLE_IDENTIFIER`, `APP_DISPLAY_NAME`, `EASY_FLAVOR`; a shared scheme per flavor; `CFBundleDisplayName = $(APP_DISPLAY_NAME)` in Info.plist; the `ios/Podfile` configuration map (if you use CocoaPods) |
| Firebase | `lib/firebase/firebase_options_<flavor>.dart`, `android/app/src/<flavor>/google-services.json`, `ios/config/<flavor>/GoogleService-Info.plist`, and an Xcode build phase that copies the right plist |
| IDE | `.vscode/launch.json` entries, `.run/<flavor>.run.xml` (Android Studio) |

easy_flavor edits files precisely rather than overwriting them:

- **Gradle**: only the block between `// easy_flavor:begin` and
  `// easy_flavor:end` is managed. Both Groovy and Kotlin DSL are supported.
- **Xcode**: `project.pbxproj` is read and written with a real parser that
  reproduces Xcode's formatting, so diffs only show actual changes. New
  object ids are deterministic.
- **main.dart** is never deleted. Its `main()` is renamed to `runMainApp()`,
  and a new `main()` delegates to the default flavor's entry point:

  ```dart
  import 'main_prod.dart' as default_flavor; // easy_flavor:default-flavor

  // Plain `flutter run` (without -t) starts the default flavor.
  Future<void> main() => default_flavor.main();

  void runMainApp() {
    runApp(const MyApp());
  }
  ```

## Using flavors in Dart

Each entry point calls `FlavorConfig.init(Flavor.<name>)` before
`runMainApp()`:

```dart
import 'flavors.dart';

final config = FlavorConfig.instance;
Text(config.appTitle);
if (config.flavor == Flavor.dev) showDebugBanner();
final api = Uri.parse(config.baseUrl);
```

`lib/flavors.dart` is regenerated when flavors change, but your edits to the
`baseUrl:` lines are kept (one line per flavor, a constant expression). Put
other per-flavor settings in your own code with a `switch` on
`FlavorConfig.instance.flavor`.

## Firebase

1. Install and log in:

   ```sh
   npm install -g firebase-tools       # or: curl -sL https://firebase.tools | bash
   dart pub global activate flutterfire_cli
   firebase login
   ```

   On macOS, FlutterFire also needs the Ruby `xcodeproj` gem
   (`gem install xcodeproj`; CocoaPods users already have it).

2. Create one Firebase project per flavor (or reuse one for several).

3. Run:

   ```sh
   easy_flavor init --firebase --firebase-projects dev=myapp-dev,prod=myapp-prod
   ```

   Without `--firebase-projects`, you are asked for each flavor's project id
   (or set `firebase_project` in `easy_flavor.yaml`).

For each flavor, easy_flavor runs:

```sh
flutterfire configure --yes --project=<id> \
  --out=lib/firebase/firebase_options_<flavor>.dart \
  --android-package-name=<android_id> --android-out=android/app/src/<flavor>/google-services.json \
  --ios-bundle-id=<ios_bundle_id> --ios-out=ios/config/<flavor>/GoogleService-Info.plist \
  --ios-build-config=Release-<flavor>
```

It also adds `firebase_core` to `pubspec.yaml`, and makes each
`main_<flavor>.dart` call `Firebase.initializeApp` with that flavor's
options. On iOS, a build phase named
`[easy_flavor] Copy GoogleService-Info.plist` copies
`ios/config/$(EASY_FLAVOR)/GoogleService-Info.plist` into the app, so builds
don't need the FlutterFire CLI.

FlutterFire changes the Xcode project itself (through Ruby). easy_flavor
undoes those edits and uses its own build phase, so the project file stays
under easy_flavor's control. FlutterFire's Gradle changes (the
google-services plugin) are kept.

Re-running `init` only calls `flutterfire configure` again for flavors whose
project or ids changed, or whose files are missing. Delete a flavor's options
file to force it.

## Existing projects

Before changing an existing project, easy_flavor:

- **Checks git.** Uncommitted changes stop the run unless you confirm (or
  pass `--force`), so its changes are easy to review. Outside git you get a
  warning.
- **Backs up** every file it will touch to `.easy_flavor_backup/<timestamp>/`.
  Use `easy_flavor restore` to undo.
- **Shows the plan** first. Use `--dry-run --verbose` to see a diff without
  writing anything.

### Projects that already have flavors

If your Gradle file or Xcode project already declares flavors, `init` stops
and offers to merge (`--merge` on CI):

```sh
easy_flavor init --merge --dry-run --verbose
easy_flavor init --merge
```

When merging, easy_flavor:

- Imports your flavors' names, ids and app names into `easy_flavor.yaml`.
  An id shared by several flavors is not imported, so each flavor gets its
  own id; check the table before confirming.
- Leaves your Gradle `productFlavors` block alone. Its own block goes after
  yours, in your flavor dimension, and sets `applicationId` (clearing any
  `applicationIdSuffix`) and `app_name`. `buildConfigField`, signing and
  other settings in your block keep working.
- Leaves your Xcode configurations' xcconfig files alone and sets
  `PRODUCT_BUNDLE_IDENTIFIER`, `APP_DISPLAY_NAME` and `EASY_FLAVOR` on them.
- Keeps your own `lib/main_<flavor>.dart` files and existing schemes.

## CI

Prompts are disabled automatically when there is no terminal (or with
`--no-interactive`), so pass everything as flags or in `easy_flavor.yaml`:

```sh
easy_flavor init --flavors dev,prod --force
easy_flavor doctor
```

For Firebase on CI, set `FIREBASE_TOKEN` (from `firebase login:ci`) or
`GOOGLE_APPLICATION_CREDENTIALS` (service account JSON). easy_flavor skips
the login check and passes them on to FlutterFire.

## Troubleshooting

**iOS build fails: "deployment target ... is set to 13.0, but the range of
supported deployment target versions is 15.0 to ..."**
Xcode 27 and newer need iOS 15.0+, but older Flutter templates use 13.0.
`easy_flavor doctor` reports this. Set `IPHONEOS_DEPLOYMENT_TARGET` to 15.0
for the Runner project and target (all configurations), and in the Podfile
use `platform :ios, '15.0'`.

**Android: "Product Flavor ... contains custom resource values, but the
feature is disabled"**
Newer Android Gradle Plugin versions disable `resValue`. The generated block
enables it (`buildFeatures { resValues = true }`). Re-run `easy_flavor init`
if you removed it.

**Android: "Duplicate resources" for `app_name`**
This means `app_name` is defined in `main/res/values/strings.xml`. easy_flavor
detects that and writes `android/app/src/<flavor>/res/values/strings.xml`
instead of using `resValue`. Re-run `easy_flavor init` if you added the
string later.

**"Runner.xcscheme not found"**
Flavor schemes are copies of the shared Runner scheme. In Xcode, open
Product > Scheme > Manage Schemes and tick **Shared** for Runner (or copy
`ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` from a fresh
`flutter create`).

**CocoaPods: "did not set the base configuration of your project"**
A warning about the plain `Profile` configuration using
`Flutter/Release.xcconfig` comes from the Flutter template and is unrelated
to flavors. The flavor configurations include their own Pods xcconfig.

**`flutterfire` fails with "cannot load such file -- xcodeproj"**
Install the gem: `gem install xcodeproj`.

**"Stopped because of uncommitted changes"**
Commit or stash, or pass `--force`.

**Something went wrong.**
Run `easy_flavor restore` to undo the last run, then `easy_flavor doctor`.
Please [open an issue](https://github.com/rokncode/easy_flavor/issues) with
the `--dry-run --verbose` output.

## Limitations

- Android and iOS only (no macOS, web, Windows or Linux flavors).
- The iOS app target is the Flutter `Runner` target (or, without one, the
  first application target).
- Merging works with a single Gradle flavor dimension.
- A flavor declared in your own Gradle `productFlavors` (merge mode) must be
  deleted there before `easy_flavor remove` can remove it.
- `--app-names` splits on commas, so app names containing commas must be set
  in `easy_flavor.yaml`. In iOS display names, `$(...)` is expanded by
  Xcode.
- FlutterFire writes `GoogleService-Info.plist` only on macOS; run Firebase
  setup on a Mac for iOS.
- FlutterFire's Crashlytics debug-symbol upload script is not kept, because
  easy_flavor restores the Xcode project after FlutterFire runs. Add it
  manually if you use Crashlytics.

## License

MIT
