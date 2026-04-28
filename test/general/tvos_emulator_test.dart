// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tvos/tvos_emulator.dart';

import '../src/common.dart';
import '../src/fake_process_manager.dart';

void main() {
  late FakeProcessManager processManager;
  late BufferLogger logger;
  late ProcessUtils processUtils;

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    processUtils = ProcessUtils(processManager: processManager, logger: logger);
  });

  testWithoutContext('getConnectedSimulators returns available tvOS simulators', () async {
    // Only Booted+isAvailable tvOS sims are returned; iOS sims and Shutdown
    // tvOS sims are excluded.
    processManager.addCommand(
      const FakeCommand(
        command: <String>['xcrun', 'simctl', 'list', 'devices', '--json'],
        stdout:
            '{"devices":{"com.apple.CoreSimulator.SimRuntime.tvOS-18-4":[{"udid":"AAAA-BBBB-CCCC","name":"Apple TV 4K","state":"Booted","isAvailable":true},{"udid":"DDDD-EEEE-FFFF","name":"Apple TV","state":"Shutdown","isAvailable":false}],"com.apple.CoreSimulator.SimRuntime.iOS-18-4":[{"udid":"1111-2222-3333","name":"iPhone 16","state":"Booted","isAvailable":true}]}}',
      ),
    );

    final List<Device> devices = await TvosEmulator.getConnectedSimulators(
      logger,
      processUtils: processUtils,
    );

    expect(devices, hasLength(1));
    expect(devices.first.id, equals('AAAA-BBBB-CCCC'));
    expect(devices.first.name, equals('Apple TV 4K'));
    expect(processManager, hasNoRemainingExpectations);
  });

  testWithoutContext('getConnectedSimulators returns empty list when no tvOS runtimes', () async {
    processManager.addCommand(
      const FakeCommand(
        command: <String>['xcrun', 'simctl', 'list', 'devices', '--json'],
        stdout:
            '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-4":[{"udid":"1111-2222-3333","name":"iPhone 16","state":"Booted","isAvailable":true}]}}',
      ),
    );

    final List<Device> devices = await TvosEmulator.getConnectedSimulators(
      logger,
      processUtils: processUtils,
    );

    expect(devices, isEmpty);
  });

  testWithoutContext('getConnectedSimulators handles simctl failure gracefully', () async {
    processManager.addCommand(
      const FakeCommand(
        command: <String>['xcrun', 'simctl', 'list', 'devices', '--json'],
        exitCode: 1,
      ),
    );

    final List<Device> devices = await TvosEmulator.getConnectedSimulators(
      logger,
      processUtils: processUtils,
    );

    expect(devices, isEmpty);
  });

  testWithoutContext('getConnectedSimulators returns multiple available simulators', () async {
    // Both Booted sims are returned; Shutdown ones are excluded.
    processManager.addCommand(
      const FakeCommand(
        command: <String>['xcrun', 'simctl', 'list', 'devices', '--json'],
        stdout:
            '{"devices":{"com.apple.CoreSimulator.SimRuntime.tvOS-18-4":[{"udid":"AAAA-BBBB-CCCC","name":"Apple TV 4K","state":"Booted","isAvailable":true},{"udid":"DDDD-EEEE-FFFF","name":"Apple TV 4K (3rd generation)","state":"Booted","isAvailable":true}]}}',
      ),
    );

    final List<Device> devices = await TvosEmulator.getConnectedSimulators(
      logger,
      processUtils: processUtils,
    );

    expect(devices, hasLength(2));
    expect(devices[0].id, equals('AAAA-BBBB-CCCC'));
    expect(devices[1].id, equals('DDDD-EEEE-FFFF'));
  });
}
