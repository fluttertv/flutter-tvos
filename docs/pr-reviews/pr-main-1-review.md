# PR Review: fluttertv/flutter-tvos #1 — Add Remote Control (RCU) Dart API to flutter_tvos package

**Repo:** fluttertv/flutter-tvos
**Branch:** `DenisovAV:rcu` → `fluttertv:main`
**Diff:** +1244 / −30 across 14 files
**Date:** 2026-04-23
**Reviewers:** 6 agents (CLI/policy, Dart package, architect, silent-failure-hunter, type-design-analyzer, code-reviewer). Copilot CLI second opinion attempted but hit a GitHub Copilot rate-limit (429, 5h cool-off) before it finished enumerating findings — it only spun up its own parallel reviewers and stopped. Our 6-agent signal is unchanged.

---

## Critical Issues

### C1. `LogicalKeyboardKey.select` maps to kVK_Return — ActivateIntent does not fire on touchpad click

**File:** `packages/flutter_tvos/lib/src/rcu/key_simulator.dart:69`

```dart
if (key == LogicalKeyboardKey.select) return 0x24;   // kVK_Return
```

`0x24` on the `macos` keymap decodes to `LogicalKeyboardKey.enter`, not `select`. This is the **primary tap-to-activate path** for the example app and every real tvOS app that uses `FocusableActionDetector` / `Actions.invoke`. Default `WidgetsApp` shortcuts bind `ActivateIntent` to `enter`+`space`, so in practice activation works by accident (enter flows through). But:

- Any app code listening for `LogicalKeyboardKey.select` explicitly (via `KeyboardListener`, custom `Shortcuts`) receives **nothing**.
- The docstring comment at `tv_remote_controller.dart` refers to `LogicalKeyboardKey.select` as the emitted key, which is wrong.
- This creates a silent gap between the stated contract and what arrives in Dart.

**Fix:** use `0x4C` (macOS numpad Enter, which Flutter's Darwin key mapping resolves to `LogicalKeyboardKey.select`) or route touchpad clicks through native `sendKey:@"select"` instead of the Dart `channelBuffers` path so the engine's key embedder handles the mapping. The engine already maps `"select"` → `0x24` in `_MacOsKeyCodeForLogicalName` — that would need the same fix too.

_Reported by: code-reviewer._

### C2. Raw-listener list mutated during iteration — `ConcurrentModificationError` at runtime

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_controller.dart:209-211`

```dart
for (final listener in _rawListeners) {
  listener(event);
}
```

A listener that calls `removeRawListener` or `addRawListener` during delivery — a realistic pattern (video scrubber self-removes on lift; debug inspector re-subscribes on a gesture) — throws `ConcurrentModificationError`. The exception also aborts the post-listener `switch (phase)` block, leaving `_swipe` in an inconsistent state (`onStart` never matched by `onEnd`) and `_lastClickKey` dangling.

**Fix:** iterate over a snapshot: `for (final listener in List.of(_rawListeners))`. Also wrap each listener invocation in `try`/`catch` + `FlutterError.reportError` so one bad listener doesn't poison the rest.

_Reported by: silent-failure-hunter, architect, code-reviewer._

### C3. README code example does not compile

**File:** `packages/flutter_tvos/README.md` "Tuning thresholds" block (around line 102).

```dart
TvRemoteController.instance.config = const TvRemoteConfig(
  shortSwipeThreshold: 0.4,
  keyRepeatInterval: Duration(milliseconds: 100),   // <-- field does not exist
);
```

`TvRemoteConfig` (tv_remote_controller.dart:27-45) has only `shortSwipeThreshold`, `fastSwipeThreshold`, `dpadDeadZone`. The config's own doc explicitly says "Key-repeat timing (initial delay + interval) lives in the native plugin and is not exposed here." Users copying the snippet get a compile error.

**Fix:** remove `keyRepeatInterval` from the snippet. Add a prose note that repeat timing is fixed in the native plugin; if tunability becomes needed later, it will land via method-channel call.

_Reported by: CLI reviewer, Dart package reviewer._

### C4. CHANGES.md claims files and tests that do not exist

**File:** `CHANGES.md` (RCU section).

The section lists `lib/src/rcu/key_repeat.dart` as NEW and says it is "tested with fake_async"; it also claims "19 new unit tests" overall.

Reality after Phase 1 of the plan:
- `key_repeat.dart` was **deleted** (logic moved to native).
- `fake_async` is imported nowhere in `packages/flutter_tvos/test/` (grep confirms).
- Test count is closer to 26 additions, not 19.
- The `fake_async: ^1.3.1` dev dep in `pubspec.yaml:21` is now dead weight.

**Fix:** rewrite the RCU section of `CHANGES.md` to match the final architecture (native KeyRepeater, Dart `key_simulator` for click events only). Remove the `fake_async` dev dep. Add the `meta` dep justification or relocate it (see I2).

_Reported by: CLI reviewer, Dart package reviewer._

---

## Important Issues

### I1. `Podfile.lock` commits a developer-specific absolute path

**File:** `packages/flutter_tvos/example/tvos/Podfile.lock:5,9`

`:path:` lines now reference `/Users/sashadenisov/Work/fluttertv/...` (replacing a previous `/Users/aliustaoglu/...`). CI and any other developer will get a CocoaPods install failure. Previous PRs already had this problem; this PR made it churn again.

**Fix:** either (a) gitignore `packages/flutter_tvos/example/tvos/Podfile.lock` (the example Podfile is a relative path dependency on `../../`, which regenerates the lock per-developer), or (b) rewrite the Podfile to use a truly relative path so the lock resolves portably. Option (a) is more pragmatic — the lock has no team-shared value for a local-path pod.

_Reported by: CLI reviewer, Dart package reviewer, code-reviewer._

### I2. `meta` listed as a runtime `dependency` but used only for `@visibleForTesting`

**File:** `packages/flutter_tvos/pubspec.yaml:15`

`meta` added to `dependencies` (ships to consumers). But `@visibleForTesting` is only used on `debugInit` / `debugReset` — test-only entry points. `flutter/foundation.dart` already re-exports `@visibleForTesting`; no direct `meta` dep is needed.

**Fix:** remove from `dependencies`. If the import still fails, rely on `package:flutter/foundation.dart` which already ships with Flutter.

_Reported by: code-reviewer._

### I3. No test for the click-race protection (CR #1 fix)

**File:** `packages/flutter_tvos/test/rcu/tv_remote_controller_test.dart:96-109` — the existing `click_s / click_e` test only verifies **phase delivery to raw listeners**, not the key event sequence.

`_handleClickStart` (tv_remote_controller.dart:244-260) now emits `keyup` for the previous `_lastClickKey` before the new `keydown` to protect against double-`click_s` without a matching `click_e`. There is no test exercising this path. The click-race fix can silently regress.

**Fix:** add a test using `TestDefaultBinaryMessengerBinding.setMockMessageHandler` on `SystemChannels.keyEvent.name` that records emitted `keydown`/`keyup` sequences, send `click_s → click_s → click_e`, assert 2 keydown + 2 keyup in the right order.

_Reported by: Dart package reviewer, silent-failure-hunter, code-reviewer._

### I4. No test for directional-click bias (CR #6 scope verification)

**File:** `packages/flutter_tvos/test/rcu/tv_remote_controller_test.dart`

`_handleClickStart` branches on `_lastDpadX.abs() >= config.dpadDeadZone` and converts to `arrowLeft/Right` instead of `select`. No test sends `loc` then `click_s` and verifies the bias. The "bias only on touches channel" policy (CR #6) is only visually verifiable.

**Fix:** add two tests — (a) dpadX=0.6 + click_s emits `arrowRight`, (b) dpadX=0 + click_s emits `select`.

_Reported by: silent-failure-hunter, code-reviewer._

### I5. Cache-invalidation mid-gesture silently drops the remaining gesture

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_controller.dart:126-140` (the `_swipe` getter).

If an app mutates `config` during an active gesture (e.g. between `started` and the next `move`), the getter creates a fresh `SwipeDetector` with `_isActive = false`, so the next `onMove` silently returns null. The in-progress gesture is dropped, but raw listeners keep receiving events — so the inconsistency is invisible.

**Fix:** copy `_segmentStartX/Y` and `_isActive` from the old detector into the new one when invalidating; or document "do not mutate config mid-gesture" and assert in debug.

_Reported by: architect, silent-failure-hunter._

### I6. `runTvApp` silently force-installs `WidgetsFlutterBinding` when app uses a custom binding

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_controller.dart:311` (inside `runTvApp`).

`WidgetsFlutterBinding.ensureInitialized()` is called unconditionally. Apps that subclass `WidgetsBinding` (analytics tooling, custom observers) must `ensureInitialized()` their own subclass **before** `runTvApp` — or `runTvApp` silently wins the init race and installs the vanilla `WidgetsFlutterBinding`. This is a Flutter-wide footgun, but the docstring of `runTvApp` doesn't mention it.

**Fix:** extend the docstring to say "if you use a custom `WidgetsBinding`, initialize it before calling `runTvApp`, and call `TvRemoteController.instance.init()` manually instead."

_Reported by: architect._

### I7. Hot restart leaves the singleton stale — RCU dead until cold restart

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_controller.dart:112-113` — `instance` is a Dart-static singleton.

On hot restart, Dart VM reinitializes statics → `_initialized` becomes `false` and channel handlers are gone. `runTvApp` is not re-invoked on hot restart. So the controller is dead (no channel listeners) until the next cold start. Since hot restart is the primary dev loop, this degrades developer experience significantly.

**Fix:** either (a) register the handlers in an `hotRestartListener` (if Flutter exposes one), or (b) document clearly that hot restart does not re-register the RCU handlers. Option (b) is easier, but add a `debugPrint('RCU channels inactive — cold restart required')` as a breadcrumb.

_Reported by: architect._

### I8. Config ranges are unvalidated

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_controller.dart:22-45` (TvRemoteConfig).

No assertions on `shortSwipeThreshold > 0`, `shortSwipeThreshold <= fastSwipeThreshold`, `0 < dpadDeadZone <= 1.0` (or `> 1.0` as the "disable" sentinel). `TvRemoteConfig(shortSwipeThreshold: -1)` compiles and produces a detector that fires on every move.

**Fix:** add assertions in the `const` constructor body (Dart supports const asserts now):
```dart
const TvRemoteConfig({...})
  : assert(shortSwipeThreshold > 0),
    assert(fastSwipeThreshold >= shortSwipeThreshold),
    assert(dpadDeadZone > 0);
```

_Reported by: type-design-analyzer._

### I9. `SwipeEvent` constructor exposed publicly — derived invariant can be forged

**File:** `packages/flutter_tvos/lib/src/rcu/swipe_detector.dart` — `SwipeEvent` const public constructor.

The invariant `isFast == (magnitude >= fastThreshold)` is upheld at emission, but any consumer can forge `SwipeEvent(direction: .right, magnitude: 100.0, isFast: false)`. Since `SwipeEvent` is an output type only, private constructor is safer.

**Fix:** make constructor private: `SwipeEvent._(...)` and expose a `@visibleForTesting` factory if tests need to build one.

_Reported by: type-design-analyzer._

### I10. Wire schema doc mismatch — `timestamp` field advertised, not emitted

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_channels.dart:30-35`

Docstring shows the touches schema as `{type, x, y, timestamp: <int>}`. Native PR #2 emits only `{type, x, y}`. Dart parser doesn't read `timestamp` either. Harmless but misleading doc.

**Fix:** remove `timestamp` from the docstring or start emitting it natively.

_Reported by: Dart package reviewer, CLI reviewer._

### I11. `CHANGES.md` reads like internal architecture notes, not a changelog

**File:** `CHANGES.md` (RCU section).

Documents refactoring details ("removed ~200 lines", "Python 3.13+ compatibility", "GameController double-registration fix") that downstream app authors don't care about. Only the "For app authors" block at the end is user-facing.

**Fix:** split the section — a short user-facing summary at the top, then an optional "Implementation notes" collapsible or linked out to the PR description.

_Reported by: CLI reviewer._

---

## Minor Issues

### M1. Double import of `widgets.dart`

**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_controller.dart:8-9`

```dart
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding, runApp;
import 'package:flutter/widgets.dart' as widgets show Widget;
```

Two imports of the same library — one for aliased `Widget`, one `show`-filtered. Works but ugly. Combine into one show list or use a single aliased import.

_Reported by: CLI reviewer._

### M2. `key_simulator.dart` has dead mapping for `LogicalKeyboardKey.enter`

**File:** `packages/flutter_tvos/lib/src/rcu/key_simulator.dart:70`

The only caller is `_handleClickStart` which produces `select`, `arrowLeft`, or `arrowRight`. `enter` is never passed in. Safe to remove.

_Reported by: Dart package reviewer._

### M3. `TvRemoteTouchPhase.loc` conflates D-pad reports with touches

**File:** `tv_remote_controller.dart:76-98`

`loc` is a D-pad position snapshot (continuous, ranges naturally `[-1, 1]`), not a real touch phase. Mixing it into the same enum with `started/move/ended/cancelled` blurs the contract. Works today; a sealed hierarchy (`TvRemoteTouchEvent` / `TvRemoteDpadEvent` / `TvRemoteClickEvent`) would be cleaner long-term.

Not blocking; noted for type-design polish.

_Reported by: type-design-analyzer._

### M4. Comment in `swipe_detector_test.dart` mismatches assertion

**File:** `packages/flutter_tvos/test/rcu/swipe_detector_test.dart` — "reverses direction mid-touch" test.

Comment says the result should be `Up`, the `expect` says `left`. Both cannot be right; the assertion is actually correct (tie goes to `absDx >= absDy`). The comment is wrong and will mislead a future maintainer.

**Fix:** rewrite the comment to match: `// dx=-0.4, dy=-0.4 — tie goes to absDx >= absDy, and dx<0 → Left`.

_Reported by: code-reviewer._

### M5. `TvRemoteTouchEvent.x/y` range in docstring only

No runtime assertion that `x, y ∈ [-1, 1]`. A misbehaving native side can deliver out-of-range values unnoticed.

_Reported by: type-design-analyzer._

### M6. No `SwipeDetector` in public export surface

`SwipeEvent` and `SwipeDirection` are exported via `flutter_tvos.dart`, but `SwipeDetector` itself is not. `SwipeEvent` is only produced by the detector, so the type is reachable only to raw-listener consumers. Either document that relationship, or consider exporting a typedef for clarity.

_Reported by: architect._

### M7. `TvRemoteChannels` not in public exports

If advanced consumers need to mock the channels for integration tests, they currently import via `src/` path (bypassing the public API). Consider exporting `TvRemoteChannels` under a `@visibleForTesting` comment or add a `test_support.dart` entry-point.

_Reported by: architect._

### M8. `example/lib/main.dart`: no shortcut override for `LogicalKeyboardKey.select`

Related to C1. The demo relies on `WidgetsApp.defaultShortcuts` binding `ActivateIntent` to `enter` + `space`. After C1 is fixed (`select` produces the correct logical key), the default shortcuts won't bind it. Add:

```dart
MaterialApp(
  shortcuts: {
    ...WidgetsApp.defaultShortcuts,
    LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
  },
  ...
);
```

_Reported by: silent-failure-hunter._

### M9. `simulateKeyEvent` return value discarded everywhere

Every call site `await`s and throws away the `bool`. The `false` return mixes two distinct conditions: "Flutter didn't handle this key" (expected) and "logical key not in mapping — programming error". A `debugPrint` / `assert` on the mapping-miss path would catch drift during development.

_Reported by: silent-failure-hunter._

### M10. Every `_onButtonCall` branch returns `null` silently on unexpected input

6 early-return exits: malformed args, missing keyName, unknown key, missing command, unknown command, unknown method. A `debugPrint('tv_remote: unhandled button method ${call.method} args=$args')` on unknown-branch arms would surface native-side protocol drift during dev.

_Reported by: silent-failure-hunter._

---

## Passed Checks

- **Engine-only separation (commit 9ddcb1d):** confirmed — no `dart.library.*`, `kIsWeb`, or `defaultTargetPlatform` in `packages/flutter_tvos/lib/`. Only runtime `FlutterTvosPlatform.isTvos` check.
- **Channel names match native** (PR #2): `flutter/tv_remote` + `flutter/tv_remote_touches` with `JSONMethodCodec` / `JSONMessageCodec`.
- **All phase strings** native emits (`started`/`move`/`ended`/`cancelled`/`loc`/`click_s`/`click_e`) are parsed by Dart `_phaseFromString`.
- **Select bias scope (CR #6):** `_onButtonCall` does NOT apply bias — implementation correct (though untested per I4).
- **Cache invalidation (CR #2):** `_swipe` getter correctly invalidates on threshold change — implementation correct (though mid-gesture case in I5 is a gap).
- **CLI-side impact:** zero. RCU work is fully contained in `packages/flutter_tvos/`. `lib/*.dart` untouched.
- **`.gitignore`:** no currently-tracked files under `artifacts/` or `flutter_upstream_tvos_engine/`. `engine_artifacts/` still ignored separately.
- **`SwipeDirection` enhanced enum:** exemplary — every direction carries its arrow key by construction.
- **Public API surface:** `lib/flutter_tvos.dart` exports are deliberate; no private-class leakage.
- **Test isolation:** setUp/tearDown correctly call `debugReset` on the singleton.
- **Dart test messages shape** (`{type, x, y}`) matches native emission.
- **iOS/Android passthrough:** on non-tvOS, `FlutterTvosPlatform.isTvos` is `false` → `init()` is a no-op → channels never wire. Verified.

---

## Summary

- **Critical:** 4 (select → enter mapping wrong; concurrent-modification on listener iteration; README example won't compile; CHANGES.md lies about files)
- **Important:** 11 (Podfile.lock portability, meta dep placement, missing tests for CR fixes, mid-gesture cache bug, WidgetsBinding doc, hot restart note, config validation, SwipeEvent forgery, wire doc mismatch, CHANGES tone)
- **Minor:** 10 (dead code, enum design, test comment fix, range docs, export polish, shortcut override, silent returns)

**Recommendation:** **REQUEST CHANGES** before merge.

The blocker is **C1 (`select` → `enter` mapping)** — the primary tap-to-activate path doesn't produce the key it claims to. Combined with **C2 (ConcurrentModificationError)** on any listener that self-removes, these are real runtime issues, not theoretical.

**C3 (README) and C4 (CHANGES)** are doc blockers — users would hit them on copy-paste. Fix together with C1 so docs and implementation land in one pass.

Suggested order:
1. Fix C1 (keymap) + M8 (shortcut override in example) — one coherent fix.
2. Fix C2 (snapshot iteration + try/catch with `FlutterError.reportError`).
3. Fix C3 + C4 (docs now match reality); remove `fake_async` dep.
4. Address I1 (gitignore Podfile.lock) and I2 (`meta` placement).
5. Add I3 + I4 tests.
6. Batch I5–I11 + all Minor into polish follow-ups.

Total estimated effort: half a day for Criticals + Important tests; another half-day for all Important lifecycle items; Minor can live in their own cleanup PR.
