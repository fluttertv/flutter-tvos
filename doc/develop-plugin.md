# Writing a tvOS plugin

This guide covers how to create a Flutter plugin that exposes native tvOS functionality to Dart code.

## Create a plugin package

```sh
flutter-tvos create --template=plugin my_tvos_plugin
cd my_tvos_plugin
```

The generated package contains:

```
my_tvos_plugin/
├── lib/
│   └── my_tvos_plugin.dart        # Dart API
├── tvos/
│   ├── Classes/
│   │   └── MyTvosPlugin.swift     # Swift implementation
│   └── my_tvos_plugin.podspec     # CocoaPods spec
├── example/                       # Example app
└── pubspec.yaml
```

The `pubspec.yaml` declares the tvOS platform:

```yaml
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: MyTvosPlugin
```

## Implement the plugin

### 1. Define the Dart API

Open `lib/my_tvos_plugin.dart` and define your public API:

```dart
class MyTvosPlugin {
  static const MethodChannel _channel = MethodChannel('my_tvos_plugin');

  static Future<String?> getPlatformVersion() async {
    return await _channel.invokeMethod<String>('getPlatformVersion');
  }
}
```

### 2. Implement in Swift

Open `tvos/Classes/MyTvosPlugin.swift`:

```swift
import Flutter

public class MyTvosPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "my_tvos_plugin",
      binaryMessenger: registrar.messenger()
    )
    let instance = MyTvosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("tvOS \(UIDevice.current.systemVersion)")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

### 3. CocoaPods podspec

The generated `tvos/my_tvos_plugin.podspec` targets tvOS 15.0. One important rule — **do not** use `s.dependency 'Flutter'` because the Flutter pod does not declare tvOS support. Use `FRAMEWORK_SEARCH_PATHS` instead:

```ruby
Pod::Spec.new do |s|
  s.name             = 'my_tvos_plugin'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter plugin for tvOS.'
  s.homepage         = 'https://fluttertv.dev'
  s.license          = { :type => 'BSD-3-Clause' }
  s.author           = { 'FlutterTV' => 'info@fluttertv.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :tvos, '15.0'

  # Use FRAMEWORK_SEARCH_PATHS instead of s.dependency 'Flutter'
  s.xcconfig = {
    'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"'
  }
end
```

## tvOS constraints

tvOS is more restricted than iOS. Keep these in mind when writing plugins:

| Feature | iOS | tvOS |
|---------|-----|------|
| WebKit / WKWebView | ✅ | ❌ Not available |
| Clipboard (UIPasteboard) | ✅ | ❌ Not available |
| Haptics (UIFeedbackGenerator) | ✅ | ❌ Not available |
| Status bar | ✅ | ❌ Not available |
| Camera / microphone | ✅ | ❌ Not available |
| Touch input | UITouch | ❌ Use UIPress (Siri Remote) |
| Game controllers | Optional | ✅ GameController.framework |
| Media playback | AVFoundation | ✅ AVFoundation |

Use `#if os(tvOS)` guards for any tvOS-specific Swift code:

```swift
#if os(tvOS)
  // tvOS-specific implementation
#else
  result(FlutterError(code: "UNSUPPORTED", message: "Not supported on this platform", details: nil))
#endif
```

## FFI plugins

For plugins that wrap a native C library, set `ffiPlugin: true` in `pubspec.yaml`:

```yaml
flutter:
  plugin:
    platforms:
      tvos:
        ffiPlugin: true
```

FFI plugins are distributed as CocoaPods and loaded via `DynamicLibrary.process()` — they are **not** added to the plugin registrant.

## Code assets from build hooks

A package can also ship its native library through a Dart build hook (`hook/build.dart`) and call it with `@Native`, as on other platforms. flutter-tvos runs the hooks when Dart data assets are enabled (`flutter config --enable-dart-data-assets`, off by default) and native assets are enabled (`--enable-native-assets`, on by default; turning it off discards code assets with a warning), and installs the code assets they return the way Flutter does for iOS: each dynamic library becomes `<name>.framework` in the app's `Frameworks/`, with the install name `@rpath/<name>.framework/<name>`, and is listed in `NativeAssetsManifest.json`.

What a tvOS hook has to know:

- **It is told `target_os: tvos` and `arm64`.** With `package:code_assets` 2.x, `input.config.code.targetOS == OS.fromString('tvos')`. There is no tvOS sub-config: no deployment target, and no device or simulator.
- **It has to choose device or simulator itself.** A library is linked for `appletvos` or `appletvsimulator`, and dyld refuses the other. A device build and a simulator build give a hook the same input, and the hooks cache serves both the library it built first. Choose by a means of your own, for example a user-define the app sets in its `pubspec.yaml`, which reruns the hook when it changes:

  ```yaml
  hooks:
    user_defines:
      my_package:
        tvos_sdk: appletvsimulator   # or appletvos
  ```

  The build reads the platform out of every library before installing it and fails, naming the library, if it is for the other SDK, rather than ship an app that fails at its first `@Native` call.
- **`native_toolchain_c` cannot build for tvOS** (0.19): its `CBuilder` has no file-name rules or target flags for an OS it does not know. Invoke `xcrun clang -target arm64-apple-tvos15.0[-simulator] -isysroot $(xcrun --sdk <sdk> --show-sdk-path) -dynamiclib` yourself.
- **Link hooks do not run.** A code asset has to be added for the app bundle by the build hook.
- **A hook that cannot read `tvos`** (one resolving `code_assets` 1.x) is retried as the iOS family so its data assets still flow; the code assets of that retry are iPhone libraries and are not installed.

The "Embed Flutter.framework" build phase of the Runner target embeds the libraries and signs them with the app's identity, and removes ones an earlier build embedded that the app no longer has. Projects created with 1.9.0 through 1.12.0 have a phase without that step; if it is unchanged, the next build updates it in `tvos/Runner.xcodeproj/project.pbxproj` and says so. If it was edited (or the project predates the phase), simulator and `--no-codesign` builds embed the libraries after the Xcode build with a warning, and a signed device build stops and prints the lines to add to the phase: embedding after Xcode has signed the app would break its signature. Re-creating `tvos/` also works.

Turning either flag on or off takes effect on the next build; no `flutter-tvos clean` is needed.

## Run the example app

```sh
cd example
flutter-tvos devices
flutter-tvos run -d <simulator_id>
```

## Publish the plugin

```sh
dart pub publish --dry-run
dart pub publish
```

See [Flutter Docs: Publishing packages](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#publish) for details.
