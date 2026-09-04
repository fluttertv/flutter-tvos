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

## Branching Model

- **`main`** holds released code only. Every commit on `main` corresponds to a published release (or the release process itself). Nothing is merged into `main` directly.
- **`dev`** is the integration branch. All pull requests target `dev`. It always contains the latest `main` plus the changes queued for the next release.
- At release time, maintainers merge `dev` into `main`, tag, and publish; `main` is then merged back into `dev` so the two stay in sync.

## Submitting a Pull Request

1. Fork the repository and create a branch from `dev`
2. Make your changes
3. Add a `CHANGELOG.md` entry under `[Unreleased]` (see below)
4. Run the test suite and static analysis (see below)
5. Open a PR against **`dev`** with a clear description of what changed and why

Keep PRs focused. One logical change per PR makes review faster.

## Changelog

User-visible changes (fixes, features, behavior changes) get an entry in `CHANGELOG.md` under the `[Unreleased]` heading, written in the same style as the released sections. **Do not bump the version** in `pubspec.yaml` or add a version heading — maintainers assign version numbers when cutting a release, at which point `[Unreleased]` entries are moved into the new version's section.

Internal-only changes (refactors, CI, test-only changes) don't need a changelog entry.

## Running Tests

The Flutter SDK is bootstrapped automatically into `flutter/` when you first run any `flutter-tvos` command. Once it is present, run the full test suite from the `flutter-tvos/` directory:

```bash
TMPDIR="$(cd "${TMPDIR:-/tmp}" && pwd -P)" flutter/bin/dart test test/
```

There are roughly 450 unit tests across the 40 files in `test/general/`. They use Flutter's own test infrastructure (`FakeProcessManager`, `testWithoutContext`, `testUsingContext`) and do not require a connected device or simulator. **The suite is green** — anything failing is yours.

**On macOS, keep the `TMPDIR` prefix.** Without it roughly 58 tests fail, and they fail in a way that looks like real breakage rather than an environment problem. Flutter's test harness installs an FS guard that resolves symlinks when computing the allowed temp root but not on the path it checks; `$TMPDIR` is `/var/folders/…` and `/var` is a symlink to `/private/var`, so the two never compare equal. CI passes the resolved form for this reason. Do not reach for `FLUTTER_TEST_DISABLE_FS_GUARD` instead — see `test/README.md`.

### Editing the CLI itself

`flutter-tvos` runs a snapshot compiled to `bin/cache/flutter-tvos.snapshot`, and `bin/internal/shared.sh` only recompiles it when `git rev-parse HEAD` changes. **An *uncommitted* edit under `lib/` or `bin/` therefore does nothing until you remove it:**

```bash
rm bin/cache/flutter-tvos.snapshot
```

Committing the edit moves `HEAD` and rebuilds the snapshot on its own, so this bites during the edit-and-try loop specifically. Worth knowing before you lose an afternoon to it: the stale snapshot does not announce itself — your change appears to have run and had no effect, so the same build fails the same way, byte for byte, and it reads as a wrong fix rather than one that never executed.

(The revision is only stale-checked this way in a git checkout. A non-git install hashes the contents of `bin/` and `lib/` instead, and needs nothing.)

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
