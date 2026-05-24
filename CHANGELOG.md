# Changelog

All notable changes to flutter-tvos will be documented here.

## [1.1.0] — 2026-05-24

Minor release — the "porter release". Adds the entire
`flutter-tvos plugin port` command for scaffolding federated
`*_tvos` plugins from existing iOS / macOS plugins, first-class
`flutter-tvos create --platforms=tvos`, a build-time nudge for
plugins missing tvOS support, and a handful of build-pipeline
fixes. No Flutter SDK or engine-artefact change — pinned versions
match v1.0.1.

### Added
- **`flutter-tvos plugin port` — new command.** Scaffolds a
  federated `<plugin>_tvos` sibling from any existing iOS or macOS
  Flutter plugin. The source plugin is never modified. Source
  loaders: positional local path, `--from-pub <name>`, or
  `--from-git <url> --ref <ref>`. The 11 packages published at
  [`fluttertv/plugins`](https://github.com/fluttertv/plugins) /
  [pub.dev/publishers/fluttertv.dev](https://pub.dev/publishers/fluttertv.dev/packages)
  were all produced this way. Built in 7 phases — scaffold → copy
  native verbatim → Swift transformer → Objective-C transformer →
  `--include-example` → fetch loaders → polish. The transformer:
  - widens Swift `#if os(iOS)` / `#elseif os(macOS)` and
    Objective-C `#if TARGET_OS_IOS` so tvOS follows the iOS branch
    (UIKit / AVFoundation / Flutter embedder shape);
  - widens `@available iOS X, *` / `#available` /
    `API_AVAILABLE(ios())` to also list `tvOS X` (Apple ships
    those symbols on tvOS at the same OS version);
  - matches a compatibility database of tvOS-incompatible APIs
    (WebKit, SafariServices, LocalAuthentication, CoreLocation,
    CaptiveNetwork, NEHotspot, StoreKit code-redemption,
    `UIPasteboard`, `AVAudioSession` Bluetooth / speaker options,
    CoreTelephony, GoogleSignIn SDK, …) and either strips the
    import + stubs the enclosing method-channel handler, or wraps
    type-level uses behind `#if !os(tvOS)` (graceful partial port —
    package still compiles with the feature disabled);
  - collapses modern multi-target SwiftPM packages (Swift API +
    `_objc` / `_ios` / `_macos` siblings) into one CocoaPods module,
    dropping the macOS-only target;
  - emits a buildable Swift skeleton for FFI / native-assets
    plugins (`dart:ffi` + `package:objective_c` + `hook/build.dart`)
    that the tvOS toolchain can't build for as-is, so the user
    still gets a working scaffold to hand-finish;
  - prunes cross-platform Dart from the generated `lib/` —
    `_plus`-style packages bundle Linux / Windows / Web / macOS /
    Android implementations alongside the iOS one; none reachable
    at runtime on tvOS, and their transitive imports
    (`package:web`, `flutter_web_plugins`, `win32`, `package:nm`,
    …) aren't in the generated pubspec, so shipping them inflates
    the package and breaks `pana` / `dart pub publish` analysis.
  Every transformation is recorded in a `PORTING_REPORT.md`
  written alongside the package.
- **`flutter-tvos create --platforms=tvos` / `--tvos-only`** —
  first-class tvOS-only project scaffold. No more
  "create-iOS-then-strip" — the generated project ships a
  `tvos/` Apple TV target only, with no iOS / Android / web /
  desktop platforms to delete by hand.
- **Build-time warning for plugins missing tvOS support.** During
  `flutter-tvos build/run`, each plugin in the app's dep graph
  that has a FlutterTV-published `<name>_tvos` sibling the user
  hasn't added is surfaced as a one-line warning, e.g.
  `audioplayers_tvos is available on pub.dev under the fluttertv.dev
  verified publisher. Did you forget to add it to pubspec.yaml?`.
  Keyed on the user-facing aggregator name, so the federated iOS
  implementation (`audioplayers_darwin`) and platform-specific
  siblings (`audioplayers_android`, `audioplayers_linux`, …) don't
  produce duplicate or noisy warnings. Plugins outside the
  curated list are silently ignored.
- **`doc/port-plugin.md`** — proper user guide for `plugin port`,
  matching the existing `doc/` style: quick start, full flag
  reference, what the transformer does and doesn't do, after-
  porting workflow, troubleshooting.

### Fixed
- `flutter-tvos build/run` now reads the app's `version:` from
  `pubspec.yaml` and writes the parsed `FLUTTER_BUILD_NAME` /
  `FLUTTER_BUILD_NUMBER` into `Generated.xcconfig` (`1.2.3+4` →
  `1.2.3` / `4`). Previously they were hardcoded to `1.0.0` / `1`
  unless explicitly passed via `--build-name` / `--build-number`,
  which broke `package_info_plus` and any code reading
  `CFBundleShortVersionString` / `CFBundleVersion`. Resolution
  order now matches iOS via `xcode_backend.dart`: CLI flag →
  `project.manifest.buildName` / `buildNumber` → canonical
  default.
- `FLTAssetsPath` is now baked into the generated `Info.plist` so
  Flutter's plugin asset lookup (`Asset` / `lookupKey(forAsset:)`)
  resolves correctly on a real Apple TV — previously only worked
  on the simulator.
- Device builds now pass `-allowProvisioningUpdates` to xcodebuild
  so the first build on a fresh team / device can refresh
  provisioning profiles itself instead of failing.
- Tvos build skips the Dart native-assets target so an app that
  transitively pulls in an FFI / native-assets plugin (e.g.
  `path_provider_foundation`, `package_info_plus`) no longer
  fails with `Target native_assets required define SdkRoot` on
  first build (issue #3).

### Documentation
- README's plugin-porting section is now a 4-line pointer to
  `doc/port-plugin.md`. The platform-key paragraph also points
  at the published
  [`fluttertv/plugins`](https://github.com/fluttertv/plugins) repo
  and the
  [`fluttertv.dev`](https://pub.dev/publishers/fluttertv.dev/packages)
  verified publisher in place of the older "FlutterTV-curated
  index being assembled and will be published soon" wording.
- `doc/` index gains "Porting an existing plugin" under "Plugin
  development".

## [1.0.1] — 2026-05-20

Patch release updating the pinned Flutter SDK and tvOS engine artifacts to Flutter 3.41.9.

### Changed
- Updated `bin/internal/flutter.version` to Flutter `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`.
- Updated `bin/internal/engine.version` to `v1.0.0-flutter3.41.9`.
- Published matching tvOS engine artifacts for debug, profile, release, simulator, and host tooling.

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
