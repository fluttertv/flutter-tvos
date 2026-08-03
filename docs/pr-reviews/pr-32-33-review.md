# PR Review: #32 + #33 — pub-workspace plugin discovery & FLUTTER_ROOT for pod script phases

**Repo:** fluttertv/flutter-tvos
**Author:** thachnb-harman (external contributor)
**Date:** 2026-07-09
**Reviewers:** 3 agents (PR-32 CLI, PR-33 build-targets, silent-failure hunter) + independent maintainer verification against the vendored `flutter/` SDK, the real cargokit scripts, and a real pub workspace on disk.

Both PRs are **correct in diagnosis and mechanism** — verified empirically, not from the descriptions. Both are small, well-motivated, and fix real silent failures. Both should land after a few changes.

---

## PR #32 — plugin discovery in pub workspaces
`lib/tvos_plugins.dart` — `_walkPluginDependencies`

**The bug is real.** Pub workspaces hoist `.dart_tool/package_config.json` to the workspace root; the old code only looked at `<project>/.dart_tool/`, so for a workspace-member app the name→path map came back empty and **every** tvOS plugin was silently dropped (empty registrant → `MissingPluginException` at runtime). Confirmed against a real workspace (`flutter_gemma-fg`): members have no `.dart_tool/` of their own, and rootUris are `../packages/<name>` relative to the workspace's `.dart_tool/`.

**The resolution semantics of the fix are correct**, and there is **no regression for non-workspace projects** (when the project-local file exists the loop runs zero iterations and `packageConfigFile.parent` is byte-identical to the old `join(project, '.dart_tool')`).

### IMPORTANT — 1. Reimplements a helper that upstream ships and this repo already uses
The 10-line upward walk duplicates `findPackageConfigFile` / `findPackageConfigFileOrDefault`:
- `flutter/packages/flutter_tools/lib/src/dart/package_map.dart:25,48`
- exposed as `project.packageConfig` — `flutter/.../src/project.dart:227`
- upstream's own `findPlugins()` — the direct analogue of this function — uses it: `flutter/.../src/flutter_plugins.dart:109`
- **this repo already calls it**: `lib/tvos_builder.dart:79` → `findPackageConfigFileOrDefault(project.directory).path`

So the tvOS **kernel** path already handled workspaces correctly while plugin discovery did not — *that asymmetry is the bug*. Collapse the whole block to:
```dart
final File packageConfigFile = project.packageConfig;
```
This also inherits upstream's `absolute`+`normalize` hardening and its `path.equals()` termination (the hand-rolled loop uses raw `!=` and doesn't absolutize — with a relative `project.directory`, `dirname('.') == '.'` so the walk would silently not walk at all).

### IMPORTANT — 2. Zero test coverage on the branch being changed
`test/general/tvos_plugins_test.dart` is ~1100 lines, but **every existing test uses an absolute `file://` rootUri** (:573, :671, :735, :778, :842, :964, :1068). The `../`-relative branch this PR rewrites has **no test today**, and the PR adds none. Three tests should exist:
1. **Workspace member** (the regression test): `/ws/.dart_tool/package_config.json` with `rootUri: '../packages/foo_tvos'`, plugin pubspec declaring `flutter.plugin.platforms.tvos`, app at `/ws/apps/my_app` with **no** local `.dart_tool` → assert `foo_tvos` reaches `GeneratedPluginRegistrant`. Fails on main, passes with the PR.
2. **Non-workspace relative rootUri** — pins the "identical results" claim.
3. **No package_config anywhere** — pins loop termination + graceful empty result.

### MINOR — 3. `startsWith('./')` is dead code; prefer proper URI resolution
Pub never emits `./` rootUris (checked three real configs: 169/273/98 packages — all non-`file://` entries start with `../`). A bare-relative form (`foo/bar`) still falls through both branches and is stored raw. All forms collapse into one correct expression:
```dart
rootUri = packageConfigFile.parent.uri.resolve(rootUri).toFilePath();
```
which also percent-decodes (today a path with a space arrives as `../my%20plugin` and the `../` branch never decodes it).

### Not a defect — the unbounded upward walk
It can in principle reach an unrelated ancestor's `.dart_tool/`, but: upstream `findPackageConfigFile` has the **identical** unbounded walk (that *is* how pub resolves); a pubspec boundary would stop at the workspace *member* and re-introduce the bug; and the function early-returns unless `.flutter-plugins-dependencies` exists, which `pub get` writes alongside `package_config.json` and `clean` deletes together. Don't add a boundary.

---

## PR #33 — FLUTTER_ROOT + flutter_export_environment.sh
`lib/build_targets/application.dart` — `NativeTvosBundle`

**The mechanism is verified end-to-end** against the real cargokit scripts:
- `cargokit/build_pod.sh:40-52` sources `$PODS_ROOT/../Flutter/flutter_export_environment.sh`. The tvOS Podfile is at `<app>/tvos/Podfile`, so that resolves to `<app>/tvos/Flutter/` — **exactly where the PR writes it** (`application.dart:1223`). No cargokit change needed.
- `cargokit/run_build_tool.sh:17-21,75` falls back to bare `dart` when `$FLUTTER_ROOT` is unset — the reported `line 75: dart: command not found`.
- It uses `$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart` (not `bin/dart`), which exists in the vendored SDK and is *the same binary the CLI itself runs from* (`bin/internal/shared.sh:29`). So the vendored `Cache.flutterRoot` is not merely acceptable — it's the only correct value (a flutter-tvos user may have no stock Flutter at all).
- `.gitignore` already expects the file (`templates/.../.gitignore.copy.tmpl:26`), and it's regenerated every build (`NativeTvosBundle` can't be skipped — `tvos_builder.dart:106-108`).

**Correction to the PR description:** the `FLUTTER_ROOT=` line in `Generated.xcconfig` is *not* what fixes cargokit. `Generated.xcconfig` reaches only the **Runner** target (via `baseConfigurationReference` — `project.pbxproj.tmpl:385,415,445`); the Pods-project targets where cargokit's script phase runs don't inherit it. **The `.sh` is the load-bearing half.** Keep the xcconfig line (upstream parity, useful for user-added Runner phases), but it isn't the fix.

### IMPORTANT — 1. `COCOAPODS_PARALLEL_CODE_SIGN` is in the wrong file (currently a no-op)
Upstream builds ONE `xcodeBuildSettings` list and writes it to **both** files (`xcode_build_settings.dart:74` → xcconfig, `:114` → .sh), with `COCOAPODS_PARALLEL_CODE_SIGN=true` at `:185`. This PR writes it **only to the `.sh`** (diff line 43). It's consumed by CocoaPods' `[CP] Embed Pods Frameworks` phase as an *Xcode build setting* — that phase never sources the `.sh`, so as written the setting does nothing. The tvOS Podfile uses `use_frameworks!` (`templates/.../Podfile:16`), so the phase exists and would genuinely benefit. **Add it to the xcconfig buffer too.**

### IMPORTANT — 2. `flutter-tvos clean` doesn't remove the new file
`lib/commands/clean.dart:28` cleans `Flutter/Generated.xcconfig` but not the new sibling. A stale `flutter_export_environment.sh` with an absolute `FLUTTER_ROOT` survives `clean`; if the project or the CLI install is then moved and the user builds from Xcode directly, cargokit sources a dead SDK path. One line:
```dart
_cleanFile(tvosDir, 'Flutter/flutter_export_environment.sh');
```

### IMPORTANT — 3. No test, though the codebase has the pattern
`NativeTvosBundle` already exposes static, MemoryFileSystem-testable builders for exactly this purpose (`copyFlutterAssetsTree`, `buildAppFrameworkInfoPlist`, `tvosGenSnapshotArgs` — see `test/general/tvos_app_bundle_test.dart`, `tvos_aot_snapshot_test.dart`). Extract the two string builders as statics and assert: `FLUTTER_ROOT` present in the xcconfig; the `.sh` starts with `#!/bin/sh` and every line is `export "NAME=VALUE"`; every xcconfig var also appears in the `.sh` (this catches the asymmetry above); a path containing a space round-trips.

### MINOR
- **`path.join` with one argument is a no-op** — `normalize(join(Cache.flutterRoot!))` reduces to `normalize(Cache.flutterRoot!)`. Upstream: `xcode_build_settings.dart:168`. Drop the `join`.
- **No `chmod 755`** — upstream does it (`xcode_build_settings.dart:124`). Not required by cargokit (it *sources*, doesn't exec), but free parity and protects tooling that execs it. `globals` is already imported.
- **`FLUTTER_ROOT` exposes the raw vendored SDK**, so `$FLUTTER_ROOT/bin/flutter` is *stock* flutter, not flutter-tvos. Fine for cargokit (which uses `bin/cache/dart-sdk/bin/dart`), but a pod phase that shells out to `$FLUTTER_ROOT/bin/flutter` would silently run stock Flutter against a tvOS project. Worth a one-line comment stating the choice is deliberate. (Note `shared.sh:150-171` builds a `proxy_root/` for exactly this concern — currently referenced from nowhere in `lib/`.)

### Verified adequate (don't change)
- `Cache.flutterRoot!` force-unwrap: **unreachable-null**. `executable.dart:95` sets it unconditionally before `runner.run`; every other consumer force-unwraps too (`create.dart:98`, `tvos_runner.dart:30`, `tvos_builder.dart:51`), and so does upstream (`xcode_build_settings.dart:168`).
- Quoting: `export "NAME=VALUE"` is verbatim upstream (`:114`) and space-safe; xcconfig values are literal-to-EOL so unquoted is correct there.
- File writes propagate `FileSystemException` (no try/catch swallowing) — correct.
- Omitted vars (`DART_OBFUSCATION`, `TRACK_WIDGET_CREATION`, `PACKAGE_CONFIG`, …) exist upstream only to feed `xcode_backend.sh`'s in-Xcode `flutter assemble`. The tvOS pbxproj has no such phase — flutter-tvos assembles in the CLI. Omissions are correct.
- The second upstream file (`flutter_native_integration.env`) is **for SwiftPM Add-to-App** (`xcode_project.dart:133`), not CocoaPods. Not needed here.

---

## Cross-cutting — the highest-leverage fix (applies to #32, not introduced by it)

**`lib/tvos_plugins.dart:171-174` — the silent `continue` is why this whole bug class is invisible:**
```dart
final String? pluginPath = packagePaths[pluginName];
if (pluginPath == null) {
  continue;   // no warning, no error, not even a trace
}
```
At this point the tool *knows* the plugin is in the dependency graph (from `.flutter-plugins-dependencies`, which pub writes correctly regardless of platform keys) and *knows* it can't resolve it. That's a build-time-detectable, fully diagnosable inconsistency — discarded with zero output. The workspace bug was undebuggable **because of this line**, not because of the missing walk.

One warning here also covers every other silent path into an empty/partial map: malformed `package_config.json` (`:174` `on FormatException` — empty body), unexpected JSON shape (`:176` `on TypeError` — and note this one leaves a **partial** map, since `packagePaths[name] = rootUri` mutates incrementally, so the comment "fall through with empty packagePaths" is factually wrong), missing pubspec at the resolved path, and the wrong-ancestor hazard.

The file's own author already got this right ~400 lines down for `.flutter-plugins-dependencies` (`printWarning('...malformed JSON...; regenerating')` — `:583-592`). Same pattern, not applied here.

Suggested (out of scope for these PRs, but worth a follow-up):
```dart
if (pluginPath == null) {
  globals.logger.printWarning(
    'tvOS: plugin "$pluginName" is in the dependency graph but could not be '
    'resolved in ${packageConfigFile.path}. It will not be registered; calls '
    'into it will fail at runtime with MissingPluginException.',
  );
  continue;
}
```

---

## Summary

| PR | Verdict |
|---|---|
| **#32** | **Approve with changes** — correct fix; replace the hand-rolled walk with `project.packageConfig`, use `uri.resolve()` instead of the `./` special-case, add the workspace regression test. |
| **#33** | **Approve with changes** — correct fix, verified against real cargokit; move/duplicate `COCOAPODS_PARALLEL_CODE_SIGN` into the xcconfig, add the `clean.dart` line, add a test, drop the no-op `join`. |

Neither has a CRITICAL defect. Both authors clearly understood the failure mode and wrote excellent problem statements. The main theme in both: **the fix is right, but the repo already has the helper/pattern to do it more robustly** (`findPackageConfigFile` for #32; upstream's single-settings-list for #33).
