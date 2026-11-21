# flutter_tvos

Platform detection and utilities for Flutter apps running on Apple TV (tvOS).

Part of the [flutter-tvos](https://fluttertv.dev) project — an open-source Flutter embedder for Apple TV.

## Features

- Detect if the app is running on tvOS
- Query tvOS version, device model, and machine identifier
- Check device capabilities: 4K, HDR, multi-user support
- Get display resolution
- **Synchronous API** — powered by dart:ffi, zero async overhead
- **Siri Remote extras** — tuning for how the remote maps to keys (repeat
  speed, touchpad dead zone, swipe thresholds), plus raw-touch and
  high-level swipe listeners. Basic focus navigation needs no package —
  the engine provides it (see [Remote Control](#remote-control-siri-remote))

## Getting Started

Add `flutter_tvos` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_tvos: ^1.1.3
```

## Usage

```dart
import 'package:flutter_tvos/flutter_tvos.dart';

// Check if running on tvOS
if (TvOSInfo.isTvOS) {
  print('Running on Apple TV!');
}

// Get platform details
final version = TvOSInfo.tvOSVersion;   // "18.4"
final model   = TvOSInfo.deviceModel;   // "Apple TV"
final machine = TvOSInfo.machineId;     // "AppleTV14,1"

// Check capabilities
final is4K      = TvOSInfo.supports4K;       // true/false
final isHDR     = TvOSInfo.supportsHDR;      // true/false
final multiUser = TvOSInfo.supportsMultiUser; // true (tvOS 14+)

// Display info
final width  = TvOSInfo.displayWidth;      // 3840
final height = TvOSInfo.displayHeight;     // 2160
final res    = TvOSInfo.displayResolution; // "3840x2160"

// Check simulator
final isSim = TvOSInfo.isSimulator; // true/false
```

### Adaptive UI Example

```dart
Widget build(BuildContext context) {
  if (TvOSInfo.isTvOS) {
    return TvLayout(child: content);    // TV-optimized layout
  }
  return MobileLayout(child: content); // Standard mobile layout
}
```

## Remote Control (Siri Remote)

The **tvOS engine** wires the Apple TV remote to Flutter's standard focus
system. Swipes and button presses become keyboard events
(`arrowLeft/Right/Up/Down`, `select`, etc.) which flow through
`Focus`/`Shortcuts`/`Actions` exactly like arrow keys on a physical
keyboard would.

### Do you need this package for remote navigation?

**No.** Remote navigation is delivered by the engine, not by this package. An
app that only uses `Focus`, `FocusTraversal`, `Shortcuts`, `Actions`, buttons,
lists and other standard focusable widgets responds to the Siri Remote with
`flutter_tvos` not even in its `pubspec.yaml`. Everything under "What works out
of the box" below is engine-side and needs no Dart dependency.

Reach for this package when you want to:

- **tune** how the remote is translated into keys — repeat speed, touchpad
  dead zone, swipe thresholds (see [Tuning](#tuning));
- consume the **analog touchpad** as coordinates rather than keys
  (`addRawListener`);
- consume **swipes** as direction + magnitude events (`addSwipeListener`).

The raw touch stream is the one feature that genuinely requires the package:
the engine holds touch forwarding back until Dart completes the `configure`
handshake, which `TvRemoteController.init()` performs. Key events are not
gated that way and flow regardless.

Call `TvRemoteController.instance.init()` once in `main()` when you use
`TvRemoteController` APIs such as `config`, `addRawListener`, or
`addSwipeListener`. `init()` is idempotent, attaches the Dart touch channel
on tvOS, and is a no-op on other platforms.

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_tvos/flutter_tvos.dart';

void main() {
  TvRemoteController.instance.init();
  runApp(const MyApp());
}
```

### What works out of the box

All of the following is engine-side — it works with or without this package:

- Swipes Up/Down/Left/Right on Siri Remote → arrow keys
- Select button → `LogicalKeyboardKey.enter` — activates focused
  buttons / list items through Flutter's default `ActivateIntent`
  binding, matching Flutter Android / flutter-tizen behavior
- Menu button (Back on the second-generation Siri Remote) →
  `LogicalKeyboardKey.goBack` key event, then, on release and only if
  nothing handled the key, `flutter/navigation popRoute` →
  `Navigator.maybePop` (see [Menu and Back](#menu-and-back))
- Play/Pause → `LogicalKeyboardKey.mediaPlayPause`
- Long-press in a direction → auto-repeat arrow key at ~80 ms intervals
- External game controllers (MFi) with a directional pad
- Lock-screen media commands (play, pause, seek, stop, toggle) are
  forwarded through `flutter/keyevent` so any widget reacting to
  `LogicalKeyboardKey.mediaPlay` / `mediaPause` / `mediaFastForward`
  / `mediaRewind` / `mediaStop` / `mediaPlayPause` is triggered with
  no app-level wiring

### Menu and Back

The Menu button (Back on the second-generation Siri Remote) reaches
Flutter in two steps:

1. A key event on `flutter/keyevent`: `LogicalKeyboardKey.goBack` down,
   then up. This is the logical key Flutter reports for Android's Back
   key (key code 4), so a `goBack` handler written for Android TV also
   matches Menu here.
2. When the button is released, and only if nothing reported the key
   down or the key up as handled, the engine sends `popRoute` on
   `flutter/navigation`. Flutter turns that into `Navigator.maybePop`,
   so `PopScope`, dialogs and pushed routes behave as with Android's
   back button. On the root route with nothing to pop, Flutter calls
   `SystemNavigator.pop()` and the app goes to the Home screen. It is
   suspended, not terminated; reopening it resumes it.

Flutter binds nothing to `goBack` by default, so an app that does not
handle it gets step 2 on every press.

To handle Menu yourself, report `goBack` as handled while focus is
inside your widget:

```dart
Focus(
  onKeyEvent: (node, event) {
    if (event.logicalKey != LogicalKeyboardKey.goBack) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      showPauseMenu();
    }
    return KeyEventResult.handled;
  },
  child: gameView,
)
```

A `Shortcuts` or `CallbackShortcuts` binding on
`SingleActivator(LogicalKeyboardKey.goBack)` works as well: it handles
the key down, which is enough. A screen that handles `goBack` owns the
press: the engine sends no `popRoute` and nothing pops. On the app's
top-level screen that means Menu no longer leaves the app. Apple's
Human Interface Guidelines treat the Home screen as the parent of an
app's top level; the exception they name is active gameplay, where Back
opens a pause menu instead.

Holding Menu is tvOS's own gesture for going to the Home screen, and
tvOS decides when a press counts as a hold. With simulated remote
presses on an Apple TV 4K running tvOS 27.2, a hold of about 0.8 s or
longer never reached the app as a key and nothing popped, while a
0.3 s hold arrived on release and popped once.

The engine sends every press that tvOS reports as Menu this way. A
hardware keyboard's Escape key or a game controller's B or Menu button
may be reported as Menu; those then arrive as `goBack` as well, not as
`escape` or `gameButtonB` as on Android.

flutter-tvos 1.12.1 and earlier sent only `popRoute`, when the button
went down, and no key event.

### Tuning

All tuning lives on `TvRemoteConfig`. Assigning a new config after
initialization ships the values to the native engine plugin (via a
method-channel call); mutations take effect on the next input event.
Assigning config before `init()` is also supported: the value is stored
locally and pushed once when `init()` runs.

```dart
// Tuning before init (applied on initialization)
void main() {
  TvRemoteController.instance.config = const TvRemoteConfig(
    shortSwipeThreshold: 0.4,
    fastSwipeThreshold: 0.6,
    dpadDeadZone: 0.6,
    continuousSwipeMoveThreshold: 4,
    keyRepeatInitialDelay: Duration(milliseconds: 450),
    keyRepeatInterval: Duration(milliseconds: 100),
  );
  TvRemoteController.instance.init();
  runApp(const MyApp());
}
```

You can also assign `config` later, such as from `initState`, if the values
depend on app state; after initialization, changes are pushed to native
immediately.

All fields have sensible defaults so apps that never touch `config`
behave identically to the stock configuration.

### Raw touch listener (video players, custom swipe zones)

Requires `TvRemoteController.instance.init()` in `main()`.

```dart
TvRemoteController.instance.addRawListener((event) {
  if (event.phase == TvRemoteTouchPhase.move && isInPlayerArea(event)) {
    seekVideo(event.x);
  }
});
```

### Swipe listener (high-level direction + magnitude)

Requires `TvRemoteController.instance.init()` in `main()`.

For consumers that just want "user swiped left/right/up/down" without
hand-rolling a detector, subscribe at the swipe-event level:

```dart
TvRemoteController.instance.addSwipeListener((event) {
  if (event.direction == SwipeDirection.right && event.isFast) {
    seekVideo(seconds: 30);
  }
});
```

`SwipeEvent` carries `direction` (left/right/up/down), `magnitude`
(`max(|dx|, |dy|)` in normalized [-1, 1] view space), and `isFast`
(true when magnitude crosses `fastSwipeThreshold` from `TvRemoteConfig`).

Raw `addRawListener` callbacks still receive every touch point in
parallel — the two layers are independent.

## API Reference

| Property | Type | Description |
|----------|------|-------------|
| `TvOSInfo.isTvOS` | `bool` | Whether the app is running on tvOS |
| `TvOSInfo.tvOSVersion` | `String` | tvOS version (e.g., "18.4") |
| `TvOSInfo.deviceModel` | `String` | Device model name |
| `TvOSInfo.machineId` | `String` | Machine identifier (e.g., "AppleTV14,1") |
| `TvOSInfo.isSimulator` | `bool` | Running in tvOS Simulator |
| `TvOSInfo.supports4K` | `bool` | 4K output capability |
| `TvOSInfo.supportsHDR` | `bool` | HDR display support |
| `TvOSInfo.supportsMultiUser` | `bool` | Multi-user support (tvOS 14+) |
| `TvOSInfo.displayWidth` | `int` | Native display width in pixels |
| `TvOSInfo.displayHeight` | `int` | Native display height in pixels |
| `TvOSInfo.displayResolution` | `String` | Display resolution (e.g., "3840x2160") |

## Requirements

- Flutter 3.19.0+
- tvOS 15.0+ deployment target
- Built with [flutter-tvos](https://fluttertv.dev) CLI

## Multi-platform / monorepo usage

`flutter_tvos` is safe to add to a core package shared across tvOS, iOS,
Android, and Web. On Web, `dart:ffi` and `dart:io` are excluded at compile
time via conditional imports — no stub workarounds needed in your code.

All `TvOSInfo` properties return safe defaults on non-tvOS platforms:

| Platform | `isTvOS` | strings | ints |
|----------|----------|---------|------|
| tvOS | `true` | real values | real values |
| iOS / macOS | `false` | `''` | `0` |
| Android / Linux / Windows | `false` | `''` | `0` |
| **Web** | `false` | `''` | `0` |

`TvRemoteController.init()` is a no-op on all non-tvOS platforms.

## License

BSD 3-Clause. See [LICENSE](LICENSE) for details.

This project is not affiliated with or endorsed by Google or Apple.
Flutter is a trademark of Google. tvOS is a trademark of Apple Inc.
