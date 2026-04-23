
## Remote Control (RCU) Architecture (2026-04-23)

Refactored Siri Remote / game controller / Walnut media handling from
inline `FlutterViewController.mm` code into a proper internal plugin
(`FlutterTvRemotePlugin`), following the `FlutterPlatformPlugin` pattern.
Added the Dart counterpart in `packages/flutter_tvos`.

### Engine changes (`flutter_upstream_tvos_engine`)

- **NEW:** `FlutterTvRemotePlugin.h` / `.mm` — owns press recognizers,
  game controller observers, media command handlers, and the two
  channels (`flutter/tv_remote`, `flutter/tv_remote_touches`). Press
  recognizers install on the view; lifecycle follows `attach`/`detach`.
- **`FlutterEngine.mm`:** plugin created alongside `FlutterPlatformPlugin`
  in `createDataPipe`. Accessor published via `FlutterEngine_Internal.h`.
- **`FlutterViewController.mm`:** removed ~200 lines of inline tvOS
  code (press handlers, gamepad setup, Walnut, channel creation).
  `touchesBegan/Moved/Ended/Cancelled` now forward to plugin; `viewDidLoad`
  calls `attachToViewController:`, `dealloc` calls `detach`.
- **Coordinate normalization:** plugin sends normalized `[-1.0, 1.0]`
  coords instead of raw pixels, removing the magic `x-1000 / y-500`
  adjustment from Dart code and making behavior correct on both 1080p
  and 4K Apple TVs.
- **GameController double-registration fix:** plugin clears previous
  `valueChangedHandler` before installing a new one, and tracks
  configured controllers in a hash table. Addresses
  `// TODO dangerous, multiple registrations can happen!`.
- **Python 3.13+ compatibility:** `build_tvos_engine.sh` creates a
  scoped shim that maps `python3 -> python3.12` for the build process
  only, so depot_tools' `ninja.py` (which imports the removed `pipes`
  module) works on Python 3.14 systems. Shim is cleaned up on exit.

### Dart package (`packages/flutter_tvos`)

- **NEW:** `lib/src/rcu/tv_remote_controller.dart` — singleton
  `TvRemoteController` receiving channel messages and generating
  keyboard events via `ServicesBinding.keyEvent`.
- **NEW:** `lib/src/rcu/swipe_detector.dart` — normalized-space swipe
  accumulator, adapted from horizon `SwipeMixin`. Emits arrow keys
  when cumulative delta crosses the configured threshold.
- **NEW:** `lib/src/rcu/key_repeat.dart` — long-press auto-repeat with
  configurable initial delay + interval. Tested with `fake_async`.
- **NEW:** `lib/src/rcu/key_simulator.dart` — wraps the macOS-format
  `keyEvent` channel message used by Flutter's Darwin keyboard pipeline.
- **NEW:** `lib/src/rcu/tv_remote_channels.dart` — channel definitions
  shared with native.
- **NEW public API:** `runTvApp(Widget)` — drop-in `runApp` replacement;
  on iOS/Android it's a passthrough, on tvOS it initializes the
  controller. One-line integration for app authors.
- **19 new unit tests** covering swipe detection, key repeat timing,
  raw listener delivery, and click event translation.
- **Example app** (`packages/flutter_tvos/example`) now exposes a 4×4
  focus grid to verify that Remote gestures drive Flutter's focus
  traversal end-to-end.

### For app authors

```dart
// before
void main() => runApp(MyApp());

// after
void main() => runTvApp(MyApp());  // identical behavior on iOS/Android
```

Existing `Focus`, `Shortcuts`, and `Actions` code Just Works — arrow
keys now come from both a hardware keyboard (as before) and Siri Remote
swipes. No new widgets to learn.

## Bug Fixes (2026-04-17)

### `lib/tvos_device.dart`

**BUG-1: `stopApp` sent `--pid 0` to `devicectl` on physical devices**  
Calling `devicectl device process terminate --pid 0` is meaningless (PID 0 is the kernel). The log-reader `dispose()` call immediately before already detaches the console session, which is sufficient to stop the app. Removed the bogus `devicectl` invocation; `stopApp` now returns `true` after teardown.

**BUG-16: `installApp` hardcoded `BuildMode.debug` for simulator and `BuildMode.release` for device**  
Profile builds on device would look for `Debug-appletvos/Runner.app` (simulator path) or `Release-appletvos/Runner.app` even when a profile bundle was built. Fixed by probing `Release-<sdk>/Runner.app` first, falling back to `Debug-<sdk>/Runner.app`, for both simulator and device.

---

### `lib/build_targets/application.dart`

**BUG-3: `_sdkPath` ignored xcrun exit code**  
If `xcrun --sdk appletvos --show-sdk-path` failed (e.g. tvOS SDK not installed), the method silently returned an empty string. Downstream xcodebuild commands would then fail with a cryptic "no such file" error. Fixed: throws an `Exception` with the stderr output when exit code is non-zero or the path is empty.

**BUG-9: `Generated.xcconfig` hardcoded `FLUTTER_BUILD_NAME=1.0.0` and `FLUTTER_BUILD_NUMBER=1`**  
These values override whatever version the app's `pubspec.yaml` declares, breaking release versioning. Fixed: reads `buildInfo.buildInfo.buildName` and `buildInfo.buildInfo.buildNumber`, falling back to `1.0.0`/`1` only if null.

---

### `lib/tvos_doctor.dart`

**BUG-8: `_checkEngineArtifacts` used a relative path for `ls -d engine_artifacts/…`**  
The check ran relative to the calling process's working directory, not the CLI root. If `flutter-tvos doctor` was invoked from a Flutter project directory the check would always fail. Replaced the `ls` subprocess call with a direct filesystem check resolved from `platform.script` (the snapshot path), which always points to `bin/cache/flutter-tvos.snapshot` inside the CLI root.

**BUG-7: Reviewed but not changed**  
The friend reported `hasErrors → ValidationType.partial` and `hasHints → ValidationType.success` were inverted. On closer inspection the code is correct: Xcode absence returns `missing` early (before the flag logic); subsequent errors (tvOS SDK, simulator runtime) are `partial`; CocoaPods absence is a hint and leaves the result as `success`. Reverting an earlier accidental change that flipped the enum values.

---

### `test/general/tvos_doctor_test.dart`

- Removed `ls -d engine_artifacts/…` fake commands (no longer a subprocess).
- Added `fileSystem` and `platform` injection to all `TvosValidator` test instantiations so `_checkEngineArtifacts` works without `globals.fs`/`globals.platform`.
- Added new test case: **"reports hint when engine artifacts are absent"** — verifies that a missing artifact directory produces a hint message and keeps overall status as `success`.

---

### Not fixed (false positives or low risk)

| Friend's ID | Claim | Decision |
|-------------|-------|----------|
| BUG-7 | `ValidationType` logic inverted | Not a bug — logic is correct as originally written |
| BUG-17 | `platforms:` regex too broad in create.dart | Low risk; only matches first occurrence inside pubspec |
| BUG-18 | `on Exception` won't catch `TypeError` in emulator | Low impact; `simctl` output is stable JSON |
| BUG-19 | `flutter_tvos_ffi.m` init not thread-safe | Out of scope; plugin skeleton only |
| BUG-20 | Unversioned deps in pubspec.yaml | Standard pattern for `flutter_tools`-wrapping packages |
