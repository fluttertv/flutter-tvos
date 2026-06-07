# Changelog

All notable changes to flutter-tvos will be documented here.

## [1.2.0] — 2026-06-05

Minor release. Upgrades the pinned engine to Flutter **3.44.1**, makes
Impeller's Metal shaders tvOS-native (retiring the per-app
`MetalLibInterposer` hack), and makes on-device **debug + hot reload +
DevTools work over a wireless Apple TV** by mirroring stock Flutter iOS's
lldb→Xcode-debugger launch flow.

### Added
- **On-device wireless debugging that works like stock Flutter iOS.**
  `TvosDevice` mirrors `IOSDevice._startAppOnCoreDevice`: it attaches lldb
  over the wireless CoreDevice tunnel, then resolves the Dart VM Service
  over mDNS at the device's LAN IP, so hot reload (`r`), hot restart
  (`R`), and DevTools (`d`) come for free from the base `HotRunner`.
  Verified end-to-end on a physical Apple TV (tvOS 18.6).

  This requires a matching **engine fix**: the tvOS debug engine now ships
  the `NOTIFY_DEBUGGER_ABOUT_RX_PAGES` Dart-VM hook that lldb breakpoints
  during attach. Without it the attach never completes. The hook is in the
  updated `v1.0.0-flutter3.44.1` engine artifact — existing checkouts must
  run `flutter-tvos precache --force` to pick it up. (Engine change:
  `fluttertv/engine` PR #1.)

  The lldb attach timeout is configurable via
  `FLUTTER_TVOS_LLDB_ATTACH_TIMEOUT_SECONDS` (default 180s) for slow
  networks. If lldb still can't attach, the run falls back to driving the
  **Xcode debugger** (`XcodeDebug.debugApp` via AppleScript against the
  generated `tvos/Runner.xcworkspace` + `Runner` scheme) as a best-effort
  backstop; the first such run prompts to allow controlling Xcode
  (Settings ▸ Privacy & Security ▸ Automation). On failure the tool prints
  actionable guidance (restart the Apple TV to reset the CoreDevice tunnel,
  check Local Network permission, or use the simulator).

### Changed
- **Impeller Metal shaders are now compiled tvOS-native in the engine
  artifact** and embedded in `Flutter.framework`, loading directly on the
  Apple TV GPU exactly like iOS. The per-app `tvos_metallibs/` directory
  and the `MetalLibInterposer` (which swizzled `newLibraryWithData:` to
  swap shaders matched by byte size) are **removed** from the app template
  and the `flutter_tvos` example. Newly created / regenerated projects no
  longer carry the interposer source or the bridging-header entry.

### Fixed
- **App.framework is now embedded for App Store / TestFlight builds**
  ([#18](https://github.com/fluttertv/flutter-tvos/issues/18)). Embedding the
  AOT `App.framework` was previously a post-build step inside the CLI, so it
  only patched the `Runner.app` left in `SYMROOT` and never ran for an Xcode
  `archive`. Archived builds therefore shipped without `App.framework` and
  crashed on launch on a real Apple TV. Embedding now happens inside the Xcode
  project as an **"Embed App.framework" build phase**, which runs for build,
  run, *and* archive, and codesigns the framework with Xcode's resolved
  identity (`${EXPANDED_CODE_SIGN_IDENTITY}`). Projects created before this
  phase existed are unaffected for CLI builds: a backward-compatible fallback
  in `flutter-tvos build/run` still embeds + signs `App.framework` when the
  build phase is absent. (To archive a legacy project directly through Xcode
  for TestFlight, regenerate the tvOS project so it picks up the build phase.)
- **App.framework's `Info.plist` now passes App Store validation**
  ([#18](https://github.com/fluttertv/flutter-tvos/issues/18)). The generated
  plist gained `CFBundleShortVersionString`, `CFBundleSupportedPlatforms`
  (`AppleTVOS`), `DTPlatformName`, `UIDeviceFamily` (`[3]`), and a tvOS
  `MinimumOSVersion`, so the framework no longer fails archive validation for
  missing keys.
- **`flutter_assets` are no longer duplicated one level deep on rebuilds**
  ([#18](https://github.com/fluttertv/flutter-tvos/issues/18)). The asset copy
  used `cp -R <src>/assets <target>/assets` without clearing the target, so a
  second build nested the tree into the existing directory
  (`flutter_assets/assets/assets/…`). The copy now wipes the target first and
  uses a pure-Dart recursive copy, producing an exact mirror every time.

### Engine
- Updated to Flutter **3.44.1**
  (`924134a44c189315be2148659913dda1671cbe99`, Dart 3.12.1).
- Updated `bin/internal/engine.version` to `v1.0.0-flutter3.44.1`.
- Matching tvOS engine artifacts published at
  [`fluttertv/engine-artifacts@v1.0.0-flutter3.44.1`](https://github.com/fluttertv/engine-artifacts/releases/tag/v1.0.0-flutter3.44.1).
  Engine-side changes live in
  [`fluttertv/engine#1`](https://github.com/fluttertv/engine/pull/1):
  tvOS-native Impeller metallibs, and an Impeller `StrokedCircle` fix
  that no longer aborts (a debug-build `DCHECK`) when the stroke
  half-width ≥ radius — e.g. the widget inspector outlining a small
  circular element.

### Compatibility
- **Existing apps keep working without changes.** Apps built with an
  older template still ship a `MetalLibInterposer`; against the 3.44.1
  engine its byte-size-keyed swizzle simply finds no match and goes
  inert — the engine's own tvOS-native shaders are used instead. To drop
  the now-dead interposer files, recreate the `tvos/` runner or delete
  `Runner/MetalLibInterposer.*`, `Runner/tvos_metallibs/`, and the
  bridging-header `#import`.

### Tests
- Added `TvosDevice.parseDeviceUdid` unit coverage (extract UDID from
  `devicectl` JSON, null on missing / malformed) in
  `tvos_physical_device_test.dart`.

## [1.1.1] — 2026-05-28

Patch release. No Flutter SDK or engine-artefact change — pinned
versions match v1.1.0.

### Fixed
- `--obfuscate` and `--split-debug-info` are now honoured by
  release/profile (AOT) builds. The tvOS AOT step runs `gen_snapshot`
  directly (rather than going through upstream `AOTSnapshotter`), and
  previously dropped these flags entirely — the build succeeded but the
  `App` binary kept readable Dart symbols and the split-debug-info
  directory stayed empty. The gen_snapshot invocation now forwards
  `--obfuscate`, the `--dwarf-stack-traces` / `--resolve-dwarf-paths` /
  `--save-debugging-info=<dir>/app.tvos-arm64.symbols` trio, and any
  `--extra-gen-snapshot-options`, matching upstream
  `AOTSnapshotter.build` (issue #10).

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

### Engine
- Updated to Flutter **3.44.0** (`559ffa3f75e7402d65a8def9c28389a9b2e6fe42`).
- Updated `bin/internal/engine.version` to `v1.0.0-flutter3.44.0`.
- Bumped `packages/flutter_tvos` to `1.0.5`.

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
