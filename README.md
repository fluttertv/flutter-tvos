# flutter-tvos

A Flutter toolchain for building and running Flutter apps on **Apple TV (tvOS)**.

`flutter-tvos` is a drop-in CLI companion to the Flutter SDK — same commands, same hot reload, same DevTools — targeting tvOS instead of iOS.

> **macOS only.** Xcode is required.

## Installation

```sh
git clone https://github.com/fluttertv/flutter-tvos.git
cd flutter-tvos
export PATH="$PATH:$PWD/bin"
flutter-tvos precache
flutter-tvos doctor
```

See [Getting started](doc/get-started.md) for the full setup guide.

## Usage

`flutter-tvos` substitutes the original [`flutter`](https://docs.flutter.dev/reference/flutter-cli) CLI command.

```sh
# Check the installed tooling and list all connected devices.
flutter-tvos doctor -v
flutter-tvos devices

# Create a new app project.
flutter-tvos create my_tv_app
cd my_tv_app

# Build and run on a tvOS Simulator.
flutter-tvos run -d <simulator_id>

# Build and run on a physical Apple TV in release mode.
flutter-tvos run -d <device_id> --release
```

- See [Supported commands](doc/commands.md) for all available commands and usage examples.
- See [Getting started](doc/get-started.md) to create your first app and try **hot reload**.
- To **update** flutter-tvos, run `git pull` in the cloned directory.

## Platform identity & limitations

flutter-tvos treats tvOS as its **own platform** at both the build and runtime layers. Read this section before adding dependencies to an existing iOS codebase — the separation has real consequences for plugins and cross-platform apps.

### Runtime identity

On a tvOS build, the Dart VM reports:

| API | Value on tvOS | Value on iOS |
|---|---|---|
| `Platform.operatingSystem` | `"tvos"` | `"ios"` |
| `Platform.isIOS` | **`true`** | `true` |
| `Platform.isTvOS` | `true` | `false` |
| `defaultTargetPlatform` | `TargetPlatform.iOS` | `TargetPlatform.iOS` |

**`Platform.isIOS` is `true` on tvOS.** This is intentional: tvOS is an iOS-family operating system (same Darwin kernel, same UIKit, same Metal, same Foundation). Upstream Flutter widgets that check `Platform.isIOS` or switch on `defaultTargetPlatform` render correctly on Apple TV without any framework modification — Cupertino styling, SF font, iOS page transitions all work out of the box.

The Flutter SDK checkout that flutter-tvos uses is bit-for-bit identical to upstream. **We do not patch Flutter.** All tvOS identity lives in the engine artifact (Dart VM) and the CLI.

### Plugin isolation (no iOS fallback)

tvOS and iOS have completely separate plugin ecosystems:

- **tvOS builds** only discover plugins that declare `flutter.plugin.platforms.tvos` in their pubspec. Plugins with only `ios:` (i.e., most Flutter plugins on pub.dev today) are silently ignored on tvOS.
- **iOS builds** (stock Flutter) only discover plugins that declare `flutter.plugin.platforms.ios`. Plugins with only `tvos:` are silently ignored — stock Flutter doesn't recognize the `tvos` key.

Every plugin with native code needs a `*_tvos` federated implementation to work on Apple TV. This is the same rule enforced by flutter-tizen, flutter-elinux, and flutter-webos. Currently shipped: `shared_preferences_tvos`. Community-contributed federated implementations are the path forward.

### Writing cross-platform apps (iOS + Android + tvOS)

If your app already targets iOS/Android and you're adding tvOS support, keep these patterns in mind:

**1. Don't rely on `Platform.isIOS` alone for "phone/tablet iOS" logic.** It's also `true` on Apple TV. Refine with `Platform.isTvOS`:

```dart
// ❌ Will run on Apple TV too
if (Platform.isIOS) {
  showTouchGestureHint();
}

// ✅ Only iPhone / iPad
if (Platform.isIOS && !Platform.isTvOS) {
  showTouchGestureHint();
}
```

**2. Exclude tvOS from iOS-only code paths** when iOS-specific behavior makes no sense on a TV (touch gestures, haptics, status-bar tweaks, keyboard dismissal, clipboard, web views, camera, etc.):

```dart
import 'package:flutter_tvos/flutter_tvos.dart';

if (FlutterTvosPlatform.isIos) {                  // iPhone / iPad only (NOT tvOS)
  // Use iPhone-specific plugin
}

if (FlutterTvosPlatform.isTvos) {                 // Apple TV only
  // 10-foot UI, focus-based navigation, D-pad
}

if (FlutterTvosPlatform.isAppleMobile) {          // iPhone, iPad, OR Apple TV
  // Any iOS-family OS (UIKit + Foundation present)
}
```

**3. Build focus-first on tvOS.** Apple TV has no touch — users navigate with the Siri Remote via the system focus engine. Apply `Focus` / `FocusableActionDetector` widgets and design for D-pad traversal.

**4. Plugin dependencies:** if your iOS app uses `url_launcher`, `shared_preferences`, `path_provider`, etc., each one needs a tvOS federated package (`url_launcher_tvos`, `shared_preferences_tvos`, …) or your tvOS build will compile but calls will throw `MissingPluginException` at runtime. Before porting, audit your `pubspec.yaml` for plugins with native iOS code and check whether a `_tvos` variant exists.

**5. `ios/` and `tvos/` directories are independent.** Running `flutter-tvos create` scaffolds a separate `tvos/` project sibling to `ios/`. They have their own Podfile, their own Info.plist, their own AppDelegate. Do not symlink or share them — the build settings diverge (tvOS SDK, UIKit-without-WebKit, no haptics/clipboard/status bar, etc.).

**6. Conditional imports** in pure-Dart packages — use `dart.library.io` guards if you publish a package that should behave differently on tvOS:

```dart
import 'package:my_package/io_stub.dart'
    if (dart.library.io) 'package:my_package/io_impl.dart';
```

Then inside `io_impl.dart`, branch on `Platform.isTvOS` vs `Platform.isIOS`.

### Known limitations

- **No touch gestures.** All input is Siri Remote (focus-based) or MFi game controller. Touch-only widgets (`GestureDetector`, `Dismissible`, swipe-to-reveal) don't fire on Apple TV.
- **No soft keyboard.** Text input goes through the tvOS system keyboard view controller (full-screen). `TextField.autofocus` requires focus engine participation — it doesn't "just work" like on iOS.
- **No WebKit / `webview_flutter`.** tvOS does not ship WebKit. Any plugin depending on `WKWebView` will not compile for Apple TV.
- **No haptics, clipboard, or status bar.** `HapticFeedback.*`, `Clipboard.*`, and `SystemChrome.setSystemUIOverlayStyle` are no-ops on tvOS.
- **No `fork()`.** Apple TV disallows `fork()` entirely. This affects some background-work libraries; Perfetto's daemonize path is already patched in our engine fork.
- **Simulator-only debug builds.** Physical Apple TV deployment is supported in release/profile mode (AOT), not debug (JIT is blocked on the device).
- **Metal-only rendering.** No OpenGL backend. Apps that rely on GL-specific platform views will not work.

## Docs

#### App development

- [Getting started](doc/get-started.md)
- [Supported commands](doc/commands.md)
- [Debugging apps](doc/debug-app.md)
- [Publishing to the App Store](doc/publish-app.md)

#### Plugin development

- [Writing a tvOS plugin](doc/develop-plugin.md)

#### Project internals

- [Architecture](doc/architecture.md)

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

```sh
# Run tests
flutter/bin/dart test test/
```

## License

BSD 3-Clause — see [LICENSE](LICENSE).

This project incorporates code from Flutter and flutter-tizen (both BSD 3-Clause).  
See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for full attribution.

---

_flutter-tvos is an independent community project and is not affiliated with, endorsed by, or sponsored by Google LLC or Apple Inc. Flutter is a trademark of Google LLC. Apple TV and tvOS are trademarks of Apple Inc._
