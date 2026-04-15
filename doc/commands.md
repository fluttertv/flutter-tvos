# Supported commands

The following commands from the [Flutter CLI](https://flutter.dev/docs/reference/flutter-cli) are supported by flutter-tvos.

## Global options

- ### `-d`, `--device-id`

  Specify the target device ID. If not specified, the tool lists all connected devices and prompts for a selection.

  ```sh
  flutter-tvos -d <device_id> [command]
  ```

- ### `-v`, `--verbose`

  Show verbose output.

  ```sh
  flutter-tvos -v [command]
  ```

## Commands and examples

- ### `attach`

  Attach to a running app.

  ```sh
  flutter-tvos attach --debug-url http://127.0.0.1:56342/abc123=/
  ```

  The `--debug-url` value must be provided. The VM Service URI is printed to the terminal when an app is launched in debug or profile mode via `flutter-tvos run`. It is also available in the device console logs.

- ### `build tvos`

  Build the tvOS app bundle. The output is an `.app` directory suitable for installation on a simulator or a signed `.ipa` for device distribution.

  ```sh
  # Build for the tvOS simulator in debug mode (JIT, fastest iteration).
  flutter-tvos build tvos --simulator --debug

  # Build for a physical Apple TV in release mode (AOT, optimised).
  flutter-tvos build tvos --release

  # Build for a physical Apple TV in profile mode (AOT, with profiling enabled).
  flutter-tvos build tvos --profile
  ```

  Note: Simulator builds always use debug (JIT) mode. Device builds use AOT compilation (`--release` or `--profile`) and require Xcode code signing to be configured with a valid development team.

- ### `clean`

  Remove the current project's build artifacts and intermediate files.

  ```sh
  flutter-tvos clean
  ```

- ### `create`

  Create a new Flutter project.

  ```sh
  # Create a new app project in the "my_app" directory.
  flutter-tvos create my_app

  # Create a new plugin project.
  flutter-tvos create --template=plugin my_plugin
  ```

- ### `devices`

  List all available tvOS simulators (via `xcrun simctl`) and connected physical Apple TVs (via `xcrun devicectl`).

  ```sh
  flutter-tvos devices
  ```

  Example output:

  ```
  Found 1 connected device:
    Apple TV 4K (3rd generation) (tvos) • <device-id> • apple-tv • tvOS 17.0
  ```

  Note: flutter-tvos does not provide an emulator manager. Simulators are created in Xcode under **Window > Devices and Simulators**.

- ### `doctor`

  Show information about the installed tooling. Use `-v` for full details.

  ```sh
  flutter-tvos doctor -v
  ```

- ### `drive`

  Run integration tests for the project on a connected device. For detailed usage, see [`integration_test`](https://github.com/flutter/flutter/tree/master/packages/integration_test).

  ```sh
  # Run an integration test on a tvOS simulator.
  flutter-tvos drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/foo_test.dart \
    -d <device_id>
  ```

- ### `precache`

  Download and cache the pre-built tvOS engine artifacts (Flutter.framework for each build variant).

  ```sh
  flutter-tvos precache
  ```

  This must be run once after installation, and again whenever the engine artifacts are updated.

- ### `run`

  Build the current project and run it on a connected device or simulator. For more information on build modes, see [Flutter Docs: Flutter's build modes](https://flutter.dev/docs/testing/build-modes).

  ```sh
  # Build and run in debug mode on a simulator (hot reload available).
  flutter-tvos run -d <device_id>

  # Build and run in release mode.
  flutter-tvos run -d <device_id> --release

  # Build and run in profile mode.
  flutter-tvos run -d <device_id> --profile
  ```

  While running in debug mode, the following key commands are available in the terminal:

  | Key | Action |
  |-----|--------|
  | `r` | Hot reload |
  | `R` | Hot restart |
  | `h` | List all available interactive commands |
  | `d` | Open Flutter DevTools |
  | `q` | Quit (terminate the application on the device) |

- ### `test`

  Run Flutter unit tests for the current project. See [Flutter Docs: Testing Flutter apps](https://flutter.dev/docs/testing) for details.

  ```sh
  # Run all tests in the "test" directory.
  flutter-tvos test

  # Run a specific test file.
  flutter-tvos test test/my_widget_test.dart
  ```

  For integration tests that must run on device, use the [`drive`](#drive) command instead.

## Not supported

The following commands from the Flutter CLI are not supported by flutter-tvos.

- `assemble`
- `bash-completion`
- `channel`
- `custom-devices`
- `downgrade`
- `emulators` — tvOS simulators are managed through Xcode, not a Flutter emulator manager.
- `gen-l10n`
- `install`
- `logs`
- `screenshot`
- `symbolize`
- `upgrade`
