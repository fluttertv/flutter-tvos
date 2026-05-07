# path_provider_tvos

The tvOS implementation of [`path_provider`][upstream], backed by
`NSFileManager`.

## Usage

Add both the upstream plugin and this implementation to your `pubspec.yaml`:

```yaml
dependencies:
  path_provider: ^2.1.0
  path_provider_tvos:
    git:
      url: https://github.com/fluttertv/plugins.git
      path: packages/path_provider_tvos
```

Then call the usual `path_provider` APIs:

```dart
final tmp = await getTemporaryDirectory();
final support = await getApplicationSupportDirectory();
```

## Supported directories

| Method | tvOS behaviour |
|--------|----------------|
| `getTemporaryDirectory` | `NSTemporaryDirectory()` — ephemeral |
| `getApplicationSupportDirectory` | `Library/Application Support/` — persistent (created if missing) |
| `getApplicationDocumentsDirectory` | `Documents/` — app-private on tvOS |
| `getApplicationCacheDirectory` | `Library/Caches/` — may be purged by the OS |
| `getLibraryDirectory` | `Library/` |
| `getDownloadsPath` | **Unsupported** |
| `getExternalStoragePath` / `getExternalCachePaths` | **Unsupported** |

## Storage caveats

Apple TV is not designed for large or long-lived on-device user data.
If you need persistence across purges, prefer
`shared_preferences_tvos` for small key-value data or CloudKit for
larger payloads.

## Requirements

- tvOS 13.0 or newer
- Built against the `flutter-tvos` engine

[upstream]: https://pub.dev/packages/path_provider
