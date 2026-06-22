## 1.1.2

- Documentation: list Siri Remote support in the README feature summary and
  bump the install snippet to the current version. No functional or API
  changes.

## 1.1.1

- Fixed the remote-control `configure` handshake racing native plugin
  registration at startup. `TvRemoteController.init()` now retries the
  `configure` call until the native `FlutterTvRemotePlugin` acknowledges it,
  so the touchpad reliably starts forwarding swipe/touch events instead of
  intermittently appearing dead when the first push landed before the native
  handler was registered. The retry now only swallows the expected
  `MissingPluginException` / `PlatformException` (any other error — e.g. a
  config serialization bug — propagates instead of being silently retried),
  and if the handshake is never acknowledged within the retry budget it
  surfaces via `FlutterError.reportError` rather than giving up silently.

## 1.1.0

- Added Swift Package Manager support. `flutter_tvos` now ships a
  `tvos/Package.swift` alongside its podspec, so apps using SPM-based plugin
  integration link it through the generated `FlutterGeneratedPluginSwiftPackage`
  umbrella. Previously this FFI plugin was CocoaPods-only because its symbols,
  resolved at runtime via `dart:ffi`, had no compile-time caller and the static
  linker dropped them. The plugin now declares its exported C symbols under
  `flutter.plugin.platforms.tvos.ffiSymbols`; flutter-tvos reads that list to
  emit forced link references in the app's generated registrant, and each export
  is annotated `__attribute__((used))` / `visibility("default")` so it reaches
  the binary's dynamic symbol table. Requires flutter-tvos 1.3.0 or newer; older
  CLIs ignore `ffiSymbols` and the plugin continues to work via CocoaPods.

## 1.0.5

- Updated compatibility with Flutter 3.44.0.

## 1.0.4

- Fixed `dart:ffi` and `dart:io` compile errors on Web. `flutter_tvos` can now
  be added to a core package shared across tvOS, iOS, Android, and Web targets
  without stub workarounds. All `TvOSInfo` properties return safe defaults
  (`false` / `''` / `0`) on Web.

## 1.0.3

- Example: call `WidgetsFlutterBinding.ensureInitialized()` before `TvRemoteController.instance.init()` so the Flutter binding is ready when the platform channel attaches.
- pubspec: added `issue_tracker` link so GitHub issues surface on pub.dev.

## 1.0.2

- Removed the `runTvApp` helper from the public API; apps should use normal `runApp`.
- `TvRemoteController.instance.init()` now attaches Dart touch handlers explicitly and remains a no-op off tvOS.
- Updated README setup/tuning guidance to reflect explicit initialization and current usage patterns.

## 1.0.1

- Changelog corrected and metadata updated for publication on pub.dev (removed incorrect 1.1.0 header and merged entries under 1.0.0).

## 1.0.0

### Remote Control (RCU)

- `TvRemoteController.init()` — Siri Remote wired to
  Flutter's keyboard/focus pipeline on tvOS; passthrough on iOS/Android.
- `TvRemoteConfig` — runtime-tunable thresholds (swipe, D-pad dead
  zone, auto-repeat delays); shipped to native via method channel.
- `TvRemoteController.addRawListener` — raw touchpad events for
  custom swipe zones (video scrubbers etc.).
- `TvRemoteController.addSwipeListener` — receive aggregated
  `SwipeEvent` notifications (direction + magnitude + isFast) without
  hand-rolling a `SwipeDetector` from raw touches. Raw and swipe
  listeners fire in parallel for the same gesture.
- Lock-screen media commands (`MPRemoteCommandCenter`) forwarded to
  `flutter/keyevent` so widgets reacting to
  `LogicalKeyboardKey.mediaPlay/Pause/Stop/...` light up for free.

### Round-3 review follow-ups (Flutter Android / flutter-tizen parity)

- **Select → `LogicalKeyboardKey.enter`** (was `select`). Flutter's
  default `ActivateIntent` binds to `enter`, so standard buttons and
  list items now activate on Select press without any app-level
  shortcut registration.
- **Menu → `Navigator.maybePop`** via `flutter/navigation popRoute`
  (was a dead `press(key=menu)` method call). Mirrors Android's
  physical back-button behavior.
- **Play/Pause → `LogicalKeyboardKey.mediaPlayPause`** (was a dead
  `press(key=playPause)` method call). Via Android keymap (Flutter's
  macOS map has no media entries).
- **Touches channel no longer spams** "message discarded" warnings
  when no `addRawListener` is registered — engine installs a no-op
  drain, transparently replaced by Dart handler on attach.

- Initial release
- Platform detection: `isTvOS`, `isSimulator`
- Device info: `tvOSVersion`, `deviceModel`, `machineId`
- Capability queries: `supports4K`, `supportsHDR`, `supportsMultiUser`
- Display info: `displayResolution`
- Result caching with `clearCache()` support
