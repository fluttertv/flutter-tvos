# Changelog

All notable changes to flutter-tvos will be documented here.

## [1.0.0] — 2026-04-15

First public release. Targets Flutter 3.41.4.

### Highlights
- **RCU (Remote Control Unit) Support**: Full integration with the Apple TV Siri Remote, including directional pad (D-pad) focus manipulation and enter/select interactions.
- **Native TextField Implementation**: Deep integration with the tvOS on-screen keyboard, allowing users to interact with Flutter `TextField` widgets identically to native tvOS text inputs.
- **Flutter DevTools Integration**: Full support for Flutter DevTools, Observatory, profiling, and debugging across both simulator and physical devices.

### Commands

Ten commands are available in this release:

| Command | Description |
|---------|-------------|
| `build tvos` | Build an IPA or app bundle for tvOS device or simulator |
| `run` | Build, install, and launch on a simulator or device with hot reload |
| `create` | Scaffold a new tvOS app or plugin |
| `clean` | Delete build artefacts |
| `devices` | List connected Apple TV devices and running simulators |
| `doctor` | Check that the toolchain is configured correctly |
| `attach` | Attach to an already-running Flutter app for debugging |
| `drive` | Run integration tests via flutter_driver |
| `test` | Run unit tests |
| `precache` | Pre-download engine artifacts |

### Simulator Support

- Debug (JIT) builds targeting `appletvsimulator` SDK
- Hot reload and hot restart over the VM service
- Simulator listed and targeted by device ID via `flutter-tvos devices` and `flutter-tvos run -d <id>`

### Physical Device Deployment

- Deployment to physical Apple TV hardware via `xcrun devicectl`
- Release and profile (AOT) builds targeting `appletvos` SDK
- Three-tier code signing resolution: environment variable → embedded `.pbxproj` setting → keychain lookup

### AOT Compilation

- Release builds use `gen_snapshot` to produce ahead-of-time compiled binaries
- Profile builds include observatory/DevTools hooks without JIT overhead

### Plugin Support

- Native Swift plugins via CocoaPods integration
- Plugin template: `flutter-tvos create --template=plugin`
- Plugins declare a `tvos` platform entry in their `pubspec.yaml`

### `flutter_tvos` Platform Package

A companion Dart/Swift package providing:

- `TvOSInfo` — device model, OS version, and screen size queries
- Device detection helpers (physical vs. simulator)
- tvOS capability queries (focus engine availability, game controller presence)

### Tests

74 unit tests covering command parsing, artifact resolution, build configuration, code signing logic, and device discovery. All tests use Flutter's standard test infrastructure and run without a connected device.

### Known Limitations

- tvOS Simulator only supports debug (JIT) mode; profile/release simulator builds are not available (Apple restriction)
- Metal is the only supported rendering backend; OpenGL is not present on tvOS
- macOS host and Xcode 15 or later are required
