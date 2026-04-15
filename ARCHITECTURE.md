# flutter-tvos Architecture

## Overview

`flutter-tvos` is a Dart CLI tool that acts as a Flutter tvOS custom embedder. It wraps an unmodified Flutter 3.41.4 SDK and injects tvOS-specific overrides via Flutter's dependency injection system (`runner.run()` with `overrides: <Type, Generator>{}`). It follows the same architectural pattern as flutter-tizen, flutter-elinux, and flutter-webos.

The CLI is designed to feel identical to the standard `flutter` CLI for end users — the same commands (`build`, `run`, `devices`, `doctor`, `clean`) work as expected, with the platform layer swapped out for tvOS.

---

## Entry Points

| File | Role |
|------|------|
| `bin/flutter-tvos` | Shell entry point — bootstraps the Flutter SDK, compiles the Dart snapshot, and executes it |
| `lib/executable.dart` | Dart entry point — registers all CLI commands and DI overrides |
| `bin/cache/flutter-tvos.snapshot` | Compiled Dart bytecode (auto-generated at first run, invalidated by stamp file) |

---

## Dependency Injection Overrides

Flutter's CLI is built around a service locator pattern. `flutter-tvos` extends it by replacing key services with tvOS-aware implementations. All overrides are registered in `lib/executable.dart`:

| Override Type | Implementation Class | Purpose |
|---------------|---------------------|---------|
| `ApplicationPackageFactory` | `TvosApplicationPackageFactory` | Resolves the tvOS `.app` bundle from the `tvos/` project directory |
| `Artifacts` | `TvosArtifacts` | Resolves `Flutter.framework` and `gen_snapshot` from `engine_artifacts/` |
| `Cache` | `TvosFlutterCache` | Manages downloading and extracting tvOS engine artifact zips |
| `DeviceManager` | `TvosDeviceManager` | Adds tvOS simulator discovery via `xcrun simctl` |
| `DoctorValidatorsProvider` | `TvosDoctorValidatorsProvider` | Validates Xcode installation and tvOS SDK availability |
| `BuildTargets` | `BuildTargetsImpl` | Routes build system calls to tvOS-specific build targets |
| `TvosValidator` | `TvosValidator` | tvOS-specific doctor checks (SDK, codesigning, etc.) |

---

## Directory Layout

```
flutter-tvos/
├── bin/
│   ├── flutter-tvos              # Shell entry point
│   ├── flutter_tvos.dart         # Dart entry (compiled to snapshot)
│   ├── cache/                    # Compiled snapshot + stamp file
│   └── internal/
│       ├── flutter.version       # Flutter SDK commit to check out
│       ├── engine.version        # Engine version stamp
│       └── shared.sh             # Shell helpers (update_flutter, setup_proxy_root)
├── lib/
│   ├── executable.dart           # Main: DI overrides + command registration
│   ├── tvos_artifacts.dart       # Artifact path resolution (Flutter.framework, gen_snapshot)
│   ├── tvos_cache.dart           # Engine artifact download/extraction
│   ├── tvos_build_info.dart      # Build configuration (mode, arch, simulator flag)
│   ├── tvos_build_system.dart    # FlutterBuildSystem extension
│   ├── tvos_builder.dart         # Static buildBundle() orchestrator
│   ├── tvos_device.dart          # tvOS device representation
│   ├── tvos_device_discovery.dart # Simulator detection via xcrun simctl
│   ├── tvos_doctor.dart          # Doctor validators
│   ├── tvos_project.dart         # tvOS project directory management
│   ├── tvos_application_package.dart # .app bundle representation
│   ├── tvos_emulator.dart        # Simulator lifecycle management
│   ├── tvos_plugins.dart         # Native plugin handling
│   ├── vscode_helper.dart        # VS Code launch.json configuration
│   ├── commands/                 # CLI command implementations
│   │   ├── build.dart            # flutter-tvos build tvos [--simulator] [--debug|--release]
│   │   ├── run.dart              # flutter-tvos run -d <device>
│   │   ├── clean.dart            # flutter-tvos clean
│   │   ├── devices.dart          # flutter-tvos devices
│   │   ├── attach.dart           # flutter-tvos attach
│   │   ├── create.dart           # flutter-tvos create
│   │   ├── drive.dart            # flutter-tvos drive
│   │   ├── precache.dart         # flutter-tvos precache
│   │   └── test.dart             # flutter-tvos test
│   └── build_targets/
│       ├── application.dart      # xcodebuild orchestration (core native build logic)
│       └── package.dart          # Plugin packaging
├── flutter/                      # Flutter SDK checkout (managed by shared.sh)
├── engine_artifacts/             # Extracted engine zips (tvos_debug_sim_arm64/, etc.)
└── proxy_root/                   # Symlinks allowing xcodebuild to locate Flutter
    ├── bin/dart → flutter/bin/cache/dart-sdk/bin/dart
    ├── bin/flutter → shell wrapper calling flutter-tvos
    └── packages → flutter/packages
```

---

## Build Flow

What happens when you run `flutter-tvos build tvos --simulator --debug`:

1. `TvosBuildCommand.runCommand()` creates a `TvosBuildInfo` capturing architecture, build mode, and the simulator flag.
2. `TvosBuilder.buildBundle()` sets up the Flutter build environment.
3. The `DebugTvosApplication` build target runs the kernel snapshot (Dart-to-bytecode compilation).
4. `NativeTvosBundle.build()` orchestrates the native side:
   - **Copy Flutter.framework** — copies the pre-built framework from `engine_artifacts/`
   - **Copy Metal libraries** — copies pre-compiled tvOS Metal shaders from templates
   - **Copy Flutter assets** — places `kernel_blob.bin` and asset bundle into `tvos/Flutter/flutter_assets/`
   - **Generate plugin registrant stubs** — creates initial Objective-C `.h`/`.m` stubs if not present
   - **AOT snapshot** (release/profile only) — runs `gen_snapshot` to produce `App.framework`
   - **Generate Xcode configs** — writes `Generated.xcconfig`, `Debug.xcconfig`, `Release.xcconfig`
   - **`ensureReadyForTvosTooling()`** — discovers tvOS plugins, writes `.flutter-plugins-dependencies` with a `plugins.tvos` key, generates `GeneratedPluginRegistrant.swift` and the Objective-C `.m` with `@import` and registration calls. Runs after `pub get` to ensure the dependencies file reflects the tvOS key.
   - **`pod install`** — runs if a `Podfile` is present; the Podfile reads `plugins.tvos` to resolve CocoaPods dependencies
   - **`xcodebuild`** — invokes `-workspace Runner.xcworkspace -scheme Runner -sdk appletvsimulator -configuration Debug build` (uses `-workspace` when CocoaPods are present, `-project` otherwise)
5. Output: `build/tvos/Debug-appletvsimulator/Runner.app`

---

## Run Flow

What happens when you run `flutter-tvos run -d <device_id>`:

1. The base `RunCommand.runCommand()` calls `TvosDevice.startApp()`.
2. `startApp()` triggers the full build via `TvosBuilder.buildBundle()`.
3. `xcrun simctl boot <device_id>` brings the simulator up; `open -a Simulator` opens the UI.
4. `xcrun simctl install <device_id> <app_path>` installs the built `.app`.
5. A unified log stream is started: `xcrun simctl spawn <device_id> log stream --style json --predicate 'senderImagePath ENDSWITH "/Flutter"'`
6. `xcrun simctl launch <device_id> <bundle_id>` launches the app.
7. `ProtocolDiscovery` scans the log stream for the VM service URI printed by the Flutter runtime.
8. `LaunchResult.succeeded(vmServiceUri: ...)` is returned to the base `RunCommand`.
9. The base `RunCommand` creates a `HotRunner`, enabling hot reload (`r`), hot restart (`R`), DevTools (`d`), and quit (`q`).

---

## Artifact Resolution

`TvosArtifacts._getDirectoryName()` maps a build configuration to an artifact directory name inside `engine_artifacts/`:

| Build Mode | Environment | Directory |
|------------|-------------|-----------|
| debug | Simulator | `tvos_debug_sim_arm64` |
| debug | Physical device | `tvos_debug_arm64` |
| profile | Physical device | `tvos_profile_arm64` |
| release | Physical device | `tvos_release_arm64` |

Within each directory, the artifact resolver looks for:

- `Flutter.framework` — pre-built tvOS Flutter framework
- `Flutter.xcframework` — XCFramework variant
- `clang_arm64/gen_snapshot` — AOT compiler (profile and release only)

---

## Artifact Sources

`TvosFlutterCache` downloads engine artifacts from `github.com/fluttertv/engine-artifacts`,
or from a custom URL set via the `TVOS_ENGINE_BASE_URL` environment variable.

Zips are extracted into `engine_artifacts/` at first use and cached locally. The `engine.version`
stamp file tracks whether the cached artifacts are current.

---

## Plugin System

Flutter's standard plugin discovery does not recognize a `tvos` platform key in `pubspec.yaml` — only `android`, `ios`, `linux`, `macos`, `web`, and `windows` are handled by the upstream `Plugin` class.

`flutter-tvos` works around this in `tvos_plugins.dart` with a custom `_discoverTvosPlugins()` function that:

1. Reads the `dependencyGraph` from `.flutter-plugins-dependencies`
2. Locates each package via `package_config.json`
3. Parses each package's `pubspec.yaml` directly to extract any `tvos:` platform section

This allows plugin authors to declare tvOS support using a `tvos:` key in their pubspec without any changes to the Flutter SDK.

### Plugin types

| Type | Integration mechanism |
|------|-----------------------|
| Method channel (native) | Objective-C registrant `.m`, compiled by Xcode |
| FFI | `DynamicLibrary.open()` / `DynamicLibrary.process()` at runtime; native code delivered as a CocoaPod |
| Dart-only | No native integration needed |
| Hybrid | Both method channel and FFI |

FFI plugins are not added to the plugin registrant — they are linked and loaded at runtime via CocoaPods.

---

## Implementation Notes

- **Private fields in base classes** — `CachedArtifacts`, `FlutterBuildSystem`, and related Flutter 3.41.4 classes use private fields (`_fileSystem`, `_platform`). Subclasses must pass all named parameters directly to the `super()` constructor.
- **`BuildMode` has no `.isDebug` getter** — compare explicitly: `buildMode == BuildMode.debug`.
- **`Generator` typedef** — imported from `package:flutter_tools/src/context_runner.dart`; this import is required in `executable.dart`.
- **Simulator builds require debug mode** — release and profile builds need `gen_snapshot` for AOT compilation, which targets a physical device.
- **`proxy_root` symlinks** — rebuilt at build time. Must be regenerated if the Flutter SDK path changes.
- **`flutter/` is a managed SDK checkout** — `shared.sh` handles cloning and pinning. Do not commit changes to this directory.
- **Plugin registrant is Objective-C, not Swift** — Xcode compiles `Runner/GeneratedPluginRegistrant.m`. The Swift file in `Flutter/` is not referenced by the Xcode project. Both are produced by `ensureReadyForTvosTooling()`.
- **Podspec dependencies on Flutter** — Plugin podspecs must not use `s.dependency 'Flutter'` because the Flutter pod does not declare tvOS support. Use `s.xcconfig = { 'FRAMEWORK_SEARCH_PATHS' => '"${PODS_ROOT}/../Flutter"' }` instead.

---

## Testing

Unit tests use Flutter's own test infrastructure (`FakeProcessManager`, `testWithoutContext`, `testUsingContext`), re-exported from `test/src/`.

```bash
# Run all tests
flutter/bin/dart test test/

# Run a specific test file
flutter/bin/dart test test/general/tvos_emulator_test.dart
```

### Test structure

```
test/
├── src/          # Re-exports from Flutter's test infrastructure
└── general/      # Component unit tests
```

### Test coverage

| Test file | What it covers |
|-----------|----------------|
| `tvos_build_info_test.dart` | SDK name, destination, build mode mapping |
| `tvos_emulator_test.dart` | `simctl` JSON parsing, tvOS runtime filtering, error handling |
| `tvos_device_test.dart` | Unified log reader, device properties, build modes |
| `tvos_device_discovery_test.dart` | Workflow integration, platform capabilities |
| `tvos_doctor_test.dart` | Xcode validation, macOS platform check |
| `tvos_application_package_test.dart` | Bundle path resolution, app naming |
| `tvos_plugins_test.dart` | Plugin discovery, Podfile resolution, workspace detection, all plugin types |
| `tvos_plugin_template_test.dart` | Swift template generation, class name conversion, pubspec patching, podspec |
| `tvos_code_signing_test.dart` | `.pbxproj` parsing, keychain identity, simulator vs device signing |
| `tvos_clean_test.dart` | Build artifact identification, missing directory handling |
| `tvos_physical_device_test.dart` | `devicectl` JSON parsing, physical device properties, log reader |
