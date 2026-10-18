# easy_flavor

Set up Flutter flavors (dev, staging, prod, ...) for Android and iOS in one
command, in new or existing projects, with optional Firebase per flavor.

> **Status:** early development. Commands parse options and print the plan;
> file generation is being implemented. The full guide lands before 0.1.0.

## Install

```sh
dart pub global activate easy_flavor
```

## Commands

```sh
# New project with flavors
easy_flavor create my_app --org com.company --flavors dev,staging,prod

# Add flavors to the project in the current directory
easy_flavor init --flavors dev,prod

# Change flavors later
easy_flavor add qa
easy_flavor remove qa

# Check the setup
easy_flavor doctor
```

Every command accepts `--dry-run` to preview changes, and
`--no-interactive` for CI.

Settings are stored in `easy_flavor.yaml` at the project root:

```yaml
flavors:
  dev:
    app_name: "MyApp Dev"
    android_id: com.company.myapp.dev
    ios_bundle_id: com.company.myapp.dev
  prod:
    app_name: "MyApp"
    android_id: com.company.myapp
    ios_bundle_id: com.company.myapp
firebase: false
```

## License

MIT
