# flutter-tvos Tests

Unit tests for the flutter-tvos CLI tool.

## Structure

```
test/
├── src/               # Re-exports from Flutter's test infrastructure
│   ├── common.dart
│   ├── context.dart
│   └── fakes.dart
└── general/           # Core component tests
    ├── tvos_build_info_test.dart
    ├── tvos_emulator_test.dart
    ├── tvos_device_test.dart
    ├── tvos_device_discovery_test.dart
    ├── tvos_doctor_test.dart
    ├── tvos_application_package_test.dart
    ├── tvos_plugins_test.dart
    ├── tvos_plugin_template_test.dart
    ├── tvos_code_signing_test.dart
    ├── tvos_clean_test.dart
    └── tvos_physical_device_test.dart
```

## Running Tests

```bash
# Run all tests
TMPDIR="$(cd "$TMPDIR" && pwd -P)" flutter/bin/dart test test/

# Run a specific test file
TMPDIR="$(cd "$TMPDIR" && pwd -P)" flutter/bin/dart test test/general/tvos_emulator_test.dart
```

### Why the resolved `TMPDIR` (macOS)

Without it, ~30 tests fail with:

```
FileSystemException: Test attempted to modify directory outside of temp
directory: /var/folders/.../T
```

Flutter's test harness installs an FS guard (`flutter/packages/flutter_tools/test/src/fs_safety.dart`)
that rejects writes outside the system temp directory. It resolves symlinks when
computing the allowed root but **not** on the path it checks — and on macOS
`$TMPDIR` is `/var/folders/…` while `/var` is a symlink to `/private/var`. The two
never compare equal, so any test touching a real temp directory fails, including
ones that only reach it through flutter_tools' own `LocalFileSystem`.

Passing an already-resolved `TMPDIR` removes the discrepancy at the source and
leaves the guard fully armed. Do **not** substitute `FLUTTER_TEST_DISABLE_FS_GUARD=true`:
that switches the guard off entirely, and the guard is what stops a stray test
writing to `$HOME`.

## Writing Tests

Tests use Flutter's own test infrastructure (`testWithoutContext`, `testUsingContext`, `FakeProcessManager`) re-exported via `test/src/`. Prefer `testWithoutContext` for tests that don't need DI context.

```dart
import '../src/common.dart';

void main() {
  testWithoutContext('description', () {
    // test body
  });
}
```

## CI

Tests run on every push and pull request. See `.github/workflows/test.yml`.
