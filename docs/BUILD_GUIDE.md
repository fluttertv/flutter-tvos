# Flutter tvOS Engine — Build Guide

Repo: https://github.com/MAUstaoglu/flutter_upstream_tvos_engine (private)

This is a patched Flutter 3.44.0 engine source tree with tvOS support. Follow these steps to build the engine artifacts.

**Tested and verified working** — a fresh clone + these steps produces artifacts that run a Flutter demo app on the tvOS simulator.

---

## Prerequisites

- **macOS** with Apple Silicon (M1/M2/M3)
- **Xcode 15+** with the tvOS SDK installed
  - Verify: `xcrun --sdk appletvos --show-sdk-path` should print a path
- **Python 3** (system default works)
- **~60 GB free disk space** (engine source + third-party deps + build outputs)
- **Fast internet** (~15 GB of deps to download)

---

## Step 1 — Install depot_tools

`depot_tools` provides `gclient` (fetches Chromium-style deps) and `ninja` (build driver).

```bash
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git ~/depot_tools
echo 'export PATH="$HOME/depot_tools:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify:
```bash
which gclient     # should print ~/depot_tools/gclient
```

---

## Step 2 — Clone the repo

```bash
git clone https://github.com/MAUstaoglu/flutter_upstream_tvos_engine.git
cd flutter_upstream_tvos_engine
```

---

## Step 3 — Create `.gclient`

This file is **not stored in the repo** — create it manually in the repo root. It tells `gclient` where to fetch deps and disables unneeded Android/Web/Linux/Windows toolchains.

Create a file named `.gclient` with this exact content:

```python
solutions = [
  {
    "managed": False,
    "name": ".",
    "url": "https://github.com/MAUstaoglu/flutter_upstream_tvos_engine.git",
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

> `"managed": False` is **critical** — it prevents gclient from resetting your git checkout (which would wipe the tvOS patches).

---

## Step 4 — Sync third-party dependencies

Downloads Skia, Dart SDK, ANGLE, and other deps into `engine/src/`. Takes 10–30 minutes.

```bash
gclient sync --no-history --shallow
```

If it asks about running hooks, let it run them (they generate `package_config.json` for Dart).

If you ran with `--nohooks` for any reason, run them manually afterwards:
```bash
gclient runhooks
```

---

## Step 5 — Create SDK symlinks

The engine's GN build system expects tvOS SDKs inside `engine/src/flutter/prebuilts/`. These point to your local Xcode installation and are **not** created automatically by gclient.

Check your installed tvOS SDK version first:
```bash
ls /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/
# Example output: AppleTVOS26.0.sdk
```

Replace `26.0` below with your actual version if it differs.

```bash
PREBUILTS="$PWD/engine/src/flutter/prebuilts"
XCODE="/Applications/Xcode.app/Contents/Developer"
SDK_VER="26.0"   # <-- change if needed

mkdir -p "$PREBUILTS/SDKs" "$PREBUILTS/Platforms"

# SDKs
ln -sf "$XCODE/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS${SDK_VER}.sdk"                 "$PREBUILTS/SDKs/AppleTVOS${SDK_VER}.sdk"
ln -sf "$XCODE/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator${SDK_VER}.sdk"   "$PREBUILTS/SDKs/AppleTVSimulator${SDK_VER}.sdk"
ln -sf "$XCODE/Platforms/MacOSX.platform/Developer/SDKs/MacOSX${SDK_VER}.sdk"                       "$PREBUILTS/SDKs/MacOSX${SDK_VER}.sdk"
ln -sf "$XCODE/Toolchains/XcodeDefault.xctoolchain"                                                 "$PREBUILTS/SDKs/XcodeDefault.xctoolchain"

# Platforms
ln -sf "$XCODE/Platforms/AppleTVOS.platform"            "$PREBUILTS/Platforms/AppleTVOS.platform"
ln -sf "$XCODE/Platforms/AppleTVSimulator.platform"     "$PREBUILTS/Platforms/AppleTVSimulator.platform"
ln -sf "$XCODE/Platforms/MacOSX.platform"               "$PREBUILTS/Platforms/MacOSX.platform"
```

---

## Step 6 — Build the engine

```bash
./build_tvos_engine.sh all
```

This builds all 6 variants (takes 30–60 min on M-series Mac):

| Variant | Purpose |
|---|---|
| `tvos_debug_sim_arm64` | Simulator, debug/JIT (hot reload) |
| `tvos_debug_arm64` | Device, debug |
| `tvos_profile_arm64` | Device, performance profiling |
| `tvos_release_arm64` | Device, App Store release |
| `host_debug_unopt` | Host tools (debug) |
| `host_release` | Host tools (release) |

The script **automatically**:
- Applies third-party patches (Skia, Perfetto, Dart VM, Dart runtime/bin) — all in `deps_patches/`
- Copies `libclang_rt.tvos.a` and `libclang_rt.tvossim.a` from your Xcode toolchain into the Flutter buildtools (these provide `__isPlatformVersionAtLeast`, missing from standard Flutter buildtools)

### Build a single variant (faster iteration)

```bash
./build_tvos_engine.sh debug_sim    # simulator debug only
./build_tvos_engine.sh release      # release for device only
./build_tvos_engine.sh host_debug   # host tools only
```

---

## Step 7 — Package artifacts

```bash
./package_artifacts.sh
```

Creates distributable zips in `artifacts/`:

```
artifacts/
├── tvos_debug_sim_arm64.zip   (~100 MB)
├── tvos_debug_arm64.zip       (~100 MB)
├── tvos_profile_arm64.zip     (~23 MB)
├── tvos_release_arm64.zip     (~22 MB)
├── host_debug_unopt.zip       (~22 MB)
└── host_release.zip           (~17 MB)
```

These are the engine artifacts consumed by the `flutter-tvos` CLI.

---

## Troubleshooting

### `vpython3: command not found`
`depot_tools` isn't in PATH. Fix:
```bash
export PATH="$HOME/depot_tools:$PATH"
```
(Add to `~/.zshrc` to persist.)

---

### `FileNotFoundError: ...prebuilts/SDKs`
You skipped Step 5. Create the symlinks and retry.

---

### `ninja: error: '.../dart/.dart_tool/package_config.json' ... missing`
gclient hooks didn't run. Fix:
```bash
gclient runhooks
```

---

### `error: 'execvp' is unavailable: not available on tvOS` (or similar Dart VM errors)
The `deps_patches/` didn't apply. Force re-apply:
```bash
rm -f .deps_patched
./build_tvos_engine.sh all
```

---

### `undefined symbol: __isPlatformVersionAtLeast`
The tvOS clang_rt libs weren't copied into buildtools. This should happen automatically in Step 6 — check that `xcode-select -p` returns a valid path:
```bash
xcode-select -p
# Should print: /Applications/Xcode.app/Contents/Developer
```

If wrong, fix with:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Then delete `.deps_patched` and rebuild.

---

### Host build crashes on desktop shader compilation
Known issue with clang crashing on unrelated desktop shaders. Build only the targets the tvOS build actually needs:
```bash
cd engine/src
ninja -C out/host_debug_unopt \
  gen_snapshot \
  flutter/flutter_frontend_server:frontend_server \
  flutter/lib/snapshot:strong_platform
```
Then re-run `./build_tvos_engine.sh all` (it'll skip host_debug if those targets already built).

---

## What to do with the artifacts

Hand the zips in `artifacts/` to whoever is using the `flutter-tvos` CLI. They extract into the CLI's `engine_artifacts/` directory — one folder per variant, named after the zip (without `.zip`).

Example:
```
flutter-tvos/engine_artifacts/
├── tvos_debug_sim_arm64/
│   ├── Flutter.framework/
│   ├── Flutter.xcframework/
│   ├── clang_arm64/
│   ├── flutter_patched_sdk/
│   └── ...
├── tvos_debug_arm64/
├── tvos_profile_arm64/
├── tvos_release_arm64/
├── host_debug_unopt/
└── host_release/
```

---

## Summary of required steps

1. Install depot_tools + add to PATH
2. `git clone` the repo
3. Create `.gclient` (Step 3)
4. `gclient sync --no-history --shallow`
5. Create SDK/Platform symlinks (Step 5)
6. `./build_tvos_engine.sh all`
7. `./package_artifacts.sh`

That's it. Zips end up in `artifacts/`.
