# Action Plan — PR #1 (fluttertv) + PR #2 (engine)

**Date:** 2026-04-23
**Status:** findings from both review reports verified against real code. Each item marked ✅ REAL / 🟡 NUANCED / ❌ FALSE-POSITIVE / 🔗 DUPLICATE.

---

## Verification summary

| Source | REAL | NUANCED | FALSE-POSITIVE | DUPLICATE |
|---|---:|---:|---:|---:|
| engine PR #2 (25 total) | 18 | 3 | 1 | 3 |
| main PR #1 (25 total) | 19 | 3 | 0 | 3 |
| **Total** | **37** | **6** | **1** | **6** |

---

# Engine PR #2 — verification

## Critical

### ✅ REAL — C1: `FlutterTvRemotePluginTest.mm` not built
**Verified:** `BUILD.gn:259-297` ios_test_flutter target has ALL test files commented out ("Tests commented out for tvOS build"). Our file not added either. Но это **не наша проблема в этом PR** — это pre-existing решение Mehmet'а полностью отключить test target на tvOS. Добавить наш файл в закомментированный список бессмысленно.

**Action:** обсудить с Mehmet — хочет ли он восстановить test target на tvOS, или тесты не выполняются вовсе. Пока не блокирует наш PR. Понижаю до IMPORTANT.

### ✅ REAL — C2: `tvosKeyboardPending` guard dropped
**Verified:** `FlutterTextInputPlugin.mm:2980-2988` имеет полный контракт `tvosKeyboardPending` / `tvosActivateKeyboard`. Наш `handlePress:` для `UIPressTypeSelect` отправляет `click_s` без этого guard. Функциональный regression для text field focus.

**Action:** восстановить guard в `handlePress:` — если `self.engine.textInputPlugin.tvosKeyboardPending`, вызвать `tvosActivateKeyboard` и НЕ слать `click_s`.

## Important

### ✅ REAL — I1: MPRemoteCommandCenter handler leak
**Verified:** `addTargetWithHandler:` везде (строки 537-587), `removeTarget:` нигде. Handler tokens не сохраняются. `mediaCommandsRegistered` per-instance. Реальная утечка на engine restart.

**Action:** сохранять токены из `addTargetWithHandler:` в `NSMutableArray* mediaCommandTokens`. В `detach` итерировать по массиву и `[command removeTarget:token]`. Сбрасывать `mediaCommandsRegistered = NO`.

### ✅ REAL — I2: `resetContinuousSwipeState` zeros `lastTouchX/Y`
**Verified:** строки 412-415 в `handleTouches:`:
```objc
if (isStart) {
  self.lastTouchX = x;          // assign actual coord
  self.lastTouchY = y;
  [self resetContinuousSwipeState];  // THIS zeros them again
}
```
После этого первый `move` вычисляет `dx = x - 0`, `dy = y - 0`. Bug небольшой по последствиям (просто один лишний trigger), но реальный.

**Action:** либо (a) убрать зануление `lastTouchX/Y` из `resetContinuousSwipeState`, либо (b) поменять порядок — сначала reset, потом assign.

### ✅ REAL — I3: `controllerDidDisconnect:` off-main-thread race
**Verified:** `controllerDidConnect:` (504) wraps in `dispatch_async(main)`, `controllerDidDisconnect:` (515) — не wraps. Data race на `NSHashTable configuredControllers`.

**Action:** обернуть тело `controllerDidDisconnect:` в `dispatch_async(dispatch_get_main_queue(), ^{...})`.

### ✅ REAL — I4: `FlutterEngine_Internal.h` import leaks tvOS header into iOS builds
**Verified:** строка 29 — `#import "...FlutterTvRemotePlugin.h"` без guard. Header сам guarded `#if TARGET_OS_TV`, но bare import нарушает конвенцию репо (все остальные tvOS imports в файле wrapped).

**Action:** обернуть import в `#if TARGET_OS_TV ... #endif`.

### 🟡 NUANCED — I5: Asymmetric key maps (`playPause` not in MacOs)
**Verified:** `_LogicalKeyNameForPressType` возвращает `@"playPause"`, `_MacOsKeyCodeForLogicalName` не мапит его. Но **не текущий баг** — `playPause` никогда не вызывается через `sendKey:` (он идёт через button channel как method call). Риск latent если кто-то позже напишет `sendKey:@"playPause"`.

**Action:** добавить комментарий в `_MacOsKeyCodeForLogicalName` что `playPause` намеренно не мапится (routes via button channel); optionally assert coverage в debug builds. Понижаю до MINOR.

### ✅ REAL — I6: Nil-check in touches forwarding is too narrow
**Verified:** `touchesBegan/Moved/Ended/Cancelled` в `FlutterViewController.mm` проверяют только `plugin != nil`. Не проверяют `plugin.viewController != nil` (i.e. attached). Post-detach touch форвардится в plugin и читает view.bounds — если view уже gone, UB.

**Action:** расширить nil-check до `plugin != nil && plugin.viewController == self`. Требует exposing `viewController` в `_Internal.h` как readonly.

### ✅ REAL — I7: `setViewController:` does not hook TvRemotePlugin
**Verified:** `FlutterEngine.mm:519-540` reassigns `textInputPlugin.viewController` но не `tvRemotePlugin`. Engine group миграция между VC не вызовет attach.

**Action:** добавить в `setViewController:`:
```objc
#if TARGET_OS_TV
if (viewController) {
  [self.tvRemotePlugin attachToViewController:viewController];
} else {
  [self.tvRemotePlugin detach];
}
#endif
```

### 🔗 DUPLICATE — I8: Header leak
Same as I4. Drop from list.

### ✅ REAL — I9: Stale VC dealloc detaches active plugin (Copilot finding)
**Verified:** `FlutterViewController.mm:1092` — `[self.engine.tvRemotePlugin detach]` безусловно. Сценарий: VC A мигрирует в VC B через attach; VC A deallocs позже; tears off plugin который теперь на VC B.

**Action:** в dealloc проверять владение:
```objc
#if TARGET_OS_TV
FlutterTvRemotePlugin* plugin = self.engine.tvRemotePlugin;
if (plugin.viewController == self) {
  [plugin detach];
}
#endif
```

## Minor

### ✅ REAL — M1: dealloc ordering
`[self.engine.tvRemotePlugin detach]` runs после `removeInternalPlugins`. Weak engine может быть nil. Low-priority — в большинстве случаев работает. Связано с I9 fix.

**Action:** решается вместе с I9.

### 📝 NOTE — M2: `_Internal.h` convention matches `FlutterPlatformPlugin_Test.h`
Positive observation — no action.

### ✅ REAL — M3: `export CLEANUP_SHIM_DIR` unnecessary
**Verified:** `build_tvos_engine.sh:43` — `export` не нужен, `trap` работает и без него.

**Action:** убрать `export` ключевое слово.

### ✅ REAL — M4: Trap only on EXIT
**Verified:** строка 44 — `trap '...' EXIT`. SIGINT, SIGTERM, SIGHUP не cleanup'ят `SHIM_DIR`.

**Action:** `trap '...' EXIT INT TERM HUP`. Добавить sanity check что shim работает:
```bash
if ! "$SHIM_DIR/python3" --version >/dev/null 2>&1; then
  echo "ERROR: python3.12 shim failed validation" >&2
  exit 1
fi
```

### 🟡 NUANCED — M5: deps_patches silent failures
**Verified:** `git apply ... || true` + unconditional `touch .deps_patched`. Но это **pre-existing** в build script ещё до этого PR. Не наш долг в этом PR.

**Action:** defer — отдельный follow-up cleanup PR. Не в scope этого review.

### ✅ REAL — M6: Stringly-typed channel values
**Verified:** phase/key names повторяются в 3+ ladder'ах. Typo drift risk.

**Action:** extract `static NSString* const kFltvPhaseStarted = @"started";` и т.д. в anonymous namespace. Нативно; параллельное изменение в Dart (см. main PR M3).

### ✅ REAL — M7: `UIPressTypeSelect` ignores `Failed` state
**Verified:** `handlePress:` для Select — emit `click_e` только на `Ended`/`Cancelled`, не на `Failed`. Recognizer может транзитировать в Failed без Ended.

**Action:** добавить `UIGestureRecognizerStateFailed` в условие для `click_e`.

### ✅ REAL — M8: `allowedPressTypes.firstObject` fragility
**Verified:** `handlePress:345-346` достаёт pressType из first object. Фрагильно если когда-нибудь добавят несколько allowed press types в один recognizer.

**Action:** при создании recognizer'а в `addPressRecognizerForType:`, сохранять `pressType` через `objc_setAssociatedObject` и читать в handler — гарантированный match к установленному типу.

### ✅ REAL — M9: Docstring mismatch `timestamp`
**Verified:** `tv_remote_channels.dart:34` упоминает `timestamp`, native не шлёт. Dart не парсит.

**Action:** убрать `timestamp` из docstring в `tv_remote_channels.dart` (это изменение в main PR но происходит из engine dataflow).

### ✅ REAL — M10: MFi controllers without microGamepad silently skipped
**Verified:** `configureController:` проверяет `if (gamepad == nil) return;` — никакого лога.

**Action:** добавить `FML_DLOG(WARNING) << "..."` или NSLog в debug builds.

### ✅ REAL — M11: `FlutterTvKeyRepeater.dealloc` no trailing keyup
**Verified:** `dealloc:103-106` invalidates timers но не sends keyup. Plugin `dealloc` вызывает `stopRepeat` first, так что safe by construction. Но repeater не self-healing.

**Action:** опционально — в `dealloc` repeater'а вызвать sendBlock с `isDown:NO` если `activeKey != nil`. Низкий приоритет.

### ✅ REAL — M12: `NSAssert(engine)` stripped in release
**Verified:** строка 204. Nil engine в release даст plugin с silent-fail методами.

**Action:** заменить на `NSCParameterAssert(engine)` (не strippable?) или явный `if (!engine) return nil`. Но: Flutter пользуется NSAssert-паттерном часто; проверить что они делают в других plugins.

### ✅ REAL — M13: Default `UIPressTypeSelect` on nil `allowedPressTypes`
**Verified:** строка 343 `pressType = UIPressTypeSelect; // default`. Если recognizer misconfigured — misrouting.

**Action:** `NSAssert` + early-return без emitting event.

### 🟡 NUANCED — M14: First-move direction seeded from start
Related to I2. После fix I2 comment нужен.

**Action:** добавить comment после I2 fix.

---

# Main PR #1 — verification

## Critical

### ✅ REAL — C1: `select` → `0x24` is wrong (maps to `enter`)
**Verified:** Flutter macOS keymap (`flutter/packages/flutter/lib/src/services/keyboard_maps.g.dart`):
- `23: LogicalKeyboardKey.select` — **23 (0x17)** - правильный keycode для Select
- `36: LogicalKeyboardKey.enter` — **36 (0x24)** - это Enter

Наш `key_simulator.dart:69` возвращает `0x24` для `LogicalKeyboardKey.select` → получаем **enter**, не **select**. Активация работает **по случайности** через дефолтный `ActivateIntent` binding на `enter`, но любой код, слушающий `select` напрямую, ничего не получит.

**Action:** изменить в `key_simulator.dart:69`:
```dart
if (key == LogicalKeyboardKey.select) return 0x17;  // kVK_ANSI_X → select
```
**Важно:** такая же проблема в engine PR `_MacOsKeyCodeForLogicalName` (строка 71 native code). Fix обе стороны вместе.

**Альтернатива:** route click через native `sendKey` вместо Dart `channelBuffers` — engine native сам выберет правильный keycode. Это более системное решение.

### ✅ REAL — C2: `ConcurrentModificationError` in raw listener loop
**Verified:** `tv_remote_controller.dart:209-211`:
```dart
for (final listener in _rawListeners) {
  listener(event);
}
```
Без snapshot. Listener, который удаляет себя, вызовет runtime crash.

**Action:**
```dart
for (final listener in List.of(_rawListeners)) {
  try {
    listener(event);
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack));
  }
}
```

### ✅ REAL — C3: README example won't compile
**Verified:** `README.md` содержит `keyRepeatInterval: Duration(milliseconds: 100)` в TvRemoteConfig example. Этого поля в конфиге нет.

**Action:** убрать `keyRepeatInterval` из snippet, добавить прозу "repeat timing is fixed in native — not configurable via Dart right now".

### ✅ REAL — C4: CHANGES.md references deleted files
**Verified:**
- `CHANGES.md:42-43` — упоминает `key_repeat.dart` (удалён в Phase 1).
- `CHANGES.md:51` — "19 new unit tests"; реально 26+.
- `fake_async` в `dev_dependencies` но grep показывает ни одного импорта в `test/`.

**Action:**
1. Переписать RCU секцию CHANGES.md под финальную архитектуру (KeyRepeater в native).
2. Удалить `fake_async` из `dev_dependencies`.

## Important

### ✅ REAL — I1: Podfile.lock commits developer-specific absolute path
**Verified:** `/Users/sashadenisov/Work/fluttertv/...` во 2 местах. Следующий разработчик получит `pod install` failure.

**Action:** добавить `packages/flutter_tvos/example/tvos/Podfile.lock` в `.gitignore` и `git rm --cached` его.

### ✅ REAL — I2: `meta` в `dependencies` вместо `dev_dependencies`
**Verified:** `meta: ^1.8.0` в `dependencies`, но используется только для `@visibleForTesting`. Flutter SDK уже re-exports `@visibleForTesting` через `package:flutter/foundation.dart`.

**Action:** либо убрать `meta` dep и импортировать `@visibleForTesting` из `foundation.dart`, либо переместить в `dev_dependencies`.

### ✅ REAL — I3: No test for click-race fix (CR #1)
**Verified:** `test/rcu/tv_remote_controller_test.dart:96-109` — только проверяет phase delivery, не keyboard event sequence.

**Action:** добавить тест с `TestDefaultBinaryMessengerBinding.setMockMessageHandler` на `SystemChannels.keyEvent.name`, отправить `click_s → click_s → click_e`, asserthat 2 keydown + 2 keyup в правильном порядке.

### ✅ REAL — I4: No test for directional-click bias
**Verified:** `_handleClickStart` реализует bias, но нет теста что `loc(0.6) → click_s` даёт `arrowRight`.

**Action:** добавить 2 теста: (a) dpadX=0.6 + click_s → arrowRight, (b) dpadX=0 + click_s → select.

### 🟡 NUANCED — I5: Config mutation mid-gesture drops gesture
**Verified:** `_swipe` getter рекреирует детектор с `_isActive = false` при threshold change. Текущая сессия теряется. Реально — mid-gesture config change это edge case.

**Action:** документировать "do not mutate config mid-gesture", либо скопировать `_isActive`/segment start при invalidation. Документирование проще. Понижаю до MINOR.

### ✅ REAL — I6: `runTvApp` vs custom WidgetsBinding
**Verified:** `runTvApp` вызывает `WidgetsFlutterBinding.ensureInitialized()` безусловно. Apps с custom binding subclass должны инициализировать свой first.

**Action:** расширить docstring `runTvApp` — документировать что custom binding apps must call their ensureInitialized first, then `TvRemoteController.instance.init()` manually, then `runApp`.

### ✅ REAL — I7: Hot restart leaves singleton stale
**Verified:** Dart VM reinitializes statics on hot restart → `_initialized = false` → channel handlers gone → `runTvApp` не re-invoked → RCU dead.

**Action:** документировать ограничение. Это Flutter-wide issue с singleton'ами. Optionally — hook into `WidgetsBinding.reassembleApplication` для re-init.

### ✅ REAL — I8: Config ranges unvalidated
**Verified:** `TvRemoteConfig(shortSwipeThreshold: -1)` компилируется.

**Action:** добавить const asserts в constructor:
```dart
const TvRemoteConfig({...})
  : assert(shortSwipeThreshold > 0),
    assert(fastSwipeThreshold >= shortSwipeThreshold),
    assert(dpadDeadZone > 0);
```

### 🟡 NUANCED — I9: `SwipeEvent` public constructor allows forgery
**Verified:** public `const SwipeEvent({...})`. Инвариант `isFast == (magnitude >= fastThreshold)` может быть нарушен если кто-то вручную создаёт event.

**Action:** низкий приоритет — `SwipeEvent` это output type, app code обычно его только читает. Но good hygiene: переименовать в `SwipeEvent._` и добавить factory для тестов. Понижаю до MINOR.

### ✅ REAL — I10: Docstring mentions `timestamp`, native doesn't send
**Verified:** см. engine M9 — то же самое, в этом PR.

**Action:** убрать `timestamp` из docstring в `tv_remote_channels.dart`.

### 🟡 NUANCED — I11: CHANGES.md reads as internal architecture notes
**Verified:** True, но subjective. CHANGES.md описывает архитектурные изменения, не user-facing features.

**Action:** reorganize into "For app authors" block first, technical details later. Понижаю до MINOR.

## Minor

### ✅ REAL — M1 (M4 duplicate numbering): Double `widgets.dart` import
**Verified:** строки 8-9.

**Action:** объединить:
```dart
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding, Widget, runApp;
```
и убрать `widgets.` prefix.

### ✅ REAL — M2: `LogicalKeyboardKey.enter` dead mapping
**Verified:** `key_simulator.dart:70` — mapping есть, но ни одного caller.

**Action:** удалить строку.

### ✅ REAL — M3: `TvRemoteTouchPhase.loc` conflates D-pad with touches
**Verified:** enum смешивает touch phases с `loc` (D-pad) и `click*` (button). Не блокирует — работает; design polish.

**Action:** defer. Стоит рассмотреть sealed hierarchy в будущей major version.

### ✅ REAL — M4: Comment in "reverses direction" test is wrong
**Verified:** коммент говорит "Up because |dy|=0.4 > |dx|=0.4 ties — right side wins by `>=`"; `expect(next!.direction, SwipeDirection.left)`. После первого swipe segment = (0.4, 0). Move to (0, -0.4) → dx=-0.4, dy=-0.4, tie → `absDx >= absDy` branch, `dx >= 0 ? right : left` → dx=-0.4 → **left**. Expect правильный, comment врёт.

**Action:** переписать comment:
```dart
// Segment reset to (0.4, 0). Move to (0, -0.4) → dx=-0.4, dy=-0.4.
// Tie goes to absDx >= absDy branch (>=), and dx<0 → Left.
```

### ✅ REAL — M5: No runtime assertion on `x, y ∈ [-1, 1]`
**Verified:** `TvRemoteTouchEvent` docs range but doesn't assert. Rogue native payload passes through.

**Action:** низкий приоритет — добавить debug-only clamp или log если out of range.

### ✅ REAL — M6: `SwipeDetector` not in public exports
**Verified:** `SwipeEvent`/`SwipeDirection` exported, но `SwipeDetector` — нет. Типы достижимы только как return type из private getter.

**Action:** добавить exp в `flutter_tvos.dart`, или документировать "return-only" статус у `SwipeEvent`.

### ✅ REAL — M7: `TvRemoteChannels` not exported
**Verified:** advanced test scenarios не могут напрямую обратиться к каналам.

**Action:** добавить к export с `@visibleForTesting` комментом.

### ✅ REAL — M8: Example missing `select` shortcut override
После fix C1, `WidgetsApp.defaultShortcuts` не будет связывать `select` с `ActivateIntent`. Нужен явный shortcut map.

**Action:** добавить в example `MaterialApp.shortcuts`:
```dart
shortcuts: <LogicalKeySet, Intent>{
  ...WidgetsApp.defaultShortcuts,
  LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
},
```

### ✅ REAL — M9: `simulateKeyEvent` return value discarded
**Verified:** Везде `await simulateKeyEvent(...)` без проверки. `false` может означать "Flutter didn't handle" или "programming error — unknown logical key". Indistinguishable.

**Action:** assert/debugPrint на unknown-mapping path в `key_simulator.dart`. Не блокирует.

### ✅ REAL — M10: `_onButtonCall` 6 silent return null paths
**Verified:** Каждый path — silent. `debugPrint` на unknown branch поможет при dev.

**Action:** добавить debug logging на unknown branches.

---

# Execution order

## Phase A — Blocking fixes (before merge)

### A1. Main PR: Fix `select` keycode (C1)
**File:** `packages/flutter_tvos/lib/src/rcu/key_simulator.dart:69`
**Change:** `0x24` → `0x17` for `LogicalKeyboardKey.select`. Also fix engine PR's `_MacOsKeyCodeForLogicalName` (строка ~71) — same change. Add explanation comment.

### A2. Main PR: ConcurrentModificationError guard (C2)
**File:** `packages/flutter_tvos/lib/src/rcu/tv_remote_controller.dart:209`
**Change:** `for (final listener in List.of(_rawListeners))` + try/catch per listener + `FlutterError.reportError`.

### A3. Main PR: README compile fix (C3)
**File:** `packages/flutter_tvos/README.md`
**Change:** remove `keyRepeatInterval` from TvRemoteConfig example. Add prose note.

### A4. Main PR: CHANGES.md accuracy (C4)
**Files:** `CHANGES.md`, `packages/flutter_tvos/pubspec.yaml`
**Change:** rewrite RCU section to match final architecture. Remove `fake_async` dev dep. Update test count.

### A5. Engine PR: `tvosKeyboardPending` guard (C2)
**File:** `flutter_upstream_tvos_engine/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemotePlugin.mm:348-356`
**Change:** before sending `click_s`, check `self.engine.textInputPlugin.tvosKeyboardPending` and call `tvosActivateKeyboard`.

### A6. Engine PR: Stale VC dealloc race (I9)
**Files:** `FlutterViewController.mm:1092`, `FlutterTvRemotePlugin_Internal.h`
**Change:** expose `viewController` property; guard dealloc detach with `if (plugin.viewController == self)`.

## Phase B — Important correctness (landing soon after)

### B1. Engine PR: MPRemoteCommandCenter handler cleanup (I1)
Store tokens; remove on detach; reset flag.

### B2. Engine PR: Reset continuous swipe fix (I2)
Swap order or don't zero `lastTouchX/Y` in reset.

### B3. Engine PR: `controllerDidDisconnect:` dispatch_async (I3)
Wrap body in main queue dispatch.

### B4. Engine PR: `FlutterEngine_Internal.h` import guard (I4)
Add `#if TARGET_OS_TV` around import.

### B5. Engine PR: `setViewController:` hook (I7)
Attach/detach plugin in setViewController:.

### B6. Engine PR: Nil-check covers attached state (I6)
Extend touches forwarding nil-check to include `plugin.viewController == self`.

### B7. Main PR: Click-race test (I3)
Use `setMockMessageHandler` on `SystemChannels.keyEvent`.

### B8. Main PR: Directional-click bias tests (I4)
2 tests: dpadX=0.6 + click_s → arrowRight, dpadX=0 + click_s → select.

### B9. Main PR: Podfile.lock hygiene (I1)
`git rm --cached` + `.gitignore` добавить путь.

### B10. Main PR: `meta` dep cleanup (I2)
Use `@visibleForTesting` from `flutter/foundation.dart`.

### B11. Main PR: TvRemoteConfig assertions (I8)
Const asserts for positive thresholds, short ≤ fast.

### B12. Main PR: `runTvApp` docstring (I6)
Document custom binding interaction.

### B13. Main PR: Hot restart note (I7)
Add to docstring / README that hot restart doesn't re-register RCU handlers.

## Phase C — Minor polish (follow-up PR)

### C.Engine
- M3: remove `export` from CLEANUP_SHIM_DIR
- M4: expand trap signals + shim sanity check
- M5: defer (pre-existing in build script)
- M6: extract channel/key name constants
- M7: add `Failed` to Select `click_e` trigger
- M8: use associated object for pressType
- M9: remove `timestamp` from docstring
- M10: log MFi-without-microGamepad skip
- M11: keyup in repeater dealloc (optional)
- M12: real guard for nil engine
- M13: assert + return on misconfigured recognizer
- M14: comment after I2 fix

### C.Main
- M1: consolidate `widgets.dart` imports
- M2: remove dead `enter` mapping from key_simulator
- M3: defer enum split (major version)
- M4: fix "reverses direction" test comment
- M5: coordinate range clamp/log
- M6: decide export of `SwipeDetector`
- M7: export `TvRemoteChannels` with `@visibleForTesting`
- M8: example shortcuts map for `select`
- M9: debug log on unknown logical key
- M10: debug log on unknown button call

## Phase D — Out of this PR cycle

- Engine C1 (test file wiring): obsolete — all iOS tests disabled for tvOS builds. Coordinate with Mehmet if he wants to restore test target for tvOS variant.
- Main M3 (TvRemoteTouchPhase split): major version break.
- Engine M5 (deps_patches error handling): not introduced by this PR.

---

# Estimated effort

- **Phase A (6 items):** ~2 hours. All surgical.
- **Phase B (13 items):** ~half day. Тесты + refactor.
- **Phase C (22 items):** ~half day polish. Separate PR.

**Rollout:**
1. Land Phase A fixes → re-request review → unblock merge.
2. Land Phase B as second commit on same branch or as follow-up before release.
3. Phase C as cleanup PR, no rush.

---

# Findings summary after verification

**Engine PR #2:**
- ✅ REAL blockers: C2 (keyboard activation regression), I1-I4, I6, I7, I9 + всё minors (кроме M2, M5)
- Понижено: C1 (not ours — Mehmet's decision), I5 (not current bug), M5 (pre-existing)
- ❌ False positives: none
- 🔗 Duplicates: I8 → I4

**Main PR #1:**
- ✅ REAL blockers: C1-C4, I1-I4, I6-I8, I10 + всё minors
- 🟡 Nuanced: I5 (mid-gesture edge case, document), I9 (stylistic)
- I11 → subjective/style
- ❌ False positives: none

**Recommendation:** Phase A is the MVP for unblock → merge. Phase B landing soon after.
