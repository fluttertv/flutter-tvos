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
flutter/bin/dart test test/

# Run a specific test file
flutter/bin/dart test test/general/tvos_emulator_test.dart
```

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
