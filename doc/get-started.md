# Getting started

## Set up the environment

### Prerequisites

- **macOS** — flutter-tvos is macOS-only. Windows and Linux are not supported.
- **Xcode 15 or later** — Required for tvOS SDK and simulator support. Install from the Mac App Store, then accept the license:

  ```sh
  sudo xcodebuild -license accept
  ```

- **CocoaPods** — Required for plugin resolution:

  ```sh
  sudo gem install cocoapods
  ```

### Install flutter-tvos

1. Clone the repository:

   ```sh
   git clone https://github.com/fluttertv/flutter-tvos.git
   cd flutter-tvos
   ```

2. Add the `bin/` directory to your `PATH`. For example, in `~/.zshrc`:

   ```sh
   export PATH="$HOME/path/to/flutter-tvos/bin:$PATH"
   ```

   Then reload your shell:

   ```sh
   source ~/.zshrc
   ```

3. Download the pre-built engine artifacts:

   ```sh
   flutter-tvos precache
   ```

### Verify the setup

Run `flutter-tvos doctor` to check that all required components are in place. Only the `Flutter` and `Xcode` entries are required; Android-related warnings can be ignored.

```
$ flutter-tvos doctor
Doctor summary (to see all details, run flutter-tvos doctor -v):
[✓] Flutter (Channel unknown, 3.41.4, on macOS, locale en-US)
[✓] Xcode - develop for iOS and tvOS (Xcode 15.4)
[✓] Connected device (1 available)
```

### Set up a tvOS simulator

flutter-tvos does not include an emulator manager. Simulators are created and managed in Xcode.

1. Open Xcode.
2. Go to **Window > Devices and Simulators**.
3. Click the **Simulators** tab, then the **+** button.
4. Choose **tvOS** as the platform, select a device type (e.g. Apple TV 4K), and pick a tvOS runtime (13.0 or later).

Once created, the simulator will appear in the `flutter-tvos devices` output.

Note: No code signing is required for simulator builds. For physical Apple TV device builds, a development team must be configured in Xcode (`DEVELOPMENT_TEAM`).

## Test drive

Reference: [Flutter Docs: Test drive](https://flutter.dev/docs/get-started/test-drive?tab=terminal)

### Create the app

Use the `create` command to create a new project:

```sh
flutter-tvos create my_app
cd my_app
```

The command creates a Flutter project directory called `my_app` that contains a simple demo app using [Material Components](https://material.io/guidelines). Open the directory in your editor of choice to explore the source code (`lib/main.dart`).

### List available devices

Before running, confirm that your simulator is visible:

```
$ flutter-tvos devices
Found 1 connected device:
  Apple TV 4K (3rd generation) (tvos) • <device-id> • apple-tv • tvOS 17.0
```

Simulators are discovered automatically via `xcrun simctl`. If no devices appear, make sure you have created a tvOS simulator in Xcode and that it is booted.

### Run the app

Run the app on a simulator with its device ID:

```sh
flutter-tvos run -d <device_id>
```

After the build completes, the starter app will launch on the simulator.

## Try hot reload

Flutter's ability to apply code changes to a live running app without restarting or losing state is called [Stateful Hot Reload](https://flutter.dev/docs/development/tools/hot-reload). After launching an app with `flutter-tvos run`, the following help message appears in the terminal:

```
Syncing files to device Apple TV 4K...                             612ms

Flutter run key commands.
r Hot reload.
R Hot restart.
h List all available interactive commands.
d Open Flutter DevTools.
q Quit (terminate the application on the device).

A Dart VM Service on Apple TV 4K is available at: http://127.0.0.1:56342/abc123=/
```

To try hot reload:

1. Open `lib/main.dart` in your editor.
2. Make a visible change — for example, change the string in the `Text` widget.
3. Save the file, then type `r` in the terminal.

```
Performing hot reload...
Reloaded 1 of 448 libraries in 834ms.
```

The change appears on the simulator immediately, without losing the current app state.

Type `R` to perform a full hot restart, or `q` to quit the app.
