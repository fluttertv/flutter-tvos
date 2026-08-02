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

- ### `versions`

  List the Flutter versions this checkout can be switched to, marking the one in
  use. Each supported version is a release line of the flutter-tvos repository,
  tagged `v<flutter>-tvos.<tool>`; the tag carries the CLI, the pinned Flutter
  revision and the matching engine artifacts together.

  ```sh
  # One line per Flutter version, at its newest tool release.
  flutter-tvos versions

  # Every release tag, for when the tool version matters.
  flutter-tvos versions --all
  ```

  The list comes from git tags, refreshed from the remote when it is reachable.
  With no network you still see — and can switch to — everything this checkout
  has fetched before.

- ### `use`

  Switch this checkout to another Flutter version.

  ```sh
  # Newest tool release for that Flutter version.
  flutter-tvos use 3.44.5

  # A specific tool release.
  flutter-tvos use v3.44.5-tvos.1.3.3
  ```

  Switching refuses to run if your checkout has uncommitted changes; pass
  `--force` to discard them and switch anyway. Committed work is safe either
  way — the switch detaches rather than moving your branch.

  The first command after a switch rebuilds the toolchain for the new version,
  which takes a few minutes: it re-checks-out the pinned Flutter SDK, reruns
  `pub get` and recompiles the tool, then downloads that version's engine.

  > **Note:** `use` prints a `git checkout` command as it switches. Keep it if
  > you are moving to a version you have not used before — if that release line
  > fails to build, `flutter-tvos` itself stops working, and that command is how
  > you get back.


- ### `upgrade`

  Upgrade the flutter-tvos toolchain to the **latest released version**. Unlike
  stock `flutter upgrade` (which moves the bundled Flutter SDK toward upstream),
  this updates your flutter-tvos checkout to its newest release tag — which bumps
  the pinned Flutter version and the matching tvOS engine artifacts together —
  and then re-downloads the correct engine.

  ```sh
  # Check whether a newer flutter-tvos release is available (no changes made).
  flutter-tvos upgrade --verify-only

  # Upgrade to the latest released version.
  flutter-tvos upgrade
  ```

  Upgrading refuses to run if your checkout has uncommitted changes; pass
  `--force` to discard them and upgrade anyway.

  > **Note:** the upgrade moves your checkout to the release commit with
  > `git checkout --force --detach`, so branch pointers are left alone and
  > committed work stays reachable. You end up on a detached HEAD, which is the
  > normal state for a released version. After upgrading, `pubspec.lock` will
  > show as modified — that is the expected `pub get` output.

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
