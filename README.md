# flutter-tvos

A Flutter toolchain for building and running Flutter apps on **Apple TV (tvOS)**.

`flutter-tvos` is a drop-in CLI companion to the Flutter SDK — same commands, same hot reload, same DevTools — targeting tvOS instead of iOS.

> **macOS only.** Xcode is required.

## Installation

```sh
git clone https://github.com/fluttertv/flutter-tvos.git
cd flutter-tvos
export PATH="$PATH:$PWD/bin"
flutter-tvos precache
flutter-tvos doctor
```

See [Getting started](doc/get-started.md) for the full setup guide.

## Usage

`flutter-tvos` substitutes the original [`flutter`](https://docs.flutter.dev/reference/flutter-cli) CLI command.

```sh
# Check the installed tooling and list all connected devices.
flutter-tvos doctor -v
flutter-tvos devices

# Create a new app project.
flutter-tvos create my_tv_app
cd my_tv_app

# Build and run on a tvOS Simulator.
flutter-tvos run -d <simulator_id>

# Build and run on a physical Apple TV in release mode.
flutter-tvos run -d <device_id> --release
```

- See [Supported commands](doc/commands.md) for all available commands and usage examples.
- See [Getting started](doc/get-started.md) to create your first app and try **hot reload**.
- To **update** flutter-tvos, run `git pull` in the cloned directory.

## Docs

#### App development

- [Getting started](doc/get-started.md)
- [Supported commands](doc/commands.md)
- [Debugging apps](doc/debug-app.md)
- [Publishing to the App Store](doc/publish-app.md)

#### Plugin development

- [Writing a tvOS plugin](doc/develop-plugin.md)

#### Project internals

- [Architecture](doc/architecture.md)

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

```sh
# Run tests
flutter/bin/dart test test/
```

## License

BSD 3-Clause — see [LICENSE](LICENSE).

This project incorporates code from Flutter and flutter-tizen (both BSD 3-Clause).  
See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for full attribution.

---

_flutter-tvos is an independent community project and is not affiliated with, endorsed by, or sponsored by Google LLC or Apple Inc. Flutter is a trademark of Google LLC. Apple TV and tvOS are trademarks of Apple Inc._
