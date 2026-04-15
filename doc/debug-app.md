# Debugging a Flutter tvOS App

This guide covers how to debug a Flutter tvOS app using VS Code, Flutter DevTools, and platform log streams.

## Debugging in VS Code

`flutter-tvos` uses an **attach** workflow rather than a launch workflow. You start the app from the terminal first, and then VS Code attaches to the running Dart VM.

### 1. Start the app from the terminal

Boot a tvOS simulator (or connect a physical Apple TV), then run:

```bash
flutter-tvos run -d <simulator_id>
```

Replace `<simulator_id>` with the device identifier shown by `flutter-tvos devices`. Once the app is running, the CLI prints a line similar to:

```
A Dart VM Service on Apple TV Simulator is available at:
http://127.0.0.1:56789/xxxxx=/
```

Keep this terminal open. The CLI also writes a `.vscode/launch.json` file into your project automatically (via `vscode_helper.dart`), so no manual configuration is required.

### 2. Attach VS Code to the running app

1. Open your project folder in VS Code.
2. Open the **Run and Debug** panel (`Cmd+Shift+D`).
3. Select the **Dart: Attach to Flutter Process** configuration from the dropdown (it is pre-populated in the generated `.vscode/launch.json`).
4. Click the green **Start Debugging** button (or press `F5`).
5. VS Code connects to the VM Service URL and the debugger becomes active.

You can now set breakpoints, inspect variables, step through code, and use the VS Code debug console — all without restarting the app.

### Hot reload and hot restart

While the app is running:

| Action | Terminal | VS Code |
|---|---|---|
| Hot reload | Press `r` | Click the lightning bolt icon or press `Ctrl+F5` |
| Hot restart | Press `R` | Click the circular arrow icon |
| Quit | Press `q` | Stop the debug session |

Hot reload injects updated Dart code without losing state. Hot restart restarts the Dart VM and resets state.

## Opening DevTools in the Browser

Flutter DevTools provides a suite of performance and inspection tools including the widget inspector, memory profiler, and CPU profiler.

### From the terminal

While `flutter-tvos run` is active, press `d` in the terminal. The CLI opens DevTools in your default browser automatically.

Alternatively, copy the DevTools URL printed in the terminal output:

```
Flutter DevTools, a Flutter debugger and profiler, on Apple TV Simulator is available at:
http://127.0.0.1:9100/?uri=http%3A%2F%2F127.0.0.1%3A56789%2Fxxxxx%3D%2F
```

Paste this URL into any browser to open DevTools manually.

### Profiling mode

For realistic performance measurements, launch in profile mode on a physical Apple TV:

```bash
flutter-tvos run -d <device_id> --profile
```

Profile mode uses AOT compilation and retains the DevTools timeline for performance profiling. Use it to measure frame rendering time and identify jank.

> **Note:** Profile mode requires a physical device. Simulator builds only support debug (JIT) mode.

## Reading Platform Logs

Dart `print()` output and Flutter framework logs appear in the terminal where `flutter-tvos run` is active. For lower-level platform messages — including Metal errors, Xcode runtime warnings, and native plugin output — read the platform log stream directly.

### tvOS Simulator

```bash
xcrun simctl spawn <simulator_id> log stream --predicate 'process == "Runner"'
```

To include more context (subsystem, category):

```bash
xcrun simctl spawn <simulator_id> log stream \
  --predicate 'process == "Runner"' \
  --style compact \
  --level debug
```

### Physical Apple TV

```bash
xcrun devicectl device process launch --console \
  --device <device_id> \
  com.example.myApp
```

`<device_id>` is the UUID shown by `xcrun devicectl list devices`. The `--console` flag attaches stdout/stderr to your terminal session.

## Other Resources

- [Flutter debugging documentation](https://docs.flutter.dev/testing/debugging) — core Dart and Flutter debugging concepts that apply equally to tvOS.
- [Flutter DevTools documentation](https://docs.flutter.dev/tools/devtools/overview) — full reference for all DevTools panels.
- [Dart VM Service protocol](https://github.com/dart-lang/sdk/blob/main/runtime/vm/service/service.md) — low-level VM service API used by the attach workflow.
