# shared_preferences_tvos

The tvOS implementation of [`shared_preferences`][upstream], backed by
`NSUserDefaults.standard`.

This is an endorsable federated implementation — apps that depend on
`shared_preferences` and this package will automatically route calls through
`NSUserDefaults` on tvOS.

## Usage

Add both the upstream plugin and this implementation to your `pubspec.yaml`:

```yaml
dependencies:
  shared_preferences: ^2.2.0
  shared_preferences_tvos:
    git:
      url: https://github.com/fluttertv/plugins.git
      path: packages/shared_preferences_tvos
```

Then use `SharedPreferences` normally:

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('user.name', 'Ada');
print(prefs.getString('user.name'));
```

## Storage details

- Keys are namespaced with the `flutter.` prefix (set by the upstream plugin)
- Values are written to the app container's `NSUserDefaults`
- `clear()` removes only keys under the `flutter.` prefix, matching the
  `shared_preferences_foundation` behaviour on iOS/macOS

## Requirements

- tvOS 13.0 or newer
- Built against the `flutter-tvos` engine

[upstream]: https://pub.dev/packages/shared_preferences
