# Getting Started with flutter-tvos

A step-by-step guide to running Flutter apps on Apple TV (tvOS) for the first time.

---

## Prerequisites

Before you begin, make sure the following are installed on your Mac:

- **macOS** (Apple Silicon or Intel)
- **Xcode 15 or later** — install from the Mac App Store, then accept the license:
  ```bash
  sudo xcodebuild -license accept
  ```
- **Xcode Command Line Tools**:
  ```bash
  xcode-select --install
  ```
- **CocoaPods**:
  ```bash
  sudo gem install cocoapods
  ```

> Do not install Flutter separately. The `flutter-tvos` CLI manages its own pinned Flutter SDK and downloads it automatically on first run.

---

## Installation

Clone this repository and add the `bin/` directory to your PATH.

```bash
git clone https://github.com/your-org/flutter_tvos_engine_monorepo.git
cd flutter_tvos_engine_monorepo
```

Add the CLI to your PATH by appending the following line to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export PATH="$HOME/path/to/flutter_tvos_engine_monorepo/flutter-tvos/bin:$PATH"
```

Reload your shell:

```bash
source ~/.zshrc
```

Verify the CLI is on your PATH:

```bash
which flutter-tvos
```

On first run, `flutter-tvos` will automatically clone the pinned Flutter 3.41.4 SDK into `flutter-tvos/flutter/`. This may take a few minutes.

---

## Download Engine Artifacts

The tvOS engine is distributed as pre-built artifacts from GitHub Releases. Download them with:

```bash
flutter-tvos precache
```

This downloads Flutter.framework builds for tvOS device and simulator targets and places them under `flutter-tvos/engine_artifacts/`. You only need to run this once (or after upgrading the CLI).

---

## Verify Your Setup

Run the built-in health check to confirm everything is configured correctly:

```bash
flutter-tvos doctor
```

All items should show a checkmark. Address any warnings before proceeding.

---

## Create Your First App

Generate a new Flutter project:

```bash
flutter-tvos create my_tv_app
cd my_tv_app
```

This creates a standard Flutter project structure. The `flutter-tvos` CLI applies tvOS-specific build settings automatically when you build or run.

---

## List Available Simulators

Before running your app, find the ID of an Apple TV simulator:

```bash
flutter-tvos devices
```

Example output:

```
Apple TV 4K (3rd generation) (Simulator) • <SIMULATOR_ID> • tvos • tvOS 17.0
```

Copy the simulator ID — you will need it in the next step. If no Apple TV simulators appear, open Xcode, go to **Xcode > Open Developer Tool > Simulator**, then add an Apple TV simulator via **File > New Simulator**.

---

## Run on Simulator

Launch your app on the simulator (replace `<SIMULATOR_ID>` with the ID from the previous step):

```bash
flutter-tvos run -d <SIMULATOR_ID>
```

The CLI will build the app, install it on the simulator, and start it with hot reload enabled.

### Hot Reload Keys

While the app is running, use these keys in the terminal:

| Key | Action |
|-----|--------|
| `r` | Hot reload |
| `R` | Hot restart |
| `d` | Open DevTools in browser |
| `q` | Quit |

---

## Build for Release

To build a release IPA for a physical Apple TV device:

```bash
flutter-tvos build tvos --release
```

To build a debug build for the simulator:

```bash
flutter-tvos build tvos --simulator --debug
```

Built artifacts are placed in `build/tvos/`.

---

## Troubleshooting

### CocoaPods not found

If `flutter-tvos doctor` reports CocoaPods is missing:

```bash
sudo gem install cocoapods
```

If `pod` is still not found after installation, your Ruby gems bin directory may not be on PATH. Find it and add it:

```bash
gem environment | grep "EXECUTABLE DIRECTORY"
# Then add that path to your ~/.zshrc
export PATH="/path/to/ruby/gems/bin:$PATH"
```

### Xcode not selected / `xcode-select` errors

Ensure Xcode (not just the Command Line Tools) is selected as the active developer directory:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Confirm with:

```bash
xcode-select -p
# Should output: /Applications/Xcode.app/Contents/Developer
```

### No simulators listed by `flutter-tvos devices`

Apple TV simulators must be created in Xcode before they appear:

1. Open Xcode
2. Go to **Xcode > Open Developer Tool > Simulator** (or press `Cmd+Shift+2`)
3. In Simulator, choose **File > New Simulator**
4. Select **Apple TV** as the device type and choose a tvOS runtime
5. Click **Create**, then re-run `flutter-tvos devices`

If no tvOS runtime is available, download one in Xcode under **Xcode > Settings > Platforms**.

### Build fails after upgrading

Re-run precache to ensure artifacts match the current CLI version:

```bash
flutter-tvos precache
```

Then clean the build directory and try again:

```bash
flutter-tvos clean
flutter-tvos build tvos --simulator --debug
```

---

## Available Commands

| Command | Description |
|---------|-------------|
| `flutter-tvos create <name>` | Create a new Flutter project |
| `flutter-tvos devices` | List connected devices and simulators |
| `flutter-tvos run -d <id>` | Build and run on a device or simulator |
| `flutter-tvos build tvos` | Build the tvOS app |
| `flutter-tvos doctor` | Check environment setup |
| `flutter-tvos precache` | Download engine artifacts |
| `flutter-tvos clean` | Delete build artifacts |
| `flutter-tvos test` | Run Dart unit tests |
| `flutter-tvos attach` | Attach to a running app |
| `flutter-tvos drive` | Run integration tests |
