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

The generated `tvos/my_tvos_plugin.podspec` targets tvOS 13.0. One important rule — **do not** use `s.dependency 'Flutter'` because the Flutter pod does not declare tvOS support. Use `FRAMEWORK_SEARCH_PATHS` instead:

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
  s.platform         = :tvos, '13.0'

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
