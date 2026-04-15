# flutter-tvos Tests

This directory contains unit tests for the flutter-tvos CLI tool.

## Test Structure

```
test/
├── commands/          # Tests for CLI commands
│   ├── build_test.dart
│   ├── run_test.dart
│   └── ...
└── general/           # Tests for core functionality
    ├── tvos_device_test.dart
    ├── tvos_emulator_test.dart
    └── ...
```

## Running Tests

Run all tests:
```bash
flutter test
```

Run specific test file:
```bash
flutter test test/commands/build_test.dart
```

Run with coverage:
```bash
flutter test --coverage
```

## Test Types

### Unit Tests
Basic unit tests verify individual components work correctly:
- Device discovery and enumeration
- Build configuration parsing
- Command argument validation
- Bundle ID resolution from project files

### Integration Tests (E2E)
Full end-to-end tests would:
1. Create a test tvOS app
2. Run `flutter-tvos build` and verify output
3. Run `flutter-tvos run` on a simulator
4. Verify hot reload works

These are typically run in CI with a real simulator environment.

## Adding New Tests

Follow the existing test structure:

```dart
import 'package:test/test.dart';

void main() {
  group('Feature name', () {
    test('describes what is being tested', () {
      // Arrange: set up test data
      const testValue = 'example';
      
      // Act: call the function being tested
      final result = testValue.isNotEmpty;
      
      // Assert: verify the result
      expect(result, true);
    });
  });
}
```

## CI/CD Integration

Tests run in GitHub Actions for every push and pull request. See `.github/workflows/test.yml` for the workflow configuration.
