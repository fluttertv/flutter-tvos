# PR Review: #23 — Release 1.3.0 — Swift Package Manager support + flutter-tvos upgrade

**Repo:** fluttertv/flutter-tvos
**Branch:** dev → main
**Date:** 2026-06-12
**Reviewers:** 6 agents (3 layer-specific + architect + silent-failure hunter + type-design analyzer), then 4 adversarial verification agents re-checked every Critical/Important finding against the actual code at `upstream/dev` (4a84145). Copilot second-opinion skipped — monthly quota exceeded.
**Layers affected:** CLI (SPM generator, upgrade command, plugin resolution, build pipeline), Dart package native packaging (Package.swift / podspec / FFI header), app templates, tests, docs.

Line references are at PR head (`upstream/dev`). Every finding below carries a verification verdict; findings refuted during verification were removed or downgraded with the refuting evidence noted.

## Critical Issues

### C1. `_hasUncommittedChanges` fails open — `git reset --hard` can destroy uncommitted changes
**Verified: CONFIRMED on all sub-points.**
`lib/commands/upgrade.dart:233-239`:
```dart
final RunResult result = await _git.run(
  <String>['git', 'status', '-s'],
  workingDirectory: workingDirectory,
);
return result.stdout.trim().isNotEmpty;
```
No `throwOnError` (default is `false` per vendored `process.dart:188`), no exit-code check. If `git status` fails (corrupted index, permissions — stdout empty, error on stderr), the tree is reported *clean* and the flow proceeds to `attemptReset` → `git reset --hard` (`upgrade.dart:138-149, 241`), silently destroying the user's uncommitted changes. This check is the only guard on that path; `--force` short-circuits it entirely. A `ProcessException` (git unspawnable) is also uncaught here — the file's only try blocks are in `fetchLatestReleaseVersion`/`fetchCurrentVersion`/`attemptReset`. Stock Flutter fails closed: vendored `flutter_tools/lib/src/commands/upgrade.dart:309-326` uses `throwOnError: true` and catches `ProcessException` into `throwToolExit('The tool could not verify the status of the current flutter checkout...')`. The port dropped both. No test covers a failing `git status`.

## Important Issues

### I1. Build never verifies the pbxproj actually links the generated SPM umbrella — mixed project states fail with a cryptic compile error, no diagnostic
**Verified: PARTIAL — downgraded from Critical.** Confirmed: `_generateSwiftPackages` (`lib/build_targets/application.dart:586-638`) always generates the umbrella and nothing anywhere in `lib/` checks that `project.pbxproj` references `FlutterGeneratedPluginSwiftPackage` (tree-wide grep: only two comments). Confirmed: the new Podfile skips any plugin with `tvos/Package.swift` (`templates/.../Podfile:31-32`).

However, the originally claimed failure mode — silent build + runtime `MissingPluginException` — was **refuted** for the common case: the generated ObjC registrant emits `@import <plugin>;` (`lib/tvos_plugins.dart:465`), so a plugin linked by neither system fails the *build* of `GeneratedPluginRegistrant.m` with a missing-module error — loud, but cryptic and pointing nowhere near the cause. Only FFI plugins (no `pluginClass`, no `@import`) would fail at runtime, and the sole shipped FFI plugin (`flutter_tvos`) carries both manifests, so it can't be dropped this way. Also, the tool itself never produces the mixed old-pbxproj/new-Podfile state (`tvos_runner.dart:40` only writes the template when `tvos/` doesn't exist) — it requires a user manually copying the new Podfile; no migration doc steers them into it.

Still worth fixing: when `spmPlugins` is non-empty and the pbxproj lacks `FlutterGeneratedPluginSwiftPackage`, print an actionable error — the file is already read in `_resolveTvosDeploymentTarget` (`application.dart:643`). Real secondary gap (confirmed): the **inverse** state — pre-1.3 Podfile (requires a podspec) + an SPM-only plugin without podspec — drops the plugin on unmigrated projects; mitigated today only because the porter always generates both manifests. Semantics mismatch (Ruby `File.exist?` true for directories vs Dart `File.existsSync()` false) confirmed but requires `Package.swift` to be a directory — exotic.

### I2. SPM/CocoaPods double-link guard is convention-only
**Verified: CONFIRMED.** The exclusivity check exists only in the user-editable Ruby Podfiles (`has_spm` skip). In `lib/`, nothing parses `Podfile.lock` (only `clean.dart` deletes it) or cross-checks pods vs SPM; `ensureReadyForTvosTooling` writes *every* native plugin into `.flutter-plugins-dependencies` with no SPM exclusion (`tvos_plugins.dart:420-426`) and `discoverTvosSpmPlugins` independently selects the SPM set. `flutter_tvos` 1.1.0 itself ships both a podspec and a `Package.swift` (confirmed via `git ls-tree`), so an old Podfile (no `has_spm` check) + new pbxproj links it twice — static via the umbrella and dynamic via the pod: duplicate ObjC classes, dlsym binding one of two symbol copies. A build-time assertion (pods in Podfile.lock that also ship `Package.swift`) would make it airtight. Related (confirmed): the classification predicate lives in three uncoordinated places (Dart + 2 Podfiles) and `TvosPlugin` carries no packaging-mode field.

### I3. Umbrella assumes product name == hyphenated package name
**Verified: CONFIRMED.** `lib/tvos_swift_package_manager.dart:219` `String get productName => name.replaceAll('_', '-');` used at `:169`. Tree-wide grep confirms nothing ever parses a plugin's actual `.library(name:)` — the only manifest parsing is the `name:` regex. A third-party plugin with a non-conventional product name fails umbrella resolution with an opaque SwiftPM error. The convention is enforced only for porter-generated plugins (`templates.dart:183`).

### I4. `_readSwiftPackageName` — fragile parse, silently swallowed read errors, unvalidated output used in symlinks and manifests
**Verified: CONFIRMED on all three parts.** `lib/tvos_plugins.dart:259-264`: (a) `RegExp(r'name:\s*"([^"]+)"').firstMatch` over the whole file — any `name: "X"` in a comment before `Package(` wins; (b) `on FileSystemException { return null; }` — no logging, silent fallback to `plugin.name` at `:244`, *after* the existence check already told CocoaPods to skip the plugin; (c) the unvalidated name becomes a symlink filename (`tvos_swift_package_manager.dart:102`) and is interpolated into the umbrella manifest (`:164, :169`) — `"`, `/`, `..` would corrupt either. Test coverage confirmed absent: the three `discoverTvosSpmPlugins` tests all use a well-formed manifest. Fix: anchor regex to `Package(\s*name:`, log the fallback, validate `^[A-Za-z0-9_]+$` in `TvosSpmPlugin`'s constructor.

### I5. Ported-plugin `Package.swift` declares `.package(path: "../FlutterFramework")` — contradicts its own doc comment and breaks standalone builds
**Verified: CONFIRMED.** `lib/plugin_porting/templates.dart:205` emits the dependency; the doc comment on the same function (`:162-167`) says "**No Flutter dependency declared.** … Declaring a Flutter package dependency here would break" — a direct contradiction 38 lines apart. The design note in `tvos_swift_package_manager.dart:20-25` ("federated plugins declare no Flutter dependency of their own, verified against network_info_plus") also contradicts the emitted manifest. The relative path resolves inside the umbrella layout by design (`.packages/<name>/../FlutterFramework`, `application.dart:616-624`) but depends on SwiftPM resolving against the symlink path rather than the pub-cache realpath — intentional yet unproven in-repo (no test runs `swift build`/`dump-package`). Standalone `swift build` / plugin-repo CI / pub.dev analysis of a ported plugin fails unconditionally (SwiftPM has no conditional package dependencies). Pick one convention, fix the doc comments, add a resolution test.

### I6. FFI symbols under SPM static linking: `__attribute__((used))` does not defeat archive-member elision; no linker anchor exists
**Verified: CONFIRMED (medium-high confidence on the risk itself).** `flutter_tvos_ffi.h:18-19` defines `used` + `visibility("default")`; the header's own comment concedes nothing in native code references the symbols (dlsym-only via `DynamicLibrary.process()`; consumers are `tvos_ffi_bindings_native.dart:32,44`). The ObjC registrant never references flutter_tvos (FFI plugin, no `pluginClass`). Tree-wide greps confirm no `-ObjC`/`-force_load`/`-u`/`unsafeFlags` anywhere; the only `linkerSettings` is `.linkedFramework("UIKit")`. `used` prevents dead-stripping within a *loaded* object but does not cause an unreferenced static-archive member to be selected; whether Xcode links SwiftPM package targets as archives or direct objects varies by version, so current device verification may pass incidentally. Recommend an explicit anchor (`-u _flutter_tvos_is_tvos` via the umbrella or a registrant-side reference) plus an `nm`/dlsym smoke check in CI; archive/TestFlight (strip) builds are untested.

## Minor Issues

### Downgraded after verification

- **Template `objectVersion = 56` with Xcode-15 SPM constructs (example uses 60).** Mismatch confirmed (`project.pbxproj.tmpl:6` vs example `:6`; XCLocalSwiftPackageReference at template `:499-501`) and `pod install` does parse the project (integrating Podfile + unconditional `pod install` at `application.dart:267-271`). **Downgraded from Critical/Important:** Xcode and the `xcodeproj` gem (≥1.23.0) parse by ISA, not objectVersion — stock Flutter itself inserts `XCLocalSwiftPackageReference` into objectVersion-54 iOS projects; the CHANGELOG documents the 56 choice as deliberate; the PR's e2e verification (5 plugins, simulator + device) implies the gem tolerated it. Still: align template to 60 for consistency with the example, or document why not. Note CI runs no `create`/`pod`/`xcodebuild`, so this stays self-reported.
- **Half-upgraded state after a failed second half.** The headline claim ("stale engine forever, masked by 'already up to date'") was **refuted**: `TvosRequiredArtifacts` adds the tvOS engine artifact to `requiredArtifacts` of build/run/drive (`tvos_cache.dart:41-47`), `FlutterCommand.verifyThenRunCommand` calls `cache.updateAll` (vendored `flutter_command.dart:1936-1948`), and `TvosEngineArtifacts.version` reads `bin/internal/engine.version` live with stamp checking — the next build self-heals stale artifacts. What remains (confirmed): `throwToolExit(null, exitCode: code)` at `upgrade.dart:267-268` and `:301-302` — null message, no statement of what state the checkout is in. Give both real messages.
- **Example app's removed `[CP] Embed Pods Frameworks` phase.** Removal confirmed, but **refuted as a bug**: with zero resolved pods, CocoaPods' own integrator removes that phase — the committed state is exactly what `pod install` produces, and it re-adds the phase automatically when a podspec-only plugin appears. No action needed (optionally a comment).
- **`.define("TARGET_OS_TV")` in Package.swift cSettings.** Asymmetry vs podspec confirmed (`Package.swift:22-24` vs podspec with no defines), but the masking concern is mostly neutralized: `flutter_tvos_ffi.m:7` includes `TargetConditionals.h`, whose `#define` supersedes the command-line `-D` within the TU. Still redundant and a parity divergence — delete it.

### Confirmed minors

- **Stale non-symlink entity at link path → unhandled `FileSystemException`.** `tvos_swift_package_manager.dart:65-69, 102-106` — `Link.existsSync()` is false when a real file/dir occupies the path; `createSync` throws a raw "File exists". Use `fs.typeSync(...) != notFound` → delete recursively. The re-runnable test covers only the existing-symlink case.
- **Regeneration not content-stable.** Manifests rewritten and symlinks recreated unconditionally every build — mtime churn re-triggers Xcode package resolution per build. Compare-before-write; prune stale `.packages/<name>` symlinks of removed plugins.
- **`--verify-only` runs `git fetch --tags` before returning** (confirmed: fetch at `upgrade.dart:160-163` precedes the `verifyOnly` return at `:132-135`) — mutates local tag refs; working tree untouched. Doc note.
- **"Newest release" ordering delegated to git versionsort** (confirmed: `git tag -l --sort=-v:refname` + `^v\d+\.\d+\.\d+-tvos\.\d+\.\d+\.\d+$`, first match wins). Flutter-version-primary; user `versionsort.suffix` config can reorder. A parsed comparable tag type would be deterministic.
- **Checkout ahead of the latest tag is silently reset backwards**; only uncommitted changes are guarded.
- **`_resolveTvosDeploymentTarget`** (`application.dart:643-654`): `firstMatch` across all build configs; silent `13.0` fallback with no log.
- **Missing-xcframework path double-reports and throws generic `Exception`** (`application.dart:602-606`) — convert to `throwToolExit`.
- **`setShouldRedisplayWelcomeMessage(true)` not in try/finally** (`upgrade.dart:272-283`); `runDoctor` ignores the doctor exit code (mirrors stock; deserves a comment).
- **Runner type design** (`upgrade.dart`): mutable nullable `workingDirectory` set post-construction (null → git runs in process CWD; testability trap); flag interplay by `if` ordering (`--continue` wins over `--verify-only`); `--working-directory` presence silently flips `testFlow`.
- **`TvosSpmPlugin`**: `@immutable` without `==`/`hashCode`; no constructor validation; `renderPluginsUmbrellaManifest` is `@visibleForTesting` but takes library-private `_PluginRef`.
- **Deployment floor duplicated**: `kDefaultDeploymentTarget = '13.0'` vs hardcoded `.tvOS(.v13)` in `renderPackageSwift`.
- **`PluginSource.packageName` never validated against pub's grammar** — a bad source pubspec name produces an invalid Swift module downstream.
- **Xcode-before-first-build** (confirmed: nothing in `create.dart`/`tvos_app_scaffold.dart`/`tvos_runner.dart` generates the umbrella; only build step 6b does): freshly created apps reference a nonexistent local package until first build; same for fresh clones since `Flutter/ephemeral/` is gitignored (confirmed in both .gitignores). Stock Flutter shares this characteristic; consider generating at `create` time anyway. Cosmetic: XCLocalSwiftPackageReference comment label differs between template and example.
- **Dead `PBXFileReference` for `Flutter/Flutter.framework` in the example** (confirmed: declaration + group child only, no build-file usage).
- **Podspec links `UIKit, Foundation`; Package.swift links only UIKit** (confirmed; Foundation auto-links — cosmetic parity).
- **Binary target is single-slice, destination-pinned** (confirmed on disk: each `engine_artifacts/tvos_*/Flutter.xcframework` carries exactly one slice; symlink swapped per build by env type). Building from Xcode for the other destination fails until the tool regenerates — document.
- **pubspec.lock resolves only on Dart ≥3.10** while pubspec.yaml claims `>=3.3.0` — expected transitive bumps; lock not published.
- **Test gaps on error paths**: failing `git status` (C1), `git fetch` network failure, `attemptReset` failure, missing-xcframework throw, malformed/unreadable `Package.swift`, `runCommandSecondHalf`. Dead test branch in `tvos_plugins_test.dart` `seedProject` (~829-836).

## Passed Checks

- **Engine-only separation**: no `#if` / compile-time platform checks in any Dart change.
- **Process calls**: list-form argv everywhere; `pod install` checks exit + throws with stderr; all upgrade git calls use `throwOnError` except C1 and the intentional, exit-code-checked `git describe`.
- **Atomic version pinning**: `flutter.version`/`engine.version` move together via the single `git reset`; `shared.sh` self-heals SDK + snapshot + pub get; engine artifacts self-heal via the `TvosRequiredArtifacts` → `cache.updateAll` stamp check on the next build (verified during adversarial pass).
- **Plugin discovery**: `_discoverTvosPlugins` untouched; strict `platforms.tvos is YamlMap` match; `.flutter-plugins-dependencies` preservation (cd4c701) not regressed.
- **Backward compat (consistent old projects)**: build never edits pbxproj; `_copyFlutterFramework` retained; old Podfile links all podspec plugins; umbrella generated-but-unreferenced is harmless.
- **Public Dart API**: zero changes under `packages/flutter_tvos/lib/`; 1.1.0 bump justified as additive; podspec version synced.
- **Package.swift correctness**: swift-tools-version 5.9 consistent; `.tvOS(.v13)` == podspec `13.0` == example deployment target; generator's own package/product names resolve.
- **FFI mechanics as written**: `used` + default visibility is upstream FFI guidance; `DynamicLibrary.process()` finds statically linked symbols (residual risk is I6).
- **Embedding**: Flutter.xcframework linked+embedded exactly once; nothing assumes pre-signed binaries.
- **No machine-specific data**: committed `DEVELOPMENT_TEAM` removed; SPM references relative; `Flutter/ephemeral/` gitignored.
- **All flutter_tools imports via `src/` paths.**
- **RCU/channel contract**: untouched by this PR.

## Summary

- Critical: 1 (was 2 — the dual-drop finding downgraded after verification: failure mode is a loud-but-cryptic build error, not silent runtime loss, and the tool never produces the broken state itself)
- Important: 6 (was 9 — objectVersion, half-upgrade staleness, and embed-pods findings downgraded/refuted with evidence)
- Minor: ~20
- **Recommendation: REQUEST CHANGES**

C1 is a genuine data-loss bug with a five-line fix (mirror stock Flutter's fail-closed `hasUncommittedChanges`). Of the Importants, I4 (parse/validation of third-party manifests) and I5 (doc-vs-code contradiction in the ported-plugin Flutter dependency) are the ones most likely to bite real users of the headline 1.3.0 features; I6 deserves at least a CI smoke check before `flutter_tvos 1.1.0` goes to pub.dev.
