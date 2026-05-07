# Flutter-tvOS vs Flutter-Tizen Feature Comparison

Last updated: 2026-04-08

---

## At a Glance

|  | flutter-tvos | flutter-tizen |
|--|:---:|:---:|
| **Target platform** | Apple TV (tvOS) | Samsung TV / Tizen devices |
| **Flutter version** | 3.41.4 | Latest stable |
| **How it works** | Patches the Flutter iOS engine with `#if TARGET_OS_TV` guards | Owns a standalone C++/C# embedder |
| **Native build tool** | xcodebuild | dotnet-cli / ninja |
| **Plugin system** | CocoaPods (reuses iOS podspecs) | C++ shared libs / .NET assemblies |
| **Rendering** | Metal (Impeller) | OpenGL ES / Vulkan |

---

## Full Feature Comparison

> **Legend**: ✅ = fully working, ⚠️ = partial / basic, ❌ = not implemented

### Day-to-Day Development

These are the features you use every time you sit down to code.

| Feature | tvOS | Tizen | Details |
|---------|:----:|:-----:|---------|
| Create a new app | ✅ | ✅ | `flutter-tvos create my_app` / `flutter-tizen create my_app` |
| Build | ✅ | ✅ | tvOS outputs `.app` via xcodebuild; Tizen outputs `.tpk` |
| Run on simulator/emulator | ✅ | ✅ | tvOS uses Apple TV Simulator; Tizen uses Tizen Emulator |
| Hot reload | ✅ | ✅ | Press `r` in terminal |
| Hot restart | ✅ | ✅ | Press `R` in terminal |
| Dart DevTools | ✅ | ✅ | Press `d` in terminal |
| List devices | ✅ | ✅ | Shows simulators + physical devices |
| Precache engine artifacts | ✅ | ✅ | Downloads/extracts pre-built engine binaries |

### Physical Device Deployment

| Feature | tvOS | Tizen | Details |
|---------|:----:|:-----:|---------|
| Discover physical devices | ✅ | ✅ | tvOS: `xcrun devicectl`; Tizen: SDB (Samsung Debug Bridge) |
| Install app on device | ✅ | ✅ | tvOS: `devicectl device install app`; Tizen: `sdb install` |
| Launch app on device | ✅ | ✅ | tvOS: `devicectl device process launch`; Tizen: `sdb shell` |
| Stream device logs | ✅ | ✅ | tvOS: `devicectl --console`; Tizen: `sdb dlog` |
| Wireless device connection | ❌ | ✅ | Tizen supports network debugging; tvOS requires USB/wired |

### Release Builds

| Feature | tvOS | Tizen | Details |
|---------|:----:|:-----:|---------|
| AOT compilation (release) | ✅ | ✅ | tvOS: gen_snapshot → assembly → App.framework; Tizen: gen_snapshot → .so |
| Profile mode | ✅ | ✅ | |
| Code signing | ⚠️ | ✅ | tvOS: only `DEVELOPMENT_TEAM` env var passthrough; Tizen: full security profile system |
| Multiple architectures | ❌ | ✅ | tvOS: arm64 only; Tizen: arm, arm64, x86, x64 |

### Plugins

| Feature | tvOS | Tizen | Details |
|---------|:----:|:-----:|---------|
| Native plugin compilation | ✅ | ✅ | tvOS: CocoaPods; Tizen: C++/.NET build |
| Plugin discovery from pubspec | ✅ | ✅ | tvOS falls back to `ios` platform if no `tvos` entry |
| Auto-generated plugin registrant | ✅ | ✅ | tvOS: Swift; Tizen: C#/C++ |
| Create plugin template | ✅ | ✅ | tvOS: Swift + podspec; Tizen: C++/C# |
| Dart-only plugins | ✅ | ✅ | |
| FFI plugins | ❌ | ✅ | |
| Documented plugin catalog | ❌ | ✅ | Tizen has 20+ known compatible plugins listed |
| Multiple native languages | ❌ | ✅ | tvOS: Swift only; Tizen: C++ and C# |

### Doctor / Toolchain Validation

| Check | tvOS | Tizen | Details |
|-------|:----:|:-----:|---------|
| IDE/SDK installed | ✅ | ✅ | tvOS checks Xcode; Tizen checks Tizen SDK + .NET SDK |
| IDE/SDK version | ✅ | ✅ | |
| Platform SDK packages | ❌ | ✅ | Tizen validates rootstraps, NativeToolchain, NativeCLI |
| Build tool check (CocoaPods etc.) | ❌ | ✅ | |
| Simulator/emulator runtime | ❌ | N/A | tvOS doesn't verify tvOS simulator runtime is installed |

### Testing & CI

| Feature | tvOS | Tizen | Details |
|---------|:----:|:-----:|---------|
| Unit tests (`test`) | ⚠️ | ✅ | tvOS delegates to Flutter base class |
| Integration tests (`drive`) | ⚠️ | ✅ | tvOS delegates to Flutter base class, no tvOS-specific logic |
| Attach to running app | ⚠️ | ✅ | tvOS delegates to Flutter base class |

### Advanced / Ecosystem

| Feature | tvOS | Tizen | Details |
|---------|:----:|:-----:|---------|
| Module template (embed in existing native app) | ❌ | ✅ | |
| Multiple app types (UI, service, multi) | ❌ | ✅ | Tizen supports background services |
| Device profiles (TV, mobile, common) | ❌ | ✅ | tvOS only targets Apple TV |
| Platform views (native views in Flutter) | ❌ | ✅ | Needed for maps, video players, web views |
| Runtime platform package (Dart APIs) | ❌ | ✅ | Tizen has `packages/flutter_tizen` |
| Embedder version tracking | ❌ | ✅ | Tizen has `embedder.version` file |
| Split debug info | ❌ | ✅ | Smaller release binaries |
| Install pre-built binary | ❌ | ✅ | Tizen: `--use-application-binary foo.tpk` |
| Create/manage emulators from CLI | ❌ | ✅ | Tizen: `flutter-tizen emulators --create` |
| Clean command (platform-specific) | ❌ | ✅ | tvOS clean is a stub, no tvOS-specific cleanup |

---

## Score Summary

| Category | tvOS | Tizen |
|----------|:----:|:-----:|
| Day-to-day development | **8 / 8** | **8 / 8** |
| Physical device deployment | **4 / 5** | **5 / 5** |
| Release builds | **2 / 4** | **4 / 4** |
| Plugins | **5 / 8** | **8 / 8** |
| Doctor / validation | **2 / 5** | **5 / 5** |
| Testing & CI | **0 / 3** | **3 / 3** |
| Advanced / ecosystem | **0 / 10** | **10 / 10** |
| **Total** | **21 / 43** | **43 / 43** |

---

## What This Means

**flutter-tvos covers everything you need for daily development.** You can create apps, build them, run on simulators and physical Apple TVs, use hot reload, and include native plugins. The core loop works.

**The gaps are in polish and ecosystem maturity**, not in fundamentals:

### Must-fix for production use

| Gap | Effort | Why |
|-----|--------|-----|
| Better `doctor` — check tvOS SDK, CocoaPods, simulator runtimes | Small | Users get zero guidance when setup is wrong |
| Code signing — provisioning profiles, certificate selection | Medium | Required for TestFlight / App Store |
| `clean` command — delete tvOS build artifacts | Small | Basic hygiene |
| Integration tests — tvOS-specific `drive` command | Medium | Required for CI/CD pipelines |

### Nice to have

| Gap | Effort | Why |
|-----|--------|-----|
| Plugin compatibility catalog | Small | Document which iOS plugins work on tvOS |
| Module template | Medium | Embed Flutter in existing tvOS apps |
| Platform views | Large | Maps, video, web views inside Flutter |
| Wireless device support | Medium | More convenient Apple TV development |
| Embedder version tracking | Small | Better artifact management |

---

## Why the Architecture Differs (and That's OK)

flutter-tizen **owns its embedder** — it has C++/C# source code that bootstraps the Flutter engine on Tizen. This is necessary because Tizen is not a platform Flutter already supports.

flutter-tvos **patches the existing iOS engine** — tvOS is a Darwin platform, so it reuses the iOS engine pipeline with `#if TARGET_OS_TV` compile-time guards. The engine patches live in `flutter_upstream_3414/`, not in a separate embedder directory.

This is the same approach macOS Catalyst uses to run iOS apps on Mac. It's not a deficiency — it's the pragmatic choice for a Darwin platform that shares 95% of its API surface with iOS.
