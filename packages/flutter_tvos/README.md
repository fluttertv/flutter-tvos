# flutter_tvos

Platform detection and utilities for Flutter apps running on Apple TV (tvOS).

Part of the [flutter-tvos](https://fluttertv.dev) project — an open-source Flutter embedder for Apple TV.

## Features

- Detect if the app is running on tvOS
- Query tvOS version, device model, and machine identifier
- Check device capabilities: 4K, HDR, multi-user support
- Get display resolution
- **Synchronous API** — powered by dart:ffi, zero async overhead

## Getting Started

Add `flutter_tvos` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_tvos: ^1.0.0
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

`flutter_tvos` wires the Apple TV remote to Flutter's standard focus
system. Swipes and button presses become keyboard events
(`arrowLeft/Right/Up/Down`, `select`, etc.) which flow through
`Focus`/`Shortcuts`/`Actions` exactly like arrow keys on a physical
keyboard would.

**One-line setup:** use `runTvApp` in place of `runApp`:

```dart
import 'package:flutter_tvos/flutter_tvos.dart';

void main() => runTvApp(const MyApp());
```

On iOS/Android `runTvApp` is a plain passthrough — the same `main.dart`
works across all platforms.

### What works out of the box

- Swipes Up/Down/Left/Right on Siri Remote → arrow keys
- Select button → `LogicalKeyboardKey.select` (same as pressing Enter on
  a focused widget)
- Menu button → `LogicalKeyboardKey.escape` (drives `Navigator.pop`)
- Play/Pause → `LogicalKeyboardKey.mediaPlayPause`
- Long-press in a direction → auto-repeat arrow key at ~80 ms intervals
- External game controllers (MFi) with a directional pad
- Lock-screen media commands (play, pause, seek) via
  `MPRemoteCommandCenter`

### Tuning thresholds

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  TvRemoteController.instance.config = const TvRemoteConfig(
    shortSwipeThreshold: 0.4,   // less sensitive
    keyRepeatInterval: Duration(milliseconds: 100),
  );
  runTvApp(const MyApp());
}
```

### Raw touch listener (video players, custom swipe zones)

```dart
TvRemoteController.instance.addRawListener((event) {
  if (event.phase == TvRemoteTouchPhase.move && isInPlayerArea(event)) {
    seekVideo(event.x);
  }
});
```

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
- tvOS 13.0+ deployment target
- Built with [flutter-tvos](https://fluttertv.dev) CLI

## License

BSD 3-Clause. See [LICENSE](LICENSE) for details.

This project is not affiliated with or endorsed by Google or Apple.
Flutter is a trademark of Google. tvOS is a trademark of Apple Inc.
