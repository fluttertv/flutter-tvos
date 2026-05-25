# Porting an existing plugin to tvOS

`flutter-tvos plugin port` scaffolds a federated `*_tvos` package from an existing Apple Flutter plugin. The source plugin is never modified — you get a new sibling package you can publish under your own name.

The 11 packages at [github.com/fluttertv/plugins](https://github.com/fluttertv/plugins) were all produced this way; the [repo README](https://github.com/fluttertv/plugins#how-this-repository-was-created) lists the exact commands used.

## Quick start

```sh
# Port an upstream package from pub.dev
flutter-tvos plugin port --from-pub shared_preferences_foundation \
  --output shared_preferences_tvos --include-example

# Or from a git repo
flutter-tvos plugin port --from-git https://github.com/foo/bar.git \
  --ref main --output bar_tvos

# Or from a local checkout
flutter-tvos plugin port ../some_plugin_ios --output ../some_plugin_tvos
```

Exactly one source is required: a positional path, `--from-pub`, or `--from-git`.

## What you get

```
<output>/
├── pubspec.yaml              # federated tvOS plugin, depends on <base>_platform_interface
├── lib/                      # source plugin's Dart, cross-platform files pruned, self-imports rewritten
├── tvos/
│   ├── Classes/              # transformed Swift / Objective-C
│   └── <pkg>.podspec         # CocoaPods spec
├── test/<pkg>_test.dart      # smoke test
├── README.md
├── CHANGELOG.md
├── PORTING_REPORT.md         # what was ported, stubbed, disabled, and why
└── example/                  # with --include-example
```

**Always read `PORTING_REPORT.md` first.** It states the tvOS build outlook, every stubbed handler, every stripped import, and every region the porter had to disable behind `#if !os(tvOS)`.

## Flags

| Flag | Purpose |
|---|---|
| `--from-pub <name>` | Fetch the source from pub.dev |
| `--from-git <url>` | Fetch the source from a git repo |
| `--ref <ref>` | Git ref to check out (`--from-git` only) |
| `--output <dir>` | Where to write the generated package |
| `--base-platform <ios\|macos>` | Which existing implementation to model on (default `ios`, falls back to `macos`) |
| `--license-holder "<name>"` | Copyright holder baked into generated file headers |
| `--include-example` | Also port the source plugin's `example/` as a runnable tvOS example |
| `--dry-run` | Compute and report; write nothing |
| `--force` | Overwrite the output directory if it exists |
| `--no-report` | Skip `PORTING_REPORT.md` (the code transform still runs) |

## How it transforms code

- **Platform guards widened.** Swift `#if os(iOS)` / `#elseif os(macOS)` and Objective-C `#if TARGET_OS_IOS` become `os(iOS) || os(tvOS)` / `TARGET_OS_IOS || TARGET_OS_TV` so tvOS follows the iOS branch (they share UIKit, AVFoundation, and the Flutter embedder shape).
- **Availability widened.** `@available(iOS X, *)` / `API_AVAILABLE(ios(X))` get a matching `tvOS X`. Apple ships those symbols on tvOS at the same OS version.
- **Multi-target SwiftPM collapsed.** Modern split-target plugins (a Swift API target plus an Objective-C `_objc`/`_ios` target, plus a macOS sibling) are folded into one CocoaPods module; the macOS-only target is dropped.
- **tvOS-incompatible imports stripped.** Frameworks Apple doesn't ship on tvOS (WebKit, SafariServices, LocalAuthentication, CoreLocation, …) have their `import` lines commented out.
- **tvOS-incompatible handlers stubbed.** Method-channel handlers that reference those APIs become `result(FlutterMethodNotImplemented)` — the rest of the plugin still works.
- **Type-level disable.** Where a tvOS-absent API appears at type / top-level scope (a property of an unavailable class, an enum case that doesn't exist), the enclosing declaration is wrapped in `#if !os(tvOS)` so the package still compiles. The disabled regions are listed in `PORTING_REPORT.md`.
- **Cross-platform Dart pruned.** `_plus`-style packages bundle Linux / Windows / Web Dart implementations alongside the iOS one. None of those are reachable at runtime on tvOS, and they pull in transitive deps (`package:web`, `flutter_web_plugins`, `win32`, …) that aren't in the generated pubspec. The porter drops them and rewrites the directives that referenced them.
- **Bundled assets fixed on device.** The generated example app sets `FLTAssetsPath` so `Asset` lookups resolve on real Apple TV hardware (not just the simulator).
- **Example monorepo wiring stripped.** `resolution: workspace` and sibling `dependency_overrides` are removed from any ported example so it `pub get`s standalone.

## What it can't do

### FFI / native-assets plugins → a skeleton

Plugins built on `dart:ffi` + `package:objective_c` with a `hook/build.dart` (e.g. `path_provider_foundation`) can't be mechanically ported — the toolchain doesn't build Dart native assets for tvOS. For these, the porter emits a **buildable Swift skeleton** (method-channel stubs + a federated Dart class) and the report says so explicitly. You hand-write the native side. Often easy — `path_provider_tvos` is `NSFileManager` over a channel.

### "Ported" ≠ "verified working"

A package that builds is not automatically correct. Stubbed handlers return *not implemented*; disabled regions are dead on tvOS. **Verify on a simulator and ideally a real Apple TV** before relying on a port. The generated `test/<pkg>_test.dart` is only a compile / export smoke test.

### Shallow transformer

The porter is regexes + brace tracking, not a Swift/Clang parser. Auditable by eye, but it can miss obfuscated API use or unusual dispatch patterns. Skim `tvos/Classes/` and the report before publishing.

## After porting

1. `cat <output>/PORTING_REPORT.md` — understand what changed.
2. Wire it into an app and build: `flutter-tvos build tvos --simulator --debug`.
3. Run the example / integration tests on the simulator, then on a device.
4. Only then treat the port as usable. Publishing under your own name is a naming / licensing / maintainership decision — it's a derivative of someone else's plugin.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No Account for Team … / missing Xcode-Token` (device build) | Stale/empty signing team. Export `DEVELOPMENT_TEAM=<valid id>` or set it in the example's Xcode project. |
| `Asset … not found` for `Controller.asset(...)` | Fixed by `FLTAssetsPath` in the generated app; regenerate with the current porter if you see this. |
| Example: `found no workspace root` / `path which doesn't exist` | Old example wiring; regenerate — the porter strips `resolution: workspace` and `dependency_overrides`. |
| FFI plugin "doesn't do anything" on tvOS | It's a skeleton by design — implement the native side. |
| Cascading compile errors after a `#if !os(tvOS)` disable | A disabled symbol is referenced elsewhere. The report lists every disabled region — wrap the use site too, or hand-implement a tvOS-safe alternative. |
