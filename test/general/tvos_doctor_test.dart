// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/doctor_validator.dart';
import 'package:flutter_tvos/tvos_doctor.dart';

import '../src/common.dart';
import '../src/fake_process_manager.dart';
import '../src/fakes.dart';

// A fake platform whose script URI points to a known path so that
// _checkEngineArtifacts can resolve the CLI root without touching globals.
//
// Layout mirrored by _engineFs below:
//   /cli/bin/cache/flutter-tvos.snapshot  ← script
//   /cli/engine_artifacts/tvos_debug_sim_arm64/
FakePlatform _makePlatform() =>
    FakePlatform(script: Uri.file('/cli/bin/cache/flutter-tvos.snapshot'));

MemoryFileSystem _makeEngineFs({bool artifactsPresent = true}) {
  final fs = MemoryFileSystem.test();
  if (artifactsPresent) {
    fs.directory('/cli/engine_artifacts/tvos_debug_sim_arm64').createSync(recursive: true);
  }
  return fs;
}

void main() {
  late FakeProcessManager processManager;

  setUp(() {
    processManager = FakeProcessManager.empty();
  });

  group('TvosValidator', () {
    testWithoutContext('validates successfully when all checks pass', () async {
      processManager.addCommands(<FakeCommand>[
        // Xcode check
        const FakeCommand(
          command: <String>['xcodebuild', '-version'],
          stdout: 'Xcode 16.3\nBuild version 16E140',
        ),
        // tvOS SDK check
        const FakeCommand(
          command: <String>['xcrun', '--sdk', 'appletvos', '--show-sdk-path'],
          stdout:
              '/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS17.0.sdk',
        ),
        // Simulator runtime check
        const FakeCommand(
          command: <String>['xcrun', 'simctl', 'list', 'runtimes', '--json'],
          stdout:
              '{"runtimes":[{"name":"tvOS 17.0","identifier":"com.apple.CoreSimulator.SimRuntime.tvOS-17-0"}]}',
        ),
        // CocoaPods check
        const FakeCommand(command: <String>['pod', '--version'], stdout: '1.15.2'),
      ]);

      final validator = TvosValidator(
        processManager: processManager,
        fileSystem: _makeEngineFs(),
        platform: _makePlatform(),
      );

      final ValidationResult result = await validator.validate();
      expect(result.type, equals(ValidationType.success));

      final List<String> messageTexts = result.messages
          .map((ValidationMessage m) => m.message)
          .toList();
      expect(messageTexts, contains(contains('Xcode installed')));
      expect(messageTexts, contains(contains('tvOS SDK')));
      expect(messageTexts, contains(contains('tvOS Simulator runtime')));
      expect(messageTexts, contains(contains('CocoaPods')));
      expect(messageTexts, contains(contains('engine artifacts')));
      expect(processManager, hasNoRemainingExpectations);
    });

    testWithoutContext('reports missing when Xcode is not installed', () async {
      processManager.addCommand(
        const FakeCommand(command: <String>['xcodebuild', '-version'], exitCode: 1),
      );

      final validator = TvosValidator(
        processManager: processManager,
        fileSystem: _makeEngineFs(),
        platform: _makePlatform(),
      );

      final ValidationResult result = await validator.validate();
      expect(result.type, equals(ValidationType.missing));
      expect(result.messages.first.message, contains('Xcode is not installed'));
    });

    testWithoutContext('reports partial when tvOS SDK is missing', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['xcodebuild', '-version'],
          stdout: 'Xcode 16.3\nBuild version 16E140',
        ),
        const FakeCommand(
          command: <String>['xcrun', '--sdk', 'appletvos', '--show-sdk-path'],
          exitCode: 1,
        ),
        const FakeCommand(
          command: <String>['xcrun', 'simctl', 'list', 'runtimes', '--json'],
          stdout: '{"runtimes":[{"name":"tvOS 17.0"}]}',
        ),
        const FakeCommand(command: <String>['pod', '--version'], stdout: '1.15.2'),
      ]);

      final validator = TvosValidator(
        processManager: processManager,
        fileSystem: _makeEngineFs(),
        platform: _makePlatform(),
      );

      final ValidationResult result = await validator.validate();
      expect(result.type, equals(ValidationType.partial));
      final List<String> messageTexts = result.messages
          .map((ValidationMessage m) => m.message)
          .toList();
      expect(messageTexts, contains(contains('tvOS SDK not found')));
    });

    testWithoutContext('reports partial when simulator runtime is missing', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['xcodebuild', '-version'],
          stdout: 'Xcode 16.3\nBuild version 16E140',
        ),
        const FakeCommand(
          command: <String>['xcrun', '--sdk', 'appletvos', '--show-sdk-path'],
          stdout: '/path/to/AppleTVOS17.0.sdk',
        ),
        // No tvOS runtime
        const FakeCommand(
          command: <String>['xcrun', 'simctl', 'list', 'runtimes', '--json'],
          stdout:
              '{"runtimes":[{"name":"iOS 17.0","identifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-0"}]}',
        ),
        const FakeCommand(command: <String>['pod', '--version'], stdout: '1.15.2'),
      ]);

      final validator = TvosValidator(
        processManager: processManager,
        fileSystem: _makeEngineFs(),
        platform: _makePlatform(),
      );

      final ValidationResult result = await validator.validate();
      expect(result.type, equals(ValidationType.partial));
      final List<String> messageTexts = result.messages
          .map((ValidationMessage m) => m.message)
          .toList();
      expect(messageTexts, contains(contains('No tvOS Simulator runtime found')));
    });

    testWithoutContext('reports hint when CocoaPods is missing', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['xcodebuild', '-version'],
          stdout: 'Xcode 16.3\nBuild version 16E140',
        ),
        const FakeCommand(
          command: <String>['xcrun', '--sdk', 'appletvos', '--show-sdk-path'],
          stdout: '/path/to/AppleTVOS17.0.sdk',
        ),
        const FakeCommand(
          command: <String>['xcrun', 'simctl', 'list', 'runtimes', '--json'],
          stdout: '{"runtimes":[{"name":"tvOS 17.0"}]}',
        ),
        const FakeCommand(command: <String>['pod', '--version'], exitCode: 1),
      ]);

      final validator = TvosValidator(
        processManager: processManager,
        fileSystem: _makeEngineFs(),
        platform: _makePlatform(),
      );

      final ValidationResult result = await validator.validate();
      // Hints don't cause partial — CocoaPods is optional
      expect(result.type, equals(ValidationType.success));
      final List<String> messageTexts = result.messages
          .map((ValidationMessage m) => m.message)
          .toList();
      expect(messageTexts, contains(contains('CocoaPods not installed')));
    });

    testWithoutContext('reports hint when engine artifacts are absent', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['xcodebuild', '-version'],
          stdout: 'Xcode 16.3\nBuild version 16E140',
        ),
        const FakeCommand(
          command: <String>['xcrun', '--sdk', 'appletvos', '--show-sdk-path'],
          stdout: '/path/to/AppleTVOS17.0.sdk',
        ),
        const FakeCommand(
          command: <String>['xcrun', 'simctl', 'list', 'runtimes', '--json'],
          stdout: '{"runtimes":[{"name":"tvOS 17.0"}]}',
        ),
        const FakeCommand(command: <String>['pod', '--version'], stdout: '1.15.2'),
      ]);

      final validator = TvosValidator(
        processManager: processManager,
        fileSystem: _makeEngineFs(artifactsPresent: false),
        platform: _makePlatform(),
      );

      final ValidationResult result = await validator.validate();
      // Missing artifacts = hint only; hints leave overall as success
      expect(result.type, equals(ValidationType.success));
      final List<String> messageTexts = result.messages
          .map((ValidationMessage m) => m.message)
          .toList();
      expect(messageTexts, contains(contains('engine artifacts not found')));
    });
  });

  group('TvosWorkflow', () {
    testWithoutContext('appliesToHostPlatform returns true on macOS', () {
      final workflow = TvosWorkflow(
        operatingSystemUtils: FakeOperatingSystemUtils(hostPlatform: HostPlatform.darwin_arm64),
      );
      expect(workflow.appliesToHostPlatform, isTrue);
      expect(workflow.canLaunchDevices, isTrue);
      expect(workflow.canListDevices, isTrue);
      expect(workflow.canListEmulators, isTrue);
    });
  });
}
