# easy_flavor examples

## New app with three flavors

```sh
easy_flavor create my_app \
  --org com.company \
  --flavors dev,staging,prod \
  --bundle-ids dev=com.company.myapp.dev,staging=com.company.myapp.stg,prod=com.company.myapp \
  --app-names dev="MyApp Dev",staging="MyApp Stg",prod="MyApp"
cd my_app
flutter run --flavor dev -t lib/main_dev.dart
```

## Existing app

```sh
cd my_existing_app
easy_flavor init --flavors dev,prod --dry-run --verbose   # preview
easy_flavor init --flavors dev,prod
easy_flavor doctor
```

Already has hand-made flavors? Adopt them:

```sh
easy_flavor init --merge
```

## Firebase per flavor

```sh
easy_flavor init --firebase --firebase-projects dev=myapp-dev,prod=myapp-prod
```

## Change flavors later

```sh
easy_flavor add qa --app-name "MyApp QA"
easy_flavor remove qa
easy_flavor restore          # undo the last run
```

## Configuration file

[easy_flavor.yaml](easy_flavor.yaml) is a complete configuration. Put it at
your project root and run `easy_flavor init`.

## Using the flavor in Dart

```dart
import 'flavors.dart';

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    final config = FlavorConfig.instance;
    return Banner(
      message: config.name,
      location: BannerLocation.topEnd,
      child: Text(config.appTitle),
    );
  }
}
```
