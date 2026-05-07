# Authoring a tvOS Plugin

This guide walks you through creating a new `*_tvos` federated plugin. It is
the canonical recipe — every plugin in `packages/` follows it. If you are
adding one, copy an existing package (e.g. `path_provider_tvos`) and adjust.

## 1. Decide the shape

Two shapes are possible:

| Shape | Name | When |
|-------|------|------|
| **Port** | `<upstream>_tvos` | You're adding tvOS support to an existing pub.dev plugin (e.g. `url_launcher`). Federate via the upstream `*_platform_interface` package. |
| **Exclusive** | `tvos_<feature>` | You're exposing a tvOS-only API (Siri Remote, top-shelf extension, focus engine bridge). No platform interface to inherit. |

This guide focuses on **ports** — the common case. Exclusives skip the
`implements:` / `platform_interface` pieces.

## 2. Pick the upstream APIs

Before writing any code, read the upstream plugin's
`*_platform_interface/lib/<name>_platform_interface.dart`. List every
abstract method and decide for each:

- **Supported** — implement via a tvOS system API
- **Unsupported** — throw `UnsupportedError` with a reason

Document the decision in a table in your `README.md`. This is the single
most useful thing for downstream users.

Common tvOS "unsupported" reasons:

- No WebKit (affects `url_launcher`, `webview_flutter`, anything opening a browser)
- No haptics (affects `vibration`, haptic feedback)
- No camera / microphone (affects `camera`, `image_picker`)
- No Mail/Phone/SMS apps (affects `url_launcher` schemes, `share_plus`)
- No user-visible file system (affects `path_provider` Downloads/External)
- No in-process `fork()` (affects process-spawning plugins)

## 3. Scaffold the package

```bash
cd plugins/packages
mkdir -p <name>_tvos/{lib,tvos/Classes}
cd <name>_tvos
cp ../path_provider_tvos/LICENSE .
```

Then create the six files described below. Using `path_provider_tvos` as
a template and renaming is the fastest path.

### `pubspec.yaml`

```yaml
name: <name>_tvos
description: tvOS implementation of the <name> plugin.
version: 0.1.0
homepage: https://github.com/fluttertv/plugins/tree/main/packages/<name>_tvos
repository: https://github.com/fluttertv/plugins
issue_tracker: https://github.com/fluttertv/plugins/issues

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.3.0"

flutter:
  plugin:
    implements: <name>             # upstream name, e.g. "url_launcher"
    platforms:
      tvos:
        pluginClass: <Name>TvosPlugin         # Swift class, native registrar
        dartPluginClass: <Name>Tvos           # Dart class, Dart-side registrar

dependencies:
  flutter:
    sdk: flutter
  <name>_platform_interface: ^X.Y.Z

dev_dependencies:
  flutter_test:
    sdk: flutter
```

The `implements:` key is what makes this a federated implementation —
Flutter's plugin resolver picks it when a tvOS build depends on the
upstream. The `dartPluginClass` makes the Dart-side registrar fire at
isolate startup so channel methods route correctly even before the first
widget build.

### `lib/<name>_tvos.dart`

```dart
import 'package:flutter/services.dart';
import 'package:<name>_platform_interface/<name>_platform_interface.dart';

const String _channelName = 'plugins.fluttertv.dev/<name>_tvos';

class <Name>Tvos extends <Upstream>Platform {
  static const MethodChannel _channel = MethodChannel(_channelName);

  static void registerWith() {
    <Upstream>Platform.instance = <Name>Tvos();
  }

  // Override each method from the platform interface here.
  // For unsupported ones:
  //   throw UnsupportedError('<method> is not supported on tvOS');
}
```

Dart-3 class-modifier gotcha: if the platform interface uses `base class`,
your subclass must also carry a modifier (`base`, `final`, or `sealed`).
Example: `base class SharedPreferencesAsyncTvos extends SharedPreferencesAsyncPlatform`.
Without it, `pub get` fails with a type-system error.

### `tvos/Classes/<Name>TvosPlugin.swift`

```swift
import Flutter
import UIKit   // or Foundation-only, depending on the API

public class <Name>TvosPlugin: NSObject, FlutterPlugin {
  private static let channelName = "plugins.fluttertv.dev/<name>_tvos"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = <Name>TvosPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "<methodA>": // ...
      result(...)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
```

Guidelines:

- **Always match the channel name** on both sides exactly. Convention:
  `plugins.fluttertv.dev/<name>_tvos`.
- **Never import WebKit, CoreTelephony, MessageUI, AVCaptureDevice** — not
  available on tvOS. Compile will fail silently at the pod stage.
- **No `#if os(tvOS)` needed** — the pod only compiles against tvOS, so
  you can assume the target. If you share code with iOS (you probably
  shouldn't), then guard appropriately.
- **Use async completion for I/O** — `UIApplication.open`, file system
  writes, etc. Call `result(...)` inside the callback.

### `tvos/<name>_tvos.podspec`

Copy verbatim from `path_provider_tvos/tvos/path_provider_tvos.podspec`,
change `s.name`, `s.summary`, `s.description`. Do **not** change the
`xcconfig` block — it solves the "Flutter pod doesn't declare tvOS
support" problem by pointing at the app's pre-linked Flutter.framework.

Key invariants in the podspec:

- `s.platform = :tvos, '13.0'` — matches the engine deployment target
- No `s.dependency 'Flutter'` — would fail pod install
- `FRAMEWORK_SEARCH_PATHS = "${PODS_ROOT}/../Flutter"` — where
  `flutter-tvos build` stages Flutter.framework
- `OTHER_LDFLAGS = '-framework Flutter'` — links against it
- `TARGETED_DEVICE_FAMILY = '3'` — tvOS device family

### `README.md` and `CHANGELOG.md`

Copy and adapt `path_provider_tvos`'s files. The README **must** have:

- Install snippet (`pubspec.yaml` + `dependencies`)
- Capability table (what works, what's unsupported, why)
- Requirements section (tvOS 13.0+, `flutter-tvos` engine)

`CHANGELOG.md` starts with `## 0.1.0` and notes what's implemented/stubbed.

### `LICENSE`

Copy from `path_provider_tvos/LICENSE` (BSD-3-Clause, FlutterTV Authors).

## 4. Register the plugin in this repo

Edit `plugins/README.md`, add the new row to the Ports table.

## 5. Test against a real app

There is no isolated unit test harness for plugins in this repo yet.
Testing is app-driven:

```bash
# In tvos_demo/pubspec.yaml, add:
#   <name>:
#   <name>_tvos:
#     path: ../plugins/packages/<name>_tvos

cd tvos_demo
flutter-tvos build tvos --simulator --debug
flutter-tvos run -d <simulator_id>
```

Then exercise every method from Dart and confirm you see method-channel
activity in the native logs. For the "unsupported" methods, confirm the
`UnsupportedError` reaches Dart.

The CLI discovers your plugin via `flutter.plugin.platforms.tvos` — if
that key is missing, the plugin will silently not register, and you'll
get `MissingPluginException` at runtime.

## 6. Commit and push

From `plugins/`:

```bash
git add packages/<name>_tvos README.md
git commit -m "Add <name>_tvos"
git push
```

Make sure your git identity is set to your personal profile, not a CI
bot. CI will run `flutter pub get` + `flutter analyze` on the new package.

---

## Checklist (use this when porting)

- [ ] Package created under `plugins/packages/<name>_tvos/`
- [ ] `pubspec.yaml` has `implements:`, `pluginClass:`, `dartPluginClass:`
- [ ] Dart class extends the upstream platform interface
- [ ] Dart class has `registerWith()` static method
- [ ] Every platform-interface method is implemented or throws `UnsupportedError`
- [ ] Swift class is `NSObject, FlutterPlugin` with `register(with:)` and `handle(_:result:)`
- [ ] Channel name matches on both sides (`plugins.fluttertv.dev/<name>_tvos`)
- [ ] Podspec has `s.platform = :tvos, '13.0'`, no Flutter dependency, correct xcconfig
- [ ] README has capability table and unsupported-reason documentation
- [ ] `plugins/README.md` Ports table updated
- [ ] Tested end-to-end in `tvos_demo` — method channel fires, results return, errors propagate

## Common pitfalls

1. **Forgot `dartPluginClass`** — Dart-side registrar never runs, `MissingPluginException` at first call.
2. **Channel name mismatch** — Dart says `plugins.fluttertv.dev/foo_tvos`, Swift says `foo_tvos/channel`. Both sides must match exactly.
3. **Missing `base`/`final` class modifier** — Dart 3 type system rejects it, `pub get` fails.
4. **`s.dependency 'Flutter'`** — the Flutter pod has no tvOS variant, pod install dies.
5. **Imported a framework that isn't on tvOS** — `WebKit`, `SafariServices`, `MessageUI`, `CoreTelephony`, `AVKit`'s `AVPictureInPictureController`. Discover these at `pod install` or link time, not compile time.
6. **Forgot the upstream plugin in `dependencies`** — user has to add both `<name>` and `<name>_tvos` to their pubspec. Document this in the README install snippet.
7. **Empty `GeneratedPluginRegistrant.swift`** — means `ensureReadyForTvosTooling()` didn't find your plugin. Check `.flutter-plugins-dependencies` in the demo app for your plugin under the `plugins.tvos` key.

## Reference implementations

When unsure, compare against these in `packages/`:

- **Simple sync API** → `path_provider_tvos` (FileManager lookups)
- **Async I/O with delegate callback** → `url_launcher_tvos` (UIApplication.open completion)
- **Persistent key/value** → `shared_preferences_tvos` (UserDefaults, federated with `dartPluginClass`)
