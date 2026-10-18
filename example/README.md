# easy_flavor examples

Create a new app with three flavors:

```sh
easy_flavor create my_app \
  --org com.company \
  --flavors dev,staging,prod \
  --bundle-ids dev=com.company.myapp.dev,staging=com.company.myapp.stg,prod=com.company.myapp \
  --app-names dev="MyApp Dev",staging="MyApp Stg",prod="MyApp"
```

Add flavors to an existing app (preview first):

```sh
cd my_existing_app
easy_flavor init --flavors dev,prod --dry-run
easy_flavor init --flavors dev,prod
```

Then run a flavor:

```sh
flutter run --flavor dev -t lib/main_dev.dart
```

See [easy_flavor.yaml](easy_flavor.yaml) for a sample config file.
