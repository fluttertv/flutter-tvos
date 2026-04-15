# flutter-tvos

A Flutter toolchain for building and running Flutter apps on **Apple TV (tvOS)**.

`flutter-tvos` is a drop-in CLI companion to the Flutter SDK — same commands, same hot reload, same DevTools — targeting tvOS instead of iOS.

> **macOS only.** Xcode is required.

---

## Features

- `build`, `run`, `create`, `clean`, `devices`, `doctor`, `attach`, `drive`, `test`, `precache`
- Hot reload and hot restart on tvOS Simulator
- Native Swift plugin support via CocoaPods
- Physical Apple TV device deployment
- Plugin scaffolding (`flutter-tvos create --template=plugin`)
- Targets **Flutter 3.41.4**

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| macOS | Required — Xcode is macOS-only |
| Xcode 15+ | Install from the App Store |
| tvOS SDK | Included with Xcode |
| CocoaPods | `sudo gem install cocoapods` |
| Flutter 3.41.4 | Auto-managed — do not install separately |

---

## Installation

**1. Clone the repository**

```bash
git clone https://github.com/fluttertv/flutter-tvos.git
cd flutter-tvos
```

**2. Add to PATH**

```bash
export PATH="$PATH:/path/to/flutter-tvos/bin"
```

Add the export to your `~/.zshrc` or `~/.bash_profile` to make it permanent.

**3. Download engine artifacts**

```bash
flutter-tvos precache
```

This downloads the pre-built tvOS engine artifacts (~300 MB). On first run, the Flutter SDK is also cloned automatically.

**4. Verify setup**

```bash
flutter-tvos doctor
```

---

## Quick Start

**Create a new tvOS app**

```bash
flutter-tvos create my_tv_app
cd my_tv_app
```

**Run on tvOS Simulator**

```bash
flutter-tvos devices          # list available simulators
flutter-tvos run -d <id>      # build, install, and launch with hot reload
```

**Build for tvOS Simulator**

```bash
flutter-tvos build tvos --simulator --debug
```

**Build for physical Apple TV**

```bash
flutter-tvos build tvos --release
```

---

## Commands

| Command | Description |
|---------|-------------|
| `flutter-tvos build tvos` | Build the tvOS app |
| `flutter-tvos run -d <device>` | Build, install, and run with hot reload |
| `flutter-tvos create <name>` | Scaffold a new tvOS app |
| `flutter-tvos create --template=plugin <name>` | Scaffold a tvOS plugin |
| `flutter-tvos clean` | Delete tvOS build artifacts |
| `flutter-tvos devices` | List tvOS simulators and connected devices |
| `flutter-tvos doctor` | Validate the development environment |
| `flutter-tvos precache` | Download engine artifacts |
| `flutter-tvos attach` | Attach to a running app |
| `flutter-tvos drive` | Run integration tests |
| `flutter-tvos test` | Run unit tests |

### Build flags

```bash
flutter-tvos build tvos --simulator --debug     # Simulator, debug (JIT)
flutter-tvos build tvos --simulator             # Simulator, debug (default)
flutter-tvos build tvos --release               # Device, release (AOT)
flutter-tvos build tvos --profile               # Device, profile (AOT)
```

---

## Plugin Support

Plugins with a `tvos:` platform key in their `pubspec.yaml` are discovered and linked automatically via CocoaPods.

**Plugin pubspec.yaml declaration:**

```yaml
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: MyPlugin
```

**Scaffold a new plugin:**

```bash
flutter-tvos create --template=plugin my_tvos_plugin
```

---

## Engine Artifacts

Pre-built engine artifacts are hosted at
[github.com/fluttertv/engine-artifacts](https://github.com/fluttertv/engine-artifacts)
and downloaded automatically by `flutter-tvos precache`.

To use a custom artifact source:

```bash
export TVOS_ENGINE_BASE_URL=https://your-host/artifacts
flutter-tvos precache
```

---

## How It Works

`flutter-tvos` wraps an unmodified Flutter 3.41.4 SDK using Flutter's dependency injection system. It injects tvOS-specific overrides for artifact resolution, device management, build targets, and doctor validation — the same approach used by [flutter-tizen](https://github.com/flutter-tizen/flutter-tizen) and other community embedders.

---

## Contributing

Issues and pull requests are welcome.

```bash
# Run tests
flutter/bin/dart test test/
```

---

## License

BSD 3-Clause — see [LICENSE](LICENSE).

This project incorporates code from Flutter and flutter-tizen (both BSD 3-Clause).  
See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for full attribution.

---

## Disclaimer

flutter-tvos is an independent community project and is not affiliated with,
endorsed by, or sponsored by Google LLC or Apple Inc.  
Flutter is a trademark of Google LLC. Apple TV and tvOS are trademarks of Apple Inc.
