# PR Review: #1 — Add Remote Control (RCU) Dart API to flutter_tvos package

**Repo:** fluttertv/flutter-tvos  
**Branch:** rcu → main  
**Date:** 2026-04-23  
**Reviewers:** Automated review (Dart package layer)  
**Layers affected:** Dart package (`packages/flutter_tvos/lib/src/rcu/`), tests, public API surface, docs

---

## Important Issues

### I-1 · `tv_remote_controller.dart:214` — Raw-listener iteration: ConcurrentModificationError
`_onTouchMessage` iterates `_rawListeners` directly with `for (final listener in _rawListeners)`. If any listener synchronously calls `removeRawListener` (a documented use case), Dart throws `ConcurrentModificationError` at runtime. Snapshot the list before the loop:
```dart
for (final listener in List.of(_rawListeners)) {
  listener(event);
}
```

### I-2 · `key_simulator.dart:55–70` + `tv_remote_controller.dart:302–335` — Media keys & Play/Pause silently dropped
`_logicalKeyToMacOsKeyCode` has no entries for `mediaPlay`, `mediaPause`, `mediaStop`, `mediaPlayPause`, `mediaFastForward`, `mediaRewind`. `simulateKeyEvent` returns `false` silently for all of these. Combined with `_logicalKeyFromName('playPause')` → `LogicalKeyboardKey.mediaPlayPause` (also unmapped), **every media command and the Play/Pause button are silently no-ops** despite being documented as supported. Add macOS key codes for media keys (e.g. `kVK_F8` = `0x64` for Play/Pause) or route them via a non-keyevent mechanism.

---

## Minor Issues

### M-1 · `CHANGES.md:46` — Mentions `key_repeat.dart` as "NEW" but the file doesn't exist
The changelog describes `lib/src/rcu/key_repeat.dart` as a new file, but it is absent from both the diff and the repo. Stale draft text — remove the entry.

### M-2 · `tv_remote_channels.dart:37` — Doc comment omits `click_s` / `click_e` message types
The `touches` channel doc lists `"started" | "move" | "ended" | "cancelled" | "loc"` but not `"click_s"` / `"click_e"`, which are handled by the controller and are part of the contract. Add them to the doc comment.

### M-3 · `tv_remote_controller.dart:163` — `debugReset()` leaves stale swipe-cache fields
`_cachedSwipe`, `_cachedSwipeThreshold`, and `_cachedFastThreshold` are not nulled in `debugReset()`. The `onEnd()` call restores the detector to a correct state so behavior is fine, but test isolation is imperfect — a post-reset config-mutation test that doesn't change thresholds will reuse the pre-reset `SwipeDetector` instance. Null all three fields in `debugReset()` for complete cleanup.

### M-4 · `swipe_detector_test.dart:111` — Misleading comment contradicts assertion
The comment says "emits Up because |dy|=0.4 > |dx|=0.4 ties — right side wins by `>=`" but the assertion is `SwipeDirection.left`. The assertion is correct (dx=–0.4 → left, tie goes to X-axis); the comment is wrong and confusing.

### M-5 · `tv_remote_controller_test.dart` — Click-race and bias logic untested
The `_handleClickStart` click-race fix and D-pad bias are core correctness guarantees but have zero test coverage. Tests note "we can't assert key simulation without patching ServicesBinding" — consider using `TestDefaultBinaryMessengerBinding` to intercept `SystemChannels.keyEvent` and assert the emitted key codes for both the race scenario (two `click_s` without intervening `click_e`) and the bias (setting `_lastDpadX` via a `loc` event, then asserting `click_s` emits an arrow key).

---

## Passed Checks

- **Engine-only separation**: No `dart.library.*` checks anywhere; platform detection is `Platform.operatingSystem == 'tvos'` runtime only. ✅
- **Channel contract**: Names (`flutter/tv_remote`, `flutter/tv_remote_touches`) and codecs (`JSONMethodCodec` / `JSONMessageCodec`) are correct and consistent on both sides. ✅
- **Coordinate normalization**: No pixel offsets; `[-1.0, 1.0]` space throughout; no legacy `x – 1000` adjustments. ✅
- **Click race protection**: `_handleClickStart` emits keyup for `_lastClickKey` before the new keydown. ✅
- **Config mutation**: Getter-based `_swipe` property reconstructs `SwipeDetector` whenever `shortSwipeThreshold` / `fastSwipeThreshold` change. ✅
- **Select bias**: Directional bias applies only in touches-channel `clickStart`; button-channel `press(key=select)` dispatches `select` directly without bias. ✅
- **runTvApp**: Calls `WidgetsFlutterBinding.ensureInitialized()` before `init()`; passthrough on non-tvOS. ✅
- **Public API surface**: All exports use explicit `show` clauses; `SwipeDetector` internals not leaked. ✅
- **No Dart key repeat**: `key_repeat.dart` is absent; auto-repeat lives in native. ✅
- **Test isolation**: Every test uses `setUp`/`tearDown` with `debugReset()`; no real platform channels (uses `TestDefaultBinaryMessengerBinding`). ✅

---

## Summary

| Severity  | Count |
|-----------|-------|
| Critical  | 0     |
| Important | 2     |
| Minor     | 5     |

**Recommendation: REQUEST CHANGES** — I-2 (silent media key drop) is a functional regression for a documented feature; I-1 (ConcurrentModificationError) will surface in any app that removes a raw listener from within a callback.
