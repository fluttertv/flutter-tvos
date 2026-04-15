# Contributing to flutter-tvos

Thanks for your interest in contributing. This project is BSD 3-Clause licensed and all contributions are welcome — no CLA required.

## Reporting Bugs

Open an issue on [GitHub Issues](https://github.com/fluttertv/flutter-tvos/issues). Please include:

- `flutter-tvos --version` output
- macOS version (`sw_vers`)
- Xcode version (`xcodebuild -version`)
- Full error output (use code blocks)
- Steps to reproduce

The more detail you provide, the faster the bug can be tracked down.

## Submitting a Pull Request

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Run the test suite and static analysis (see below)
4. Open a PR against `main` with a clear description of what changed and why

Keep PRs focused. One logical change per PR makes review faster.

## Running Tests

The Flutter SDK is bootstrapped automatically into `flutter/` when you first run any `flutter-tvos` command. Once it is present, run the full test suite from the `flutter-tvos/` directory:

```bash
flutter/bin/dart test test/
```

There are 74 unit tests in `test/general/`. They use Flutter's own test infrastructure (`FakeProcessManager`, `testWithoutContext`, `testUsingContext`) and do not require a connected device or simulator.

## Static Analysis

```bash
flutter/bin/dart analyze lib/
```

Fix all warnings and errors before opening a PR. New code should introduce no new analysis issues.

## Code Style

- Follow the patterns already in the codebase
- Match Flutter SDK conventions (naming, structure, error handling)
- Prefer `testWithoutContext` for tests that do not need a full context; use `testUsingContext` only when necessary
- Keep command implementations thin — logic belongs in helpers that can be unit-tested

## What Not to Contribute

Do not modify anything inside the `flutter/` directory. That directory is a managed Flutter SDK checkout controlled by `bin/internal/flutter.version`. Changes there will be overwritten on the next bootstrap.

Similarly, do not modify files under `engine_artifacts/` — those are populated by the artifact download step and are not part of the source tree.

If you believe the pinned Flutter version needs to change, open an issue to discuss it first.
