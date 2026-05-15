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

**`Platform.isIOS` is `true` on tvOS.** Apple TV runs the same Darwin kernel, UIKit, Metal, and Foundation as iPhone and iPad — it's part of the iOS family. Standard Flutter widgets that branch on `Platform.isIOS` or `defaultTargetPlatform` already render correctly on Apple TV: Cupertino styling, SF font, and iOS-style page transitions all work out of the box, with no Flutter framework changes required.

The Flutter framework that flutter-tvos uses is unmodified. tvOS identity is contributed entirely by the Dart VM in our engine build and by the `flutter-tvos` CLI itself.

### Plugin platform key

A Flutter plugin advertises which platforms it supports under `flutter.plugin.platforms` in its `pubspec.yaml`. Plugins target tvOS by adding a `tvos:` entry there:

```yaml
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: MyPlugin
```

A tvOS build only loads plugins that declare this key. Plugins targeting only `ios:` are not picked up — Apple TV needs different native code in many cases (no WebKit, no haptics, no clipboard, no camera, focus-engine input instead of touch), so the safe default is to require explicit opt-in.

In practice each plugin with native code ships an extra federated package (e.g. `url_launcher` → `url_launcher_tvos`) that adds the tvOS implementation. The same model is used by `flutter-tizen`, and `flutter-elinux`.

A FlutterTV-curated index of ported plugins is being assembled and will be published soon. In the meantime, `flutter-tvos plugin port` (coming next) can scaffold a federated `*_tvos` package from any existing iOS or macOS plugin so you can port the ones you depend on yourself.

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

- **No touch gestures.** All input is Siri Remote (focus-based) or MFi game controller. Touch-only widgets (`GestureDetector`, `Dismissible`, swipe-to-reveal) don't fire on Apple TV. Build with `Focus` / `FocusableActionDetector` / `Shortcuts` instead.
- **Text input goes through the tvOS virtual keyboard.** `TextField` works on Apple TV: focusing it brings up the full-screen system keyboard view controller. Hardware keyboards paired over Bluetooth also work. `TextField.autofocus` is supported but participates in the focus engine — it competes with other focusables and isn't always the first focus on screen.
- **No WebKit / `webview_flutter`.** tvOS does not ship WebKit. Plugins depending on `WKWebView` will not compile for Apple TV.
- **No haptics, clipboard, or status bar.** `HapticFeedback.*`, `Clipboard.*`, and `SystemChrome.setSystemUIOverlayStyle` are no-ops on tvOS.
- **No `fork()`.** Apple TV disallows `fork()` entirely. Some background-work libraries are affected; Perfetto's daemonize path is already patched in our engine build.
- **Debug mode is simulator-only.** Physical Apple TV deployment runs in release/profile mode (AOT). Debug (JIT) is blocked on the device by Apple.
- **Metal-only rendering.** No OpenGL backend. Apps relying on GL-specific platform views will not work.

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
