# PR Review: MAUstaoglu/flutter_upstream_tvos_engine #2 — Extract Apple TV remote handling into FlutterTvRemotePlugin

**Repo:** MAUstaoglu/flutter_upstream_tvos_engine
**Branch:** `rcu-plugin-refactor` → `main`
**Diff:** +1069 / −223 across 10 files
**Date:** 2026-04-23
**Reviewers:** 7 agents (native, architect, silent-failure-hunter, type-design-analyzer, code-reviewer, integration, Copilot CLI second opinion). Copilot converged on the same findings — see "Copilot convergence" at the bottom.

---

## Critical Issues

### C1. `FlutterTvRemotePluginTest.mm` is not built (blocking)

**File:** `engine/src/flutter/shell/platform/darwin/ios/BUILD.gn`

The 269-line test file (13 XCTestCase methods covering attach/detach, VC migration, zero-sized view, `sendKey` mapping, and the full `FlutterTvKeyRepeater` state machine) is **not listed** in the `ios_test_flutter` test target (lines ~259–297). The `flutter_framework_source` target correctly lists the plugin `.h/.mm/_Internal.h`, but the test translation unit is never compiled. Every assertion in the file is dead code — zero regression protection.

**Fix:** add `"framework/Source/FlutterTvRemotePluginTest.mm"` to the `ios_test_flutter` sources block (guarded behind `if (is_tvos)` if the build system requires). Re-run `ninja -C out/... flutter/shell/platform/darwin/ios:ios_test_flutter` to confirm the symbols appear.

_Reported by: native reviewer, integration reviewer, code reviewer._

### C2. `handleCenterTap` keyboard-activation guard was silently dropped (functional regression)

**File:** `engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemotePlugin.mm:348-356` (vs. previous `FlutterViewController.mm:1201-1215`)

The old code checked `FlutterTextInputPlugin.tvosKeyboardPending` before sending `click_s` — if a text field was focused and waiting for keyboard activation, Select was consumed to open the keyboard rather than dispatched to Dart. The new `handlePress:` always forwards `click_s`/`click_e` through the touches channel. Result: tapping Select on a focused TextField now both opens the keyboard (via `FlutterTextInputPlugin` path) **and** fires a spurious click to Dart, which may trigger focus/navigation handlers unintentionally.

**Fix:** restore the guard in `handlePress:` for `UIPressTypeSelect`. Access `FlutterTextInputPlugin* tip = self.engine.textInputPlugin;` and short-circuit if `tip.tvosKeyboardPending`. Cross-reference `tvos_patches/TVOS_TEXT_INPUT_PATCH.md` if present.

_Reported by: native reviewer (code-reviewer agent)._

---

## Important Issues

### I1. `MPRemoteCommandCenter` handlers never unregistered — handler leak + duplicate fires on engine restart

**File:** `FlutterTvRemotePlugin.mm:725-728` (`registerMediaCommandsOnce`) and the entire `detach` block.

`addTargetWithHandler:` accumulates handlers on the process-wide `MPRemoteCommandCenter` singleton. On engine restart / engine groups / hot-restart, a second `FlutterTvRemotePlugin` is created and adds a second set; both fire for every media button. The `mediaCommandsRegistered` flag is per-instance and doesn't help.

**Fix:** capture the token returned by `addTargetWithHandler:` in an `NSMutableArray`. In `detach`, iterate the array and call `[command removeTarget:token]`. Clear the array + reset `mediaCommandsRegistered = NO` so a re-attach re-registers cleanly.

_Reported by: native, silent-failure-hunter, architect, type-design-analyzer._

### I2. `resetContinuousSwipeState` zeros `lastTouchX/Y`, corrupting the first `move` delta

**File:** `FlutterTvRemotePlugin.mm:412-415` (and see `resetContinuousSwipeState` and its call from `handleTouches` on `isStart`).

On touch-start the code does `self.lastTouchX = x; self.lastTouchY = y;` then `[self resetContinuousSwipeState];` — but the reset method itself sets `lastTouchX/Y` back to 0. So the very first `move` computes `dx = x - 0`, which looks like a huge jump from the origin rather than a real delta. Subsequent moves self-correct, but `continuousSwipeMoveCount` resets on the spurious first direction → repeat kick-in is delayed by one extra move.

**Fix:** either (a) `resetContinuousSwipeState` should not touch `lastTouchX/Y` (leave that to `handleTouches`), or (b) call `reset` FIRST and then assign `lastTouchX/Y` last.

_Reported by: native reviewer._

### I3. `controllerDidDisconnect:` runs off-main-thread — data race on `configuredControllers` and `GCMicroGamepad`

**File:** `FlutterTvRemotePlugin.mm:504-513` vs. `controllerDidDisconnect:` (not wrapped in `dispatch_async`).

`controllerDidConnect:` correctly wraps its body in `dispatch_async(dispatch_get_main_queue(), ...)` because `GCControllerDidConnectNotification` can be delivered on a background thread on physical devices. The symmetric `controllerDidDisconnect:` does not — it mutates `configuredControllers` (non-thread-safe `NSHashTable`) and sets `gamepad.dpad.valueChangedHandler = nil` from whatever thread NSNotificationCenter chose. Data race.

**Fix:** mirror the connect handler — wrap the body in `dispatch_async(dispatch_get_main_queue(), ...)`.

_Reported by: code reviewer._

### I4. `FlutterEngine_Internal.h` imports `FlutterTvRemotePlugin.h` unconditionally

**File:** `engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine_Internal.h` (the new `#import` line, ~line 101).

The header is included by many iOS translation units. Even though `FlutterTvRemotePlugin.h`'s content is `#if TARGET_OS_TV`-guarded, the bare `#import` violates the project's convention of keeping tvOS-specific includes inside `#if TARGET_OS_TV` blocks in shared iOS headers (all other tvOS imports in this file follow that rule).

**Fix:**
```objc
#if TARGET_OS_TV
#import "flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemotePlugin.h"
#endif
```

_Reported by: code reviewer, architect._

### I5. Dart test-file `sendKey_ignoresUnknownKeyName` enshrines silent-drop

**File:** `FlutterTvRemotePlugin.mm:436-439` — `sendKey:` returns silently for unknown `logicalKeyName`.

`_LogicalKeyNameForPressType` returns `@"playPause"` for `UIPressTypePlayPause`, but `_MacOsKeyCodeForLogicalName` **does not map `@"playPause"`** — it returns -1. If anyone ever calls `sendKey:@"playPause"` (not done today, but the keyRepeater block or a future extension might) it no-ops. Asymmetry between the two maps, invisible to tests.

**Fix:** either (a) add `@"playPause"` → `MediaPlayPauseKeyCode` in `_MacOsKeyCodeForLogicalName` and document that `sendKey` is the canonical interface, or (b) assert in debug builds that every name produced by `_LogicalKeyNameForPressType` has a keyCode mapping. Minimum: `NSLog` / `FML_DLOG` when the mapping is absent.

_Reported by: silent-failure-hunter, type-design-analyzer._

### I6. Touches-forwarding nil-check is not a liveness check

**File:** `FlutterViewController.mm:1404-1407, 1417-1419, 1430-1432, 1443-1445`.

The nil-check `if (plugin != nil)` only guards against non-tvOS builds / unset plugin. It does **not** detect "plugin's engine has gone nil" or "plugin is mid-detach on another queue". The plugin's own `sendKey:` guards `engine == nil`, but `handleTouches:` posts to `touchesChannel` unconditionally — the channel internally holds the messenger, so touch events can flow into a dead engine's isolate.

**Fix:** inside `handleTouches:phase:view:`, early-return if `self.engine == nil || self.viewController == nil` (the latter indicates a detached state). This already mirrors the pattern used in `sendKey:`.

_Reported by: silent-failure-hunter, type-design-analyzer._

### I7. `viewDidLoad`-only attach misses `setViewController:` re-binding path

**File:** `FlutterViewController.mm:874` attaches in `viewDidLoad` only.

`FlutterEngine.setViewController:` (see `FlutterEngine.mm:519-540`) is used by engine groups / headless-to-headed transitions and already re-assigns other per-VC plugin state (e.g. `textInputPlugin.viewController`). The TV plugin does not participate — if an engine is re-attached to a different VC via `setViewController:` (not via `viewDidLoad`), `attachToViewController:` is never called.

**Fix:** mirror `textInputPlugin` — have `FlutterEngine.setViewController:` call `[self.tvRemotePlugin attachToViewController:viewController]` when non-nil, `[self.tvRemotePlugin detach]` when nil.

_Reported by: architect._

### I8. `_Internal.h` import for `FlutterTvRemotePlugin` leaks into iOS builds

See I4 — same concern from the architect angle (keep engine-internal headers OS-symmetric).

### I9. Stale view-controller `dealloc` detaches plugin from the active VC

**Files:** `FlutterViewController.mm:1085-1092` (new detach call in `dealloc`) + `FlutterTvRemotePlugin.mm:258-305` (`attach`/`detach` implementation).

Scenario: engine group or navigation flow causes `FlutterEngine` to migrate from VC A to VC B via `attachToViewController:B`. The plugin's `attach` logic sees a different VC, calls `detach` internally (cleaning VC A's recognizers), then sets `_viewController = B`. **Later**, when VC A deallocs (retained elsewhere until now), its `dealloc` calls `[self.engine.tvRemotePlugin detach]` unconditionally — but the plugin is now attached to VC B. VC A's dealloc tears everything off VC B, killing remote input on the active VC.

**Fix:** in `FlutterViewController.mm` `dealloc`, only call `detach` if the plugin is still attached to *this* VC:
```objc
#if TARGET_OS_TV
if (self.engine.tvRemotePlugin.viewController == self) {
  [self.engine.tvRemotePlugin detach];
}
#endif
```
This requires exposing `viewController` as a readonly property (already internal — extend `_Internal.h`).

Alternatively, plugin's `detach` method can accept the VC it's being torn off from and no-op if it doesn't match.

_Reported by: Copilot CLI — independent second opinion._

---

## Minor Issues

### M1. `dealloc` ordering in `FlutterViewController`: plugin `detach` runs after `removeInternalPlugins`

**File:** `FlutterViewController.mm:1082-1090` (approximate, pre-diff line numbers).

`dealloc` sequence: `removeInternalPlugins` → `deregisterNotifications` → `[self.engine.tvRemotePlugin detach]`. If the weak `self.engine` reference goes nil in the same ARC drain pass, `detach` is a silent no-op. Move the detach call ahead of `removeInternalPlugins` or observe the VC lifecycle directly (via `setViewController:` hook, see I7).

### M2. `_Internal.h` convention matches `FlutterPlatformPlugin_Test.h`

The `FlutterTvRemotePlugin_Internal.h` header used by tests is consistent with existing internal-header conventions in the codebase. Positive note — no action required.

### M3. `export CLEANUP_SHIM_DIR` is unnecessary

**File:** `build_tvos_engine.sh:21`.

`trap` closures over the variable in the parent shell scope regardless of `export`; exporting propagates it to child processes (ninja, gn) with no consumer. Remove the `export` keyword to avoid leaking internal bookkeeping into subprocesses.

### M4. Python shim trap only fires on EXIT, not on INT/TERM/HUP

**File:** `build_tvos_engine.sh:44`.

`trap '...' EXIT` cleans up `SHIM_DIR` on normal script termination, but Ctrl-C (SIGINT) leaves the `mktemp` directory orphaned. Expand to `trap '...' EXIT INT TERM HUP`. Additionally, validate the shim once after creation: `"$SHIM_DIR/python3" --version >/dev/null || { echo "python3.12 shim broken"; exit 1; }`.

### M5. `deps_patches/*.patch` applied with `|| true` — silent failures

**File:** `build_tvos_engine.sh:77-95`.

`(cd ... && git apply -p0 ...) || true` followed by unconditional `touch "$DEPS_MARKER"` means a failed patch application (hunk drift, missing dir, wrong -p level) is completely invisible and the marker blocks retry forever. Detect with `git apply --check` first; distinguish "already applied" from "apply failed" via `git apply --check -R`; only touch the marker if every patch either applied cleanly or was already in place.

### M6. Stringly-typed channel values

**File:** `FlutterTvRemotePlugin.mm` and `tv_remote_controller.dart`.

Phase strings (`@"started"`, `@"move"`, ...) and logical key names (`@"arrowUp"`, ...) exist in 3+ switch/if ladders across the ObjC/Dart boundary. Typo drift is a latent risk. Two mitigations:
- Extract `static NSString* const kFltvKeyArrowUp = @"arrowUp";` etc. so all native switches share identity.
- Add a unit test that asserts `_LogicalKeyNameForPressType` names form a subset of `_MacOsKeyCodeForLogicalName` (or route them via the button channel).

### M7. `UIPressTypeSelect` handler ignores `Changed`/`Failed` states

**File:** `FlutterTvRemotePlugin.mm:351-358`.

With `minimumPressDuration = 0`, `UILongPressGestureRecognizer` transitions through `Began → Changed* → Ended` (happy path) or `Began → Failed` (interrupted). Current code emits `click_s` on Began and `click_e` on Ended/Cancelled only. On `Failed`, no `click_e` is ever sent and Dart state stays "pressed".

**Fix:** treat `Failed` as end too.

### M8. `handlePress:` derives pressType from `allowedPressTypes.firstObject`

**File:** `FlutterTvRemotePlugin.mm:344-347`.

Works because each recognizer is installed with exactly one allowed type, but fragile — if the installation code ever sets two allowed types, routing silently breaks. Consider attaching the type via `objc_setAssociatedObject` or a `NSMapTable<UIGestureRecognizer*, NSNumber*>` at install time.

### M9. Schema docstring / implementation mismatch in `tv_remote_channels.dart`

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_channels.dart:34`.

Documents the touches schema as `{type, x, y, timestamp}`. Native `sendTouchEventOfType:x:y:` only emits `{type, x, y}`. Dart parser doesn't read `timestamp` either. Harmless but misleading — either remove the field from the docstring or start emitting it.

### M10. `configureController:` silently skips MFi gamepads without a microGamepad projection

**File:** `FlutterTvRemotePlugin.mm:686-689`.

MFi extended gamepads without a `microGamepad` projection are entirely ignored. Users see "nothing happens" with zero diagnostic. Add a debug log naming `controller.vendorName`.

### M11. `FlutterTvKeyRepeater.dealloc` doesn't emit a trailing keyup

**File:** `FlutterTvRemotePlugin.mm:103-106`.

`dealloc` invalidates timers but doesn't emit keyup for `activeKey`. `FlutterTvRemotePlugin.dealloc` calls `stopRepeat` first, so it works by construction — but the repeater isn't self-healing in isolation. Low-priority since the plugin's dealloc handles it.

### M12. `initWithEngine:` uses `NSAssert` — compiled out in release

**File:** `FlutterTvRemotePlugin.mm:219` (approximate).

`NSAssert(engine, ...)` is stripped in release builds. A nil engine then produces a plugin whose every method silently fails. Use `NSParameterAssert` (also stripped) + a real runtime guard that returns nil or an `FML_CHECK`.

### M13. `handlePress:` default `pressType = UIPressTypeSelect` on nil `allowedPressTypes`

**File:** `FlutterTvRemotePlugin.mm:540-544`.

If the recognizer is misconfigured with `allowedPressTypes = @[]`, the fallback is Select (activate) — destructive default. Prefer a safe no-op early-return with an assertion.

### M14. First-move direction "seeded" from start coords

Related to I2. Even after I2 is fixed, the first `move` computes delta from the actual start coord — that's correct but worth a code comment explaining the seed semantic, especially because the repeat threshold is 3 consecutive moves.

---

## Passed Checks

- Channel names match Dart-side constants (`flutter/tv_remote`, `flutter/tv_remote_touches`).
- Codecs aligned (`FlutterJSONMethodCodec` ↔ `JSONMethodCodec`; `FlutterJSONMessageCodec` ↔ `JSONMessageCodec`).
- All phase strings native emits (`started`/`move`/`ended`/`cancelled`/`loc`/`click_s`/`click_e`) are parsed by Dart `_phaseFromString`.
- All public `.h` methods implemented in `.mm`. All methods that tests consume are exposed via `.h` or `_Internal.h`.
- `FlutterEngine.mm` creates `tvRemotePlugin` after `binaryMessenger` is ready (ordering correct).
- `BUILD.gn` alphabetical ordering in `flutter_framework_source.sources` preserved (TextureRegistryRelay → TvRemotePlugin → UndoManager).
- Dart test messages (`{type, x, y}`) match native emission shape.
- `FlutterTvKeyRepeater` state machine in tests covers start/stop/switch-key/idempotent-same-key/stop-when-idle/periodic-firing.
- Weak-self pattern correctly applied in timer callbacks (guards against plugin dealloc mid-timer).
- iOS build remains buildable — all tvOS-specific code guarded with `#if TARGET_OS_TV`.
- Plugin ownership model follows `FlutterPlatformPlugin` pattern (weak engine, designated init, channels on engine.binaryMessenger).

---

## Copilot convergence

Independent second-opinion run (Copilot CLI, gpt-5.4 + claude-sonnet-4.5 + claude-haiku-4.5) converged on the same findings: I1 (MP handler leak), C2 (Select keyboard-activation regression), I3 (disconnect off-main race), M9 (timestamp doc mismatch). Copilot also independently surfaced **I9 (stale VC dealloc detaches active plugin)** — a real lifecycle race that none of the other agents caught. Copilot did not flag C1 (test file build wiring) or I2 (first-move delta bug); those came from the dedicated native-layer agent.

Copilot's recommendation: REQUEST CHANGES. Matches ours.

## Summary

- **Critical:** 2 (test file not wired into build, Select-press-during-text-input regression)
- **Important:** 9 (MP handler leak, continuous-swipe reset bug, disconnect thread race, iOS header leak, asymmetric key-name maps, touches nil-check too narrow, missing `setViewController:` hook, I8 duplicate, stale-VC dealloc race)
- **Minor:** 14 (dealloc ordering, build-script hygiene, silent patch failures, stringly-typed channels, gesture-state coverage, MFi diagnostic, etc.)

**Recommendation:** **REQUEST CHANGES** before merge.

Blockers are C1 (tests don't compile — effectively no regression coverage) and C2 (Select press during text input now leaks a click to Dart — functional regression from the old inline code). The Important items are not merge-blocking individually but collectively indicate the detach/restart lifecycle and the native/Dart contract need another pass. Several Minor items cluster around build-script hygiene and are worth batching into a follow-up PR.

## Suggested next steps

1. Fix C1 + C2. Re-run `./build_tvos_engine.sh debug_sim` and confirm `ios_test_flutter` links the new test file.
2. Address I1, I3, I6, I7 — all lifecycle / thread-safety. Each is small on its own.
3. Choose one of the asymmetric-map mitigations for I5/M6 (probably the constant-extraction one — cheapest) and do it now so the codebase stays maintainable.
4. Batch M3–M5 + M7–M14 into a polish PR; nothing here changes user-visible behavior.
