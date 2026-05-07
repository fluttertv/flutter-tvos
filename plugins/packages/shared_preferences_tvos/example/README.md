# shared_preferences_example (tvOS)

Vendored from the official
[flutter/packages `shared_preferences/example`][upstream] with **no changes
to Dart code**. Only `pubspec.yaml` differs:

- `shared_preferences` is pulled from pub.dev (upstream)
- `shared_preferences_tvos` is pulled via `path: ../` (this repo)

## Running

```bash
flutter-tvos create .               # Scaffolds tvos/ project dir
flutter-tvos run -d <simulator_id>
```

[upstream]: https://github.com/flutter/packages/tree/main/packages/shared_preferences/shared_preferences/example
