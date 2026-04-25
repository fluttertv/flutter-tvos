
## Remote Control (RCU) Architecture (2026-04-23)

### For app authors

```dart
// before
void main() => runApp(const MyApp());

// after
void main() => runTvApp(const MyApp());  // identical behavior on iOS/Android
```

Existing `Focus`, `Shortcuts`, and `Actions` code Just Works — arrow
keys and Select now come from the Siri Remote (both touchpad and
physical buttons), the Apple TV Remote app, MFi game controllers, and
lock-screen media commands. No new widgets to learn. Threshold tuning
is available via `TvRemoteController.instance.config` (see the package
README).

### Engine changes (`flutter_upstream_tvos_engine`)

Refactored Siri Remote / game controller / Walnut media handling from
inline `FlutterViewController.mm` code into a proper internal plugin
(`FlutterTvRemotePlugin`), following the `FlutterPlatformPlugin`
pattern.

- **NEW:** `FlutterTvRemotePlugin.{h,mm,_Internal.h}` — owns press
  recognizers, game controller observers, media command handlers, an
  internal `FlutterTvKeyRepeater` (NSTimer-based auto-repeat), and the
  two public channels: `flutter/tv_remote` (`FlutterMethodChannel`,
  JSON) for buttons/media and `flutter/tv_remote_touches`
  (`FlutterBasicMessageChannel`, JSON) for touchpad events.
- **NEW:** `FlutterTvRemotePluginTest.mm` — XCTests for attach/detach,
  VC migration, touch normalization with zero-size view, `sendKey`
  keymap selection, and the full `FlutterTvKeyRepeater` state machine.
  (The `ios_test_flutter` target is currently disabled for tvOS builds;
  tests will land as part of re-enabling that target — coordinate with
  Mehmet.)
- **`FlutterEngine.mm`:** plugin created alongside
  `FlutterPlatformPlugin` inside `setUpChannels`. Accessor on
  `FlutterEngine_Internal.h`. `setViewController:` now attaches/detaches
  the plugin to mirror the `textInputPlugin` lifecycle, so engine-group
  / headless-to-headed flows work correctly.
- **`FlutterViewController.mm`:** removed ~200 lines of inline tvOS
  code (press handlers, gamepad setup, Walnut, channel creation).
  `touchesBegan/Moved/Ended/Cancelled` forward to the plugin guarded
  against stale-VC forwarding; `viewDidLoad` calls
  `attachToViewController:`, `dealloc` only detaches if this VC is
  still the plugin's attached VC.
- **Keyboard event path:** arrow/page button presses and continuous-
  swipe auto-repeat emit macOS-keymap `flutter/keyevent` messages via
  the engine's own channel. Touchpad clicks route through the touches
  channel (`click_s`/`click_e`) so the Dart controller can apply
  directional bias from the last D-pad position. For
  `LogicalKeyboardKey.select` the plugin switches to the Android keymap
  (`23 → select`) because macOS `kVK_Return` decodes to `enter` — using
  it would silently deliver a different logical key.
- **Coordinate normalization:** plugin sends normalized `[-1.0, 1.0]`
  coords with double precision, removing the magic `x-1000 / y-500`
  adjustment from Dart code and making behavior correct on both 1080p
  and 4K Apple TVs.
- **Continuous-swipe auto-repeat:** native accumulator counts
  consecutive same-direction moves; after a small threshold the
  `FlutterTvKeyRepeater` is engaged so holding a swipe behaves like
  holding an arrow key.
- **Lifecycle fixes:** GameController `valueChangedHandler` cleared
  before reassignment; `configureController` skip path logs the vendor
  name in debug; `controllerDidConnect:` and `controllerDidDisconnect:`
  both dispatch to the main queue; `MPRemoteCommandCenter` handlers are
  captured by `(command, token)` pairs and removed in `detach` so they
  do not accumulate across engine restarts; `registerMediaCommandsOnce`
  only flips its "registered" flag after all handlers installed.
- **Select press during text input:** restored the
  `tvosKeyboardPending` / `tvosActivateKeyboard` handoff so tapping
  Select on a focused text field opens the tvOS keyboard without also
  firing a `click_s` to Dart.
- **Build script:** `build_tvos_engine.sh` creates a scoped shim that
  maps `python3 -> python3.12` for the build process only, so
  depot_tools' `ninja.py` (which imports the removed `pipes` module)
  works on Python 3.13+. Shim validated on creation and cleaned up via
  `trap` on EXIT / INT / TERM / HUP.

### Dart package (`packages/flutter_tvos`)

- **NEW:** `lib/src/rcu/tv_remote_controller.dart` — singleton
  `TvRemoteController`. Handles touchpad click events (with
  directional-click bias and click-race protection), exposes
  `addRawListener` for advanced consumers (video scrubbing, custom
  swipe zones), and carries mutable `TvRemoteConfig` with validated
  defaults.
- **NEW:** `lib/src/rcu/swipe_detector.dart` — normalized-space swipe
  accumulator used for the raw-listener API and unit tests. Actual
  continuous-swipe auto-repeat runs natively.
- **NEW:** `lib/src/rcu/key_simulator.dart` — sends a simulated
  hardware keyboard event through `SystemChannels.keyEvent`. Only used
  for touchpad click events now (physical buttons and continuous
  swipes are simulated in native). Falls back to the Android keymap
  for `LogicalKeyboardKey.select` since macOS has no matching keycode.
- **NEW:** `lib/src/rcu/tv_remote_channels.dart` — channel definitions
  shared with native.
- **NEW public API:** `runTvApp(Widget)` — drop-in `runApp` replacement;
  on iOS/Android it's a passthrough, on tvOS it initializes the
  controller. Documented interaction with custom `WidgetsBinding`
  subclasses and the hot-restart limitation (cold restart required to
  re-register channel handlers after hot restart).
- **Tests:** 52+ unit tests split across `swipe_detector_test.dart`
  (threshold edge cases, direction reversal, zigzag) and
  `tv_remote_controller_test.dart` (raw listener delivery, malformed
  messages, click phases, directional-click bias, rapid click_s
  sequences verifying the keyup-for-previous fix, config mutation,
  button channel handlers, media commands).
- **Example app** (`packages/flutter_tvos/example`) uses `runTvApp`
  and exposes a 4×4 `FocusableActionDetector` grid with click counters
  so focus traversal, Select activation, and hold-to-scroll can be
  verified visually on the Apple TV simulator.

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
