# path_provider_example (tvOS)

Vendored from the official
[flutter/packages `path_provider/example`][upstream] with **no changes to
Dart code**. Only `pubspec.yaml` differs:

- `path_provider` is pulled from pub.dev (upstream)
- `path_provider_tvos` is pulled via `path: ../` (this repo)

On tvOS, buttons for external storage, external caches, and downloads
are disabled — those APIs throw `UnsupportedError` at the platform layer,
matching the upstream behaviour for non-Android / non-desktop targets.

## Running

```bash
flutter-tvos create .               # Scaffolds tvos/ project dir
flutter-tvos run -d <simulator_id>
```

[upstream]: https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider/example
