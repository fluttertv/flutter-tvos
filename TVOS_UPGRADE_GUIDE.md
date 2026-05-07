# Flutter tvOS Engine — Version Upgrade Guide

This document describes how to upgrade the tvOS engine patches when a new Flutter version is released. It covers the full workflow: from setting up the new Flutter monorepo to building and running a tvOS app on both device and simulator.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [High-Level Upgrade Workflow](#high-level-upgrade-workflow)
3. [Step 1 — Clone & Configure the New Flutter Version](#step-1--clone--configure-the-new-flutter-version)
4. [Step 2 — Port Engine Source Patches](#step-2--port-engine-source-patches)
   - [2a. Build System Files (4 files)](#2a-build-system-files-4-files)
   - [2b. FML / Impeller (5 files)](#2b-fml--impeller-5-files)
   - [2c. Darwin/iOS Platform Layer (20+ files)](#2c-darwinios-platform-layer-20-files)
   - [2d. New Files (2 files)](#2d-new-files-2-files)
5. [Step 3 — Port Third-Party Patches (Skia & Perfetto)](#step-3--port-third-party-patches-skia--perfetto)
6. [Step 4 — Port Flutter Tools Patches](#step-4--port-flutter-tools-patches)
7. [Step 5 — Create clang Runtime Libraries](#step-5--create-clang-runtime-libraries)
8. [Step 6 — Build the Engine](#step-6--build-the-engine)
9. [Step 7 — Build & Run the Demo App](#step-7--build--run-the-demo-app)
10. [Troubleshooting](#troubleshooting)
11. [Architecture Reference](#architecture-reference)

---

## Prerequisites

- **macOS** with Xcode installed (including AppleTVOS and AppleTVSimulator SDKs)
- **Apple Silicon** Mac (arm64) — or adjust simulator-cpu flags for Intel
- **depot_tools** in PATH: `export PATH="/path/to/depot_tools:$PATH"`
- **Python 3**, **ninja**, **git**
- Previous Flutter tvOS engine monorepo (as patch reference)

---

## High-Level Upgrade Workflow

```
1. Clone new Flutter version monorepo
2. Configure .gclient, run gclient sync
3. Port all engine source patches (29 files + 2 new)
4. Re-generate & apply Skia/Perfetto patches
5. Port flutter_tools patches (4 files)
6. Create libclang_rt.tvos.a and libclang_rt.tvossim.a
7. Build engine (device, simulator, host)
8. Build demo app and test on simulator/device
```

---

## Step 1 — Clone & Configure the New Flutter Version

### 1a. Set Up Directory Structure

```bash
mkdir flutter_tvos_engine_monorepo && cd flutter_tvos_engine_monorepo
git clone https://github.com/flutter/flutter.git flutter_upstream_NEW
cd flutter_upstream_NEW
git checkout <NEW_VERSION_TAG>  # e.g. 3.41.1, 3.50.0, etc.
```

### 1b. Configure `.gclient`

Create `flutter_upstream_NEW/.gclient`:

```python
solutions = [
  {
    "managed": False,
    "name": ".",
    "url": "https://github.com/flutter/flutter.git",
    "custom_deps": {},
    "deps_file": "DEPS",
    "safesync_url": "",
    "custom_vars": {
      "download_android_deps": False,
      "download_emsdk": False,
      "download_linux_deps": False,
      "download_windows_deps": False,
    },
  },
]
```

### 1c. Sync Dependencies

```bash
cd flutter_upstream_NEW
export PATH="/path/to/depot_tools:$PATH"
gclient sync --no-history --shallow -j8
```

This fetches engine, Skia, Perfetto, and all other dependencies.

---

## Step 2 — Port Engine Source Patches

The tvOS patches modify ~29 files and add 2 new ones. For each file, compare the old patched version against the new upstream version and re-apply the tvOS-specific changes.

**Key Patterns Used Throughout:**

| Pattern | Usage |
|---------|-------|
| `#if TARGET_OS_TV` | Guard tvOS-specific code |
| `#if !TARGET_OS_TV` | Exclude code not available on tvOS |
| `#if !(defined(TARGET_OS_TV) && TARGET_OS_TV)` | Non-ObjC contexts (C/C++) |
| `@available(..., tvOS X.Y, ...)` | Runtime API availability |

### 2a. Build System Files (4 files)

These configure the GN/ninja build to target appletvos/appletvsimulator SDKs.

#### `engine/src/build/config/darwin/darwin_sdk.gni`
- Change iOS SDK paths to use `appletvos` / `appletvsimulator`
- Update Swift library paths from `iphoneos` → `appletvos` and `iphonesimulator` → `appletvsimulator`

**What to look for in new version:** SDK path variable names, any new Swift package search paths.

#### `engine/src/build/config/darwin/BUILD.gn`
- Set `_triplet_os = "apple-tvos"` where the original sets `"apple-ios"`

**What to look for:** Any new platform-specific triplet handling.

#### `engine/src/build/mac/darwin_sdk.py`
- Add `'appletvos'` and `'appletvsimulator'` to the `SDKS` list (replacing/supplementing `iphoneos`/`iphonesimulator`)

**What to look for:** New SDK enumeration logic.

#### `engine/src/build/toolchain/mac/BUILD.gn`
- Replace `-miphoneos-version-min=` with `-mtvos-version-min=` in sysroot flags

**What to look for:** New compiler/linker flag handling, min version flags.

### 2b. FML / Impeller (5 files)

#### `engine/src/flutter/fml/build_config.h`
- Add `TARGET_OS_TV` to the `FML_OS_IOS` detection:
  ```c
  #if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || \
      (defined(TARGET_OS_TV) && TARGET_OS_TV)
  #define FML_OS_IOS 1
  ```

**What to look for:** New platform detection macros, any refactoring of the FML_OS_* defines.

#### `engine/src/flutter/impeller/tools/metal_library.py`
- Add `'appletvos'` to the SDK list
- Add `-mtvos-version-min=13.0` alongside existing `-mios-version-min`

**What to look for:** Metal shader compilation pipeline changes, new SDK arguments.

#### `engine/src/flutter/impeller/tools/shaders_mtl.gni`
- Add `--metal-tvos` shader compilation flag

**What to look for:** New shader compilation GNI templates.

#### `engine/src/flutter/impeller/renderer/backend/metal/command_buffer_mtl.mm`
- Add `tvOS(14.0)` to `@available` and `API_AVAILABLE` annotations

#### `engine/src/flutter/impeller/renderer/backend/metal/sampler_library_mtl.mm`
- Add `tvOS(14.0)` or `tvOS(16.0)` to `@available` annotations

**What to look for in Impeller files:** New Metal backend files, new `@available` checks that need tvOS equivalents, new GPU feature detection.

### 2c. Darwin/iOS Platform Layer (20+ files)

This is the largest set of patches — the iOS platform layer under `engine/src/flutter/shell/platform/darwin/ios/`.

#### `BUILD.gn` (ios/BUILD.gn)
- Add new source files (`FlutterAccessibilitySelectionView.h`, `.mm`)
- Replace `WebKit.framework` with `GameController.framework` + `MediaPlayer.framework`
- Conditionally link `IOKit.framework` for simulator only:
  ```gn
  if (defined(use_ios_simulator) && use_ios_simulator) {
    frameworks += [ "IOKit.framework" ]
  }
  ```
- Comment out test sources (they depend on iOS-only APIs)

**What to look for:** New framework dependencies, new source files, test source lists.

#### `rendering_api_selection.mm`
- Force Metal on tvOS (Metal is always available):
  ```objc
  #if defined(TARGET_OS_TV) && TARGET_OS_TV
    ios_version_supports_metal = true;
  ```

#### `FlutterViewController.h` / `FlutterViewController.mm`
- Add `getAccessibilitySelectionView` method declaration
- Guard orientation APIs (`setNeedsStatusBarAppearanceUpdate`, `supportedInterfaceOrientations`)
- Add Siri Remote / gamepad input handling via `GameController.framework`
- Guard keyboard-related methods
- Guard status bar appearance and home indicator deferral

**⚠️ HIGH CHURN FILE** — This is the most likely file to have conflicts on upgrade. Review carefully.

#### `FlutterPlatformPlugin.mm`
- Extensive `#if !TARGET_OS_TV` guards around:
  - Haptic feedback
  - Status bar / home indicator
  - Clipboard (partial — some clipboard works on tvOS)
  - System navigation pop
  - URL launching
  
**⚠️ HIGH CHURN FILE**

#### `FlutterTextInputPlugin.h` / `FlutterTextInputPlugin.mm`
- Guard Scribble/handwriting interaction
- Guard edit menu / keyboard autocorrection
- Guard `UITextInputAssistantItem`
- Guard clipboard operations that use `UIMenuController`

**⚠️ HIGH CHURN FILE**

#### `FlutterPlatformViews.mm`
- Guard `#import <WebKit/WebKit.h>`
- Guard touch-related properties

#### `SemanticsObject.h` / `SemanticsObject.mm`
- Guard `FlutterSwitchSemanticsObject` (UISwitch unavailable on tvOS)
- Guard `accessibilityAttributedValue` spell-out

#### `accessibility_bridge.mm`
- Guard focus tracking / selection overlay
- Guard hit-test behavior

#### `FlutterAccessibilitySelectionView.h` / `.mm` **(NEW FILES)**
- UIView subclass for tvOS accessibility focus overlay
- Must be created fresh (copy from previous version)

#### `FlutterPlugin.h` / `FlutterPluginAppLifeCycleDelegate.h` / `.mm`
- Guard notification registration methods
- Guard `application:performActionForShortcutItem:` (3D Touch)

#### `FlutterAppDelegate.mm`
- Guard lifecycle methods not available on tvOS

#### `FlutterEngine.mm`
- Guard platform-specific registrations

#### `FlutterSceneLifeCycle.mm` / `vsync_waiter_ios.mm` / `ios_surface.mm`
- Guard `CAFrameRateRangeMake` (ProMotion — tvOS doesn't support variable refresh)
- Guard `windowScene.screen` access
- Guard Impeller availability pragmas

#### `FlutterDartProject.mm`
- Guard wide gamut color support check

#### `FlutterUndoManagerPlugin.mm`
- Use `inputDelegate` instead of `inputAssistantItem` on tvOS

#### `profiler_metrics_ios.mm`
- Return `std::nullopt` on tvOS (profiling APIs unavailable)

### 2d. New Files (2 files)

These must be **created** in the new version (they don't exist upstream):

1. `engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterAccessibilitySelectionView.h`
2. `engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterAccessibilitySelectionView.mm`

Copy from the previous working version and register them in `BUILD.gn`.

---

## Step 3 — Port Third-Party Patches (Skia & Perfetto)

Third-party dependencies are fetched by `gclient sync`, so patches must be re-generated for each new version.

### 3a. Skia Patches (4 files)

The Skia revision changes with each Flutter release. Check `DEPS` for the new Skia hash:

```bash
grep "skia_revision" engine/src/flutter/DEPS
```

**Files to patch:**

| File | Patch Description |
|------|-------------------|
| `src/gpu/ganesh/mtl/GrMtlCaps.mm` | GPU family detection — add tvOS GPU Family 1/2 |
| `src/gpu/ganesh/mtl/GrMtlCommandBuffer.mm` | Command buffer descriptor guarding |
| `src/gpu/ganesh/mtl/GrMtlGpu.mm` | Unified memory detection guard |
| `src/gpu/graphite/mtl/MtlCaps.mm` | Graphite GPU family support for tvOS |

**Procedure:**
1. After `gclient sync`, `cd` into the Skia directory
2. Apply each change manually by comparing old patch against new Skia source
3. Generate a new patch: `git diff > ../../tvos_patches/skia_tvos.patch`

**What to look for:** Metal GPU family APIs may change. Apple periodically renames GPU family enums. Check Apple's Metal Feature Set Tables for current tvOS GPU family names.

### 3b. Perfetto Patch (1 file)

| File | Patch Description |
|------|-------------------|
| `src/base/utils.cc` | Guard `fork()` in `Daemonize()` — tvOS prohibits fork |

**Procedure:**
1. `cd` into the Perfetto directory
2. Apply the `#if !TARGET_OS_TV` guard around `fork()` calls
3. `git diff > ../../tvos_patches/perfetto_tvos.patch`

### 3c. Save & Update apply_patches.sh

Ensure `tvos_patches/apply_patches.sh` references the correct paths. The Perfetto path may change between Flutter versions:

```bash
# Check current path:
find engine/src -path "*/perfetto/src/base/utils.cc" 2>/dev/null
```

---

## Step 4 — Port Flutter Tools Patches

The `flutter` CLI tool needs patches to recognize tvOS SDKs and engine artifacts.

### 4a. `packages/flutter_tools/lib/src/artifacts.dart`

**Patch:** `_getIosFlutterFrameworkPlatformDirectory` must accept directories prefixed with `tvos-` in addition to `ios-`:

```dart
// Original: only matches ios- prefix
// Patched: also matches tvos- prefix
!platformDirectory.basename.startsWith('ios-') &&
!platformDirectory.basename.startsWith('tvos-')
```

**What to look for:** Any refactoring of artifact resolution paths, new platform directory naming conventions.

### 4b. `packages/flutter_tools/lib/src/ios/xcodeproj.dart`

**Patch:** Change `XcodeSdk` enum display names and platform names:

```dart
// Original:
IPhoneOS(displayName: 'iOS', platformName: 'iphoneos', ...)
IPhoneSimulator(displayName: 'iOS Simulator', platformName: 'iphonesimulator', ...)

// Patched:
IPhoneOS(displayName: 'tvOS', platformName: 'appletvos', ...)
IPhoneSimulator(displayName: 'tvOS Simulator', platformName: 'appletvsimulator', ...)
```

**What to look for:** SDK enum refactoring, new build destination logic, new platform identifiers.

### 4c. `packages/flutter_tools/lib/src/macos/xcode.dart`

**Patch:** `environmentTypeFromSdkroot()` must recognize `appletv` SDK names:

```dart
// Original:
if (sdkName.contains('iphone'))

// Patched:
if (sdkName.contains('iphone') || sdkName.contains('appletv'))
```

**What to look for:** New SDK detection logic, new environment type handling.

### 4d. `packages/flutter_tools/lib/src/macos/swift_packages.dart`

**Patch:** Add tvOS platform to Swift package manifest generation:

```dart
tvos(name: '.tvOS'),
```

### 4e. Clear Cached Snapshots

After modifying flutter_tools, **always** delete the cached snapshot:

```bash
rm -f bin/cache/flutter_tools.snapshot
```

---

## Step 5 — Create clang Runtime Libraries

Flutter's bundled Clang ships `libclang_rt.ios.a` and `libclang_rt.iossim.a` but **not** tvOS variants. You must create them.

### Locate the clang runtime directory:

```bash
CLANG_RT_DIR="engine/src/flutter/buildtools/mac-arm64/clang/lib/clang/*/lib/darwin"
ls $CLANG_RT_DIR/libclang_rt.ios*.a
```

### 5a. Create `libclang_rt.tvos.a` (Device)

```bash
cd /tmp && mkdir tvos_rt && cd tvos_rt

# Extract arm64 slice from the fat iOS library
lipo -thin arm64 $CLANG_RT_DIR/libclang_rt.ios.a -output libclang_rt.ios_arm64.a

# Extract individual objects
ar x libclang_rt.ios_arm64.a

# Patch platform metadata from iOS (2) to tvOS (6) using vtool
for f in *.o; do
  vtool -set-build-version tvos 13.0 26.0 -replace -output "$f" "$f" 2>/dev/null || true
done

# Rebuild archive
ar rcs libclang_rt.tvos.a *.o

# Install
cp libclang_rt.tvos.a $CLANG_RT_DIR/
```

### 5b. Create `libclang_rt.tvossim.a` (Simulator)

```bash
cd /tmp && mkdir tvossim_rt && cd tvossim_rt

# Extract arm64 slice from iOS simulator library
lipo -thin arm64 $CLANG_RT_DIR/libclang_rt.iossim.a -output libclang_rt.iossim_arm64.a

# Extract objects
ar x libclang_rt.iossim_arm64.a

# Patch platform from iOS Simulator (7) to tvOS Simulator (8)
for f in *.o; do
  vtool -set-build-version tvossimulator 13.0 26.0 -replace -output "$f" "$f" 2>/dev/null || true
done

# Verify all objects have correct platform
for f in *.o; do
  platform=$(vtool -show "$f" 2>/dev/null | grep "platform " | awk '{print $2}')
  if [ "$platform" != "TVOSSIMULATOR" ] && [ -n "$platform" ]; then
    echo "WARNING: $f still has platform $platform"
  fi
done

# Rebuild archive
ar rcs libclang_rt.tvossim.a *.o

# Install
cp libclang_rt.tvossim.a $CLANG_RT_DIR/
```

### 5c. Fallback: Binary Patching

If `vtool` fails for some objects (e.g., "not enough space to hold load commands"), use this Python script to binary-patch the Mach-O `LC_BUILD_VERSION` platform field:

```python
#!/usr/bin/env python3
"""Binary-patch LC_BUILD_VERSION platform field in Mach-O objects."""
import struct, sys, os

OLD_PLATFORM = int(sys.argv[1])  # e.g. 7 for IOSSIMULATOR
NEW_PLATFORM = int(sys.argv[2])  # e.g. 8 for TVOSSIMULATOR

for fpath in sys.argv[3:]:
    data = bytearray(open(fpath, 'rb').read())
    # Mach-O 64-bit header: magic(4) + cputype(4) + cpusubtype(4) + filetype(4)
    #   + ncmds(4) + sizeofcmds(4) + flags(4) + reserved(4) = 32 bytes
    offset = 32
    ncmds = struct.unpack_from('<I', data, 16)[0]
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, offset)
        if cmd == 0x32:  # LC_BUILD_VERSION
            plat = struct.unpack_from('<I', data, offset + 8)[0]
            if plat == OLD_PLATFORM:
                struct.pack_into('<I', data, offset + 8, NEW_PLATFORM)
                open(fpath, 'wb').write(data)
                break
        offset += cmdsize
```

Usage:
```bash
# Patch iOS Simulator (7) → tvOS Simulator (8)
python3 patch_platform.py 7 8 *.o

# Patch iOS (2) → tvOS (6)
python3 patch_platform.py 2 6 *.o
```

**Platform IDs Reference:**

| ID | Platform |
|----|----------|
| 2  | iOS (device) |
| 6  | tvOS (device) |
| 7  | iOS Simulator |
| 8  | tvOS Simulator |

---

## Step 6 — Build the Engine

All commands run from `engine/src/` directory with depot_tools in PATH.

### 6a. Host Build

```bash
python3 flutter/tools/gn --runtime-mode debug --unoptimized
ninja -C out/host_debug_unopt
```

### 6b. tvOS Device Build

```bash
python3 flutter/tools/gn --ios --runtime-mode debug --unoptimized
ninja -C out/ios_debug_unopt
```

### 6c. tvOS Simulator Build (arm64 — Apple Silicon)

```bash
python3 flutter/tools/gn --ios --runtime-mode debug --unoptimized --simulator --simulator-cpu=arm64
ninja -C out/ios_debug_sim_unopt_arm64
```

### 6d. Verify Output

```bash
# Device — should show platform TVOS
vtool -show out/ios_debug_unopt/Flutter.framework/Flutter | grep platform

# Simulator — should show platform TVOSSIMULATOR
vtool -show out/ios_debug_sim_unopt_arm64/Flutter.xcframework/tvos-arm64-simulator/Flutter.framework/Flutter | grep platform
```

### 6e. Profile / Release Builds (Optional)

```bash
# Profile device
python3 flutter/tools/gn --ios --runtime-mode profile --no-lto
ninja -C out/ios_profile

# Release device
python3 flutter/tools/gn --ios --runtime-mode release --no-lto
ninja -C out/ios_release
```

---

## Step 7 — Build & Run the Demo App

### 7a. Configure tvOS Demo App

If starting fresh, create a Flutter project and convert it to tvOS:

```bash
flutter create tvos_demo && cd tvos_demo
```

Then modify the Xcode project:
- **project.pbxproj**: Set `SDKROOT = appletvos`, `TVOS_DEPLOYMENT_TARGET = 13.0`, `TARGETED_DEVICE_FAMILY = 3`
- **Info.plist**: Remove iOS-only keys (`UIRequiredDeviceCapabilities`, etc.), set landscape orientations
- **Storyboards**: Use `com.apple.InterfaceBuilder.AppleTV.Storyboard` document type, `targetRuntime="AppleTV"`, 1920x1080 canvas

### 7b. Build for Device

```bash
cd tvos_demo
flutter build ios --debug --no-codesign \
  --local-engine-src-path=/path/to/engine/src \
  --local-engine=ios_debug_unopt \
  --local-engine-host=host_debug_unopt
```

Output: `build/ios/appletvos/Runner.app`

### 7c. Build for Simulator

```bash
flutter build ios --debug --simulator --no-codesign \
  --local-engine-src-path=/path/to/engine/src \
  --local-engine=ios_debug_sim_unopt_arm64 \
  --local-engine-host=host_debug_unopt
```

Output: `build/ios/appletvsimulator/Runner.app`

### 7d. Run on Simulator

```bash
# Boot simulator
xcrun simctl boot "Apple TV 4K (3rd generation)"

# Open Simulator.app
open -a Simulator

# Install
xcrun simctl install booted build/ios/appletvsimulator/Runner.app

# Launch
xcrun simctl launch booted com.example.tvosDemo
```

### 7e. Clean Build (if needed)

```bash
rm -rf build/ios
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
rm -f /path/to/flutter/bin/cache/flutter_tools.snapshot
```

---

## Troubleshooting

### Undefined symbol: `IOServiceGetMatchingServices` (and other IOKit symbols)

**Cause:** IOKit.framework is not available on tvOS device but is available on the simulator.

**Fix:** In `ios/BUILD.gn`, link IOKit conditionally:
```gn
if (defined(use_ios_simulator) && use_ios_simulator) {
  frameworks += [ "IOKit.framework" ]
}
```

### Undefined symbol: `__isPlatformVersionAtLeast`

**Cause:** Missing `libclang_rt.tvos.a` or `libclang_rt.tvossim.a`.

**Fix:** Follow [Step 5](#step-5--create-clang-runtime-libraries) to create the runtime libraries.

### Platform mismatch errors during linking

**Cause:** Object files in `libclang_rt` archive still have iOS/iOSSimulator platform metadata.

**Fix:** Verify all objects with `vtool -show`:
```bash
for f in *.o; do
  vtool -show "$f" 2>/dev/null | grep "platform "
done
```
Use the binary patching script if `vtool -set-build-version` fails.

### `flutter build ios` fails to find engine artifacts

**Cause:** `artifacts.dart` doesn't recognize `tvos-` prefixed directories.

**Fix:** Patch `_getIosFlutterFrameworkPlatformDirectory` to accept `tvos-` prefix (see [Step 4a](#4a-packagesflutter_toolslibsrcartifactsdart)).

### Storyboard errors: "does not support tv device type"

**Cause:** iOS storyboards use `com.apple.InterfaceBuilder3.CocoaTouch.Storyboard`.

**Fix:** Replace with `com.apple.InterfaceBuilder.AppleTV.Storyboard`, set `targetRuntime="AppleTV"`, resolution `1920x1080`.

### `vtool -set-build-version` fails: "not enough space to hold load commands"

**Cause:** Some Mach-O objects don't have enough header padding.

**Fix:** Use the Python binary-patching script from [Step 5c](#5c-fallback-binary-patching) which modifies the platform field in-place without resizing.

### Skia patch fails to apply

**Cause:** Skia revision changed, files were restructured.

**Fix:** Manually inspect the failing hunks. The core pattern is:
- `GrMtlCaps.mm` / `MtlCaps.mm`: Look for `MTLGPUFamily` enum usage and add tvOS families
- `GrMtlGpu.mm`: Look for `hasUnifiedMemory` and guard it
- `GrMtlCommandBuffer.mm`: Look for command buffer descriptor creation

### App crashes on launch with no visible error

**Debug:** Check simulator logs:
```bash
xcrun simctl spawn booted log stream --predicate 'process == "Runner"' --level debug
```

---

## Architecture Reference

### Conditional Compilation Cheat Sheet

```objc
// ObjC/ObjC++ — Is this tvOS?
#if TARGET_OS_TV
  // tvOS-only code
#endif

// ObjC/ObjC++ — Not tvOS (iOS only)
#if !TARGET_OS_TV
  // iOS-only code (touches, UIWebView, status bar, etc.)
#endif

// C/C++ — Is this tvOS? (safer with defined() check)
#if defined(TARGET_OS_TV) && TARGET_OS_TV
  // tvOS code
#endif

// C/C++ — Not tvOS
#if !(defined(TARGET_OS_TV) && TARGET_OS_TV)
  // Non-tvOS code
#endif

// API availability
if (@available(iOS 14.0, tvOS 14.0, *)) {
  // Use newer API
}
```

### APIs Not Available on tvOS

| API/Framework | Notes |
|---------------|-------|
| `WebKit` | No web views on tvOS |
| `UITouch` / touch events | Use `GameController` for Siri Remote |
| `UISwitch` | Use custom toggle widgets |
| `UIMenuController` | No edit menus |
| `UITextInputAssistantItem` | No keyboard assistant bar |
| Scribble / Apple Pencil | Not applicable |
| Status bar / Home indicator | tvOS has no status bar |
| `fork()` | Prohibited on tvOS |
| Haptic feedback | No taptic engine |
| 3D Touch / Force Touch | Not on tvOS |
| `UIApplication.openURL` | Limited on tvOS |
| Variable refresh rate (ProMotion) | tvOS is fixed refresh |
| IOKit (device only) | Available on simulator |

### tvOS-Specific Frameworks Used

| Framework | Purpose |
|-----------|---------|
| `GameController.framework` | Siri Remote, game controllers |
| `MediaPlayer.framework` | Media playback controls |
| `Metal.framework` | GPU rendering (always available on tvOS) |

### GN Build Flags Reference

| Flag | Description |
|------|-------------|
| `--ios` | Target iOS/tvOS platform |
| `--runtime-mode debug` | Debug build with symbols |
| `--unoptimized` | Skip optimizations (faster build) |
| `--simulator` | Build for simulator |
| `--simulator-cpu=arm64` | Target Apple Silicon simulator |
| `use_ios_simulator` | GN variable — true for sim builds |

### File Counts by Category

| Category | Files Modified | New Files |
|----------|---------------|-----------|
| Build system (GN/GNI/Python) | 7 | 0 |
| FML | 1 | 0 |
| Impeller | 4 | 0 |
| Darwin/iOS platform | 20 | 2 |
| Flutter tools | 4 | 0 |
| Skia (patch) | 4 | 0 |
| Perfetto (patch) | 1 | 0 |
| **Total** | **41** | **2** |

---

## Version History

| Flutter Version | Engine Commit | Skia Revision | Status |
|-----------------|---------------|---------------|--------|
| 3.27.4 | LibertyGlobal fork | — | Original tvOS fork |
| 3.41.1 | `582a0e7c558...` | `837be28dd21...` | Migrated ✅ |
| 3.41.4 | `ff37bef6...` | — | Migrated ✅ |

---

## Version-Specific Fixes

### 3.41.4 Additional Patches

When upgrading from 3.41.1 → 3.41.4, two new tvOS-incompatible APIs were introduced in the Dart SDK.
These require source patches **in addition to** the standard tvOS patch set.

#### 1. `process_macos.cc` — `execvp` unavailable on tvOS

**File**: `engine/src/flutter/third_party/dart/runtime/bin/process_macos.cc`

Add `#include <TargetConditionals.h>` near the top of the file, then expand the watchOS guard for `execvp`:

```diff
+#include <TargetConditionals.h>

-#if defined(DART_HOST_OS_WATCH)
+#if defined(DART_HOST_OS_WATCH) || (defined(TARGET_OS_TV) && TARGET_OS_TV)
 // execvp is not available on watchOS or tvOS
```

#### 2. `virtual_memory.h` — Mach JIT exception workarounds unavailable on tvOS

**File**: `engine/src/flutter/third_party/dart/runtime/vm/virtual_memory.h`

The `DART_ENABLE_RX_WORKAROUNDS` macro enables a JIT code-verification mechanism that uses Mach exception ports (`mach_msg_server_once`, `thread_swap_exception_ports`, `thread_set_exception_ports`). These APIs are not available on tvOS.

Since `DART_HOST_OS_IOS` is also defined for tvOS (via `TARGET_OS_IPHONE`), the guard needs an explicit tvOS exclusion:

```diff
 #if defined(DART_HOST_OS_IOS) && !defined(DART_PRECOMPILED_RUNTIME) &&         \
-    !defined(DART_HOST_OS_SIMULATOR)
+    !defined(DART_HOST_OS_SIMULATOR) && !(defined(TARGET_OS_TV) && TARGET_OS_TV)
 #define DART_ENABLE_RX_WORKAROUNDS
 #endif
```

This single change prevents `ScopedExcBadAccessHandler`, `CheckIfRXWorks()`, and related Mach exception code from being compiled for tvOS device builds.
