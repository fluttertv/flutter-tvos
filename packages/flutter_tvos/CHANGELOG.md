## 1.1.0

### Remote Control (RCU)

- `runTvApp` / `TvRemoteController.init()` — Siri Remote wired to
  Flutter's keyboard/focus pipeline on tvOS; passthrough on iOS/Android.
- `TvRemoteConfig` — runtime-tunable thresholds (swipe, D-pad dead
  zone, auto-repeat delays); shipped to native via method channel.
- `TvRemoteController.addRawListener` — raw touchpad events for
  custom swipe zones (video scrubbers etc.).
- Lock-screen media commands (`MPRemoteCommandCenter`) forwarded to
  `flutter/keyevent` so widgets reacting to
  `LogicalKeyboardKey.mediaPlay/Pause/Stop/...` light up for free.

### Round-3 review follow-ups (Flutter Android / flutter-tizen parity)

- **Select → `LogicalKeyboardKey.enter`** (was `select`). Flutter's
  default `ActivateIntent` binds to `enter`, so standard buttons and
  list items now activate on Select press without any app-level
  shortcut registration.
- **Menu → `Navigator.maybePop`** via `flutter/navigation popRoute`
  (was a dead `press(key=menu)` method call). Mirrors Android's
  physical back-button behavior.
- **Play/Pause → `LogicalKeyboardKey.mediaPlayPause`** (was a dead
  `press(key=playPause)` method call). Via Android keymap (Flutter's
  macOS map has no media entries).
- **Touches channel no longer spams** "message discarded" warnings
  when no `addRawListener` is registered — engine installs a no-op
  drain, transparently replaced by Dart handler on attach.

## 1.0.0

- Initial release
- Platform detection: `isTvOS`, `isSimulator`
- Device info: `tvOSVersion`, `deviceModel`, `machineId`
- Capability queries: `supports4K`, `supportsHDR`, `supportsMultiUser`
- Display info: `displayResolution`
- Result caching with `clearCache()` support
