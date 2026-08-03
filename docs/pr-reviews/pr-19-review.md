# PR Review: #19 — Upgrade to Flutter 3.44.1 + native tvOS shaders + wireless on-device debug

**Repo:** fluttertv/flutter-tvos
**Branch:** feat/flutter-3.44.1-upgrade
**Date:** 2026-05-30
**Reviewers:** 6 agents (CLI layer, build/shaders, wireless-debug lifecycle, flutter-architect, silent-failure-hunter, type-design-analyzer). Copilot second-opinion skipped — blocked by auto-mode sandbox policy.
**Layers affected:** CLI tool (`lib/tvos_device.dart`, `lib/build_targets/application.dart`), example app + template (pbxproj, MetalLibInterposer removal), version bumps, docs, tests.
**Size:** +788 / −398, 27 files.

---

## Verdict on the wireless-debug flow vs upstream

The new flow ports stock iOS `IOSDevice._startAppOnCoreDevice`. Cross-checked against the pinned SDK (`flutter/packages/flutter_tools/lib/src/ios/{devices,xcode_debug,lldb,mdns_discovery}.dart`). Two places where the port **diverges from upstream in a way that introduces a regression**:

1. Upstream passes `xcode: globals.xcode` (**nullable**) — the port hard-unwraps `globals.xcode!` (diff line 804).
2. Upstream registers a shutdown hook / wraps the Xcode launch so the debug session is always torn down — the port has neither, so a `throwToolExit` from mDNS resolution after a successful Xcode launch orphans the session.

One place where the port is **better than upstream**: stall detection uses a 75 s `.timeout()` instead of scraping the lldb "taking longer than expected" log string — robust to Xcode-version changes. (The CHANGELOG/PR wording about the log string is therefore cosmetically inaccurate.)

The AppleScript-injection concern is **not applicable**: `XcodeDebug` passes workspace/scheme/device-id as separate argv to `osascript`, no shell, no string interpolation. mDNS client is closed in a `finally`. These are inherited-safe.

---

## Critical / Important Issues

### 1. `globals.xcode!` force-unwrap in the Xcode fallback — `lib/tvos_device.dart:804`
The fallback fires precisely when lldb already failed. On a machine where Xcode isn't selected (`xcode-select` points at CLT only, fresh CI), `globals.xcode` is null and `!` throws a bare `Null check operator used on a null value` — *after* `_teardownDeviceLaunch()` has already killed the working devicectl+lldb launch, so there's no recovery. **Upstream passes the nullable `globals.xcode`, so this is a regression, not parity.**
**Fix:** guard `globals.xcode == null` → `printError` actionable message ("Xcode required for the wireless debug fallback; open Xcode once / run `xcode-select`") and `return false`.

### 2. `_xcodeDebug` not cleaned up in `dispose()` — `lib/tvos_device.dart` (`dispose()`, not in diff)
The PR adds `_xcodeDebug` teardown to `stopApp()` (diff 921-922) but **not** to `dispose()`, which only disposes the log reader. `dispose()` runs on abnormal teardown / `attach` exit / hot-restart. If the Xcode fallback was active, the `osascript` automation process and the Apple TV debug session leak. The base code already cleans `_lldb`/`_lldbLogForwarder` in `stopApp`; the symmetry for `dispose` is missing.
**Fix:** add `unawaited(_xcodeDebug?.exit()); _xcodeDebug = null;` to `dispose()`.

### 3. No try/finally around Xcode-launch + mDNS resolve — orphaned session on throw — `lib/tvos_device.dart:749`
After `_launchViaXcodeDebugger` succeeds, `getVMServiceUriForAttach` (line 749) can `throwToolExit` — multiple VM services on the LAN (`mdns_discovery.dart:122`) or denied macOS Local Network permission (`:273`, because `throwOnMissingLocalNetworkPermissionsError` defaults to `true`). With `_xcodeDebug` set and no try/finally and no shutdown hook (upstream has one at `devices.dart:1184`), the throw exits `_startAppOnDevice` leaving an attached Xcode debug session on the device.
**Fix:** wrap the post-fallback block in try/finally that runs `_xcodeDebug.exit()`, **or** pass `throwOnMissingLocalNetworkPermissionsError: false` and handle null (see #4).

### 4. mDNS-not-found returns `succeeded()` with no URI → hot reload silently dead — `lib/tvos_device.dart:755-759` (and pre-existing tail at 742)
When `getVMServiceUriForAttach` returns null (VM service never advertised within 60 s), the code returns `LaunchResult.succeeded()` with no `vmServiceUri`. Traced through `resident_runner.dart:478`: `started==true && hasVmService==false` → `vmServiceUris = Stream.empty()` → runner reports success and waits forever. The app launches, the CLI says success, but **hot reload / hot restart / DevTools are silently non-functional with zero diagnostic output**. This is the most user-hostile outcome of the new flow.
**Fix:** before the bare `succeeded()`, `printWarning`: "App launched via Xcode but the Dart VM Service was not found over mDNS within 60 s — hot reload and DevTools will be unavailable. Check the Mac's Local Network permission and that the Apple TV is on the same LAN." (The pre-existing line-742 path copies the same anti-pattern; worth fixing both.)

### 5. `ensureXcodeDebuggerLaunchAction` can `throwToolExit` out of the fallback — `lib/tvos_device.dart:815`
Upstream `xcode_debug.dart` `throwToolExit`s when the Runner scheme's LaunchAction doesn't select the LLDB debugger. The PR calls it unguarded, so a scheme that isn't debugger-configured aborts the whole `run` instead of returning `false` with the intended "Failed to start a debug session" message. (Read-only validation — no scheme-restore cleanup needed, so the only fix is the guard.)
**Fix:** try/catch → `return false`.

### 6. `_resolveDeviceUdid` swallows devicectl stderr, then silently feeds the wrong identifier to Xcode — `lib/tvos_device.dart:882-885`
The `exitCode != 0 || !out.existsSync()` branch returns null with **no log of stderr**; the caller does `?? id`, handing the CoreDevice **GUID** (which Xcode doesn't recognize) to `debugApp`. The user gets a confusing "device not found in Xcode" much later with no breadcrumb that UDID resolution failed.
**Fix:** `printTrace` the devicectl exit code + stderr in that branch, and `printTrace` when falling back to the raw `id`.

### 7. Docs contradict the new feature — `README.md:146`, `doc/architecture.md:95`
`README.md` still says **"Debug mode is simulator-only … Debug (JIT) is blocked on the device by Apple"** — directly contradicted by this PR. `doc/architecture.md` Build Flow still lists the removed "Copy Metal libraries" step and the Run Flow doesn't mention the Xcode fallback.
**Fix:** update both before release (CHANGELOG already updated; the README limitation section and architecture doc were missed).

---

## Minor Issues

- **M1 — `expectedConfigurationBuildDir` omitted** (`_launchViaXcodeDebugger`). Upstream passes `bundle.parent.absolute.path` so Xcode reuses the CLI-built bundle. Omitting it risks Xcode silently rebuilding from source with different debug flags ("why isn't hot reload reflecting my change"). Pass the bundle parent dir.
- **M2 — Fallback is interface-agnostic.** `TvosDevice` has no `isWirelesslyConnected` flag; the fallback triggers on any `attached==false`, including a wired device where lldb genuinely failed. Benign (Xcode debugging works wired too), but broader than "wireless stall only." Consider gating on connection interface or document the intent.
- **M3 — lldb log-forwarder subscription leak.** `lldbForwarder.logLines.listen(...)` (diff 687) is never captured/cancelled; `_teardownDeviceLaunch` exits the forwarder but drops the subscription handle.
- **M4 — `_resolveDeviceUdid` finally deletes temp dir unguarded** (diff 889-891). Siblings (`_resolveDeviceIp`, `_findAppPid`) wrap `deleteSync` in `try/on FileSystemException`; this one doesn't, so a shutdown-race deletion failure masks the real result.
- **M5 — `parseDeviceUdid` conflates "no UDID" with "malformed JSON".** Both → null; tests cement this. Tolerable (one fallback-tolerant caller), but a future devicectl JSON-shape change is invisible. Add a trace log on the malformed branch at the caller. (Type-design agent: keep `String?`, a result type is over-engineering here.)
- **M6 — `_embedAppFrameworkFallback` hardcodes `'Apple Development'` identity** when the `Authority=` regex misses (`application.dart:390`). A *successful* sign with the wrong identity isn't surfaced — only fails later at install with `0xe8008014`. `printTrace` when the default is used.
- **M7 — `DEVELOPMENT_TEAM = 866PPL96Z4`** committed to the example pbxproj (was `2U7DD3DNRL`). Real personal Team ID; contributors hit codesign failures. Pre-existing pattern (template parametrizes via mustache var). Not a secret — Apple Team IDs are public — but consider `""` for the example. *(Confirmed earlier this session that publishing a Team ID is acceptable.)*
- **M8 — `tvos_app_bundle_test.dart` pbxproj test uses `LocalFileSystem` + relative path** (line ~1563). CWD-dependent; fails if `dart test` runs from a subdirectory. Anchor via `Platform.script`.
- **M9 — `_kTvosMinimumOSVersion='13.0'`** (`application.dart:562`) has a comment saying it "must match `TVOS_DEPLOYMENT_TARGET`" but no assertion enforces it. Drift → App Store validation rejection. Add a test asserting both agree.
- **M10 — `xcode_debug.dart` is a `src/` internal with no stability contract.** Upstream is actively narrowing the Xcode-script path (Xcode 26+ prefers `IOSCoreDeviceLauncher`). Add an SDK-bump-checklist note to re-verify `debugApp` / `XcodeDebugProject` signatures on the next bump.
- **M11 — PR bundles three concerns** (SDK bump + shader removal + wireless debug) in one `tvos_device.dart` rewrite. Rolling back an engine regression couples 150+ lines of unrelated device logic. Process note, not a code defect.

---

## Passed Checks (verified clean)

- **MetalLibInterposer removal — complete & symmetric.** Both pbxproj edits internally consistent (every `PBXFileReference` removed with its `PBXBuildFile` + build-phase membership); zero dangling refs/orphaned IDs; all 4 `.metallib` binaries + `.h`/`.m` + `.copy.tmpl` removed in both example and template. Bridging header **edited not deleted** (retains `GeneratedPluginRegistrant.h`), so `SWIFT_OBJC_BRIDGING_HEADER` still valid. The interposer self-installed via `+load`, not an AppDelegate call, so deleting the source fully unwires it. "Goes inert" claim holds (byte-size-keyed swizzle finds no match against the new tvOS metallibs and passes through).
- **`application.dart` rewrite — no regression to PR #17's AOT work.** The +223/−155 is: `_copyMetalLibs` removal + unused `tvos_cache.dart` import removal + App.framework embed extraction + `_copyFlutterAssets` rewrite (fixes `assets/assets/…` nesting, issue #18) + richer `buildAppFrameworkInfoPlist`. PR #17's gen_snapshot obfuscate/split-debug-info builder is untouched (verified the diff ends on its unchanged doc-comment context line).
- **`Embed App.framework` rsync is safe.** Empirically tested: `rsync -av --delete src/App.framework dest/Frameworks/` (non-trailing-slash source) prunes only *inside* the transferred subtree — sibling `Flutter.framework` survives.
- **Engine-only separation (9ddcb1d):** no `#if` / `dart.library.*` added.
- **Version consistency:** flutter.version `924134a44c189315be2148659913dda1671cbe99`, engine.version `v1.0.0-flutter3.44.1`, pubspec/README/CHANGELOG all `1.2.0` / `3.44.1`.
- **AppleScript injection — safe** (separate argv, no shell). **mDNS client closed** in `finally`. **lldb stall detection robust** (75 s timeout, not string match).
- **`parseDeviceUdid` never throws** on malformed/array/wrong-type JSON (guarded with `is Map`/`is String`, only `FormatException` possible and caught). Unit tests cover these.
- **Test fixtures clean** — `copyFlutterAssetsTree` tests assert the two real invariants (exact mirror, no self-nesting); `parseDeviceUdid` cases map 1:1 onto the null-producing branches with realistic sibling keys.

---

## Summary

- **Critical/Important: 7** — all clustered in the new wireless-debug flow in `lib/tvos_device.dart`.
- **Minor: 11**
- **Recommendation: REQUEST CHANGES.**

The shader removal and version bump are clean and merge-ready. The wireless-debug flow needs the guard/cleanup fixes before merge — priority order:

1. **#4** (silent dead hot reload — worst UX) and **#3** (orphaned Xcode session on permission-denied throw) — these bite a real wireless user immediately.
2. **#1** (`globals.xcode!` crash) and **#5** (`throwToolExit` out of the fallback).
3. **#2** (`dispose()` leak) and **#6** (swallowed UDID-resolution stderr).
4. **#7** (docs) before tagging the release.

Most fixes are small (a guard + a `printWarning` + a try/finally). The underlying logic faithfully mirrors upstream and is sound; it's the error/cleanup edges that need tightening.
