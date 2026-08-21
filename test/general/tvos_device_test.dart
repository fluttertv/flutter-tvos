// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tvos/tvos_device.dart';

import '../src/common.dart';
import '../src/context.dart';

void main() {
  group('TvosSimulatorLogReader', () {
    testWithoutContext('extracts eventMessage from JSON log', () async {
      final reader = TvosSimulatorLogReader('test');
      final lines = <String>[];
      reader.logLines.listen(lines.add);

      const logLine =
          r'{ "eventMessage" : "flutter: The Dart VM service is listening on http:\/\/127.0.0.1:12345\/abc=\/" }';
      reader.processLogLine(logLine);
      await Future<void>.delayed(Duration.zero);

      expect(lines, hasLength(1));
      expect(lines.first, contains('The Dart VM service is listening on'));
      expect(lines.first, contains('127.0.0.1:12345'));

      reader.dispose();
    });

    testWithoutContext('ignores lines without eventMessage', () async {
      final reader = TvosSimulatorLogReader('test');
      final lines = <String>[];
      reader.logLines.listen(lines.add);

      reader.processLogLine('Filtering the log data using "senderImagePath ENDSWITH"');
      reader.processLogLine('[{');
      reader.processLogLine('  "timestamp" : "2026-04-08"');
      await Future<void>.delayed(Duration.zero);

      expect(lines, isEmpty);

      reader.dispose();
    });

    testWithoutContext('handles flutter print output', () async {
      final reader = TvosSimulatorLogReader('test');
      final lines = <String>[];
      reader.logLines.listen(lines.add);

      reader.processLogLine('{ "eventMessage" : "flutter: Hello from Dart!" }');
      await Future<void>.delayed(Duration.zero);

      expect(lines, hasLength(1));
      expect(lines.first, equals('flutter: Hello from Dart!'));

      reader.dispose();
    });
  });

  group('TvosDevice', () {
    testWithoutContext('TvosDevice reports correct platform', () async {
      final device = TvosDevice(
        'test-id',
        name: 'Apple TV 4K',
        logger: BufferLogger.test(),
        isSimulator: true,
      );

      expect(await device.targetPlatform, equals(TargetPlatform.ios));
      expect(await device.isLocalEmulator, isTrue);
      expect(await device.emulatorId, equals('test-id'));
      expect(await device.sdkNameAndVersion, equals('tvOS'));
    });

    testWithoutContext('TvosDevice physical device reports not emulator', () async {
      final device = TvosDevice(
        'physical-id',
        name: 'Apple TV',
        logger: BufferLogger.test(),
        isSimulator: false,
      );

      expect(await device.isLocalEmulator, isFalse);
      expect(await device.emulatorId, isNull);
    });

    testWithoutContext('TvosDevice supports expected build modes', () {
      final device = TvosDevice(
        'test-id',
        name: 'Apple TV 4K',
        logger: BufferLogger.test(),
        isSimulator: true,
      );

      expect(device.supportsRuntimeMode(BuildMode.debug), isTrue);
      expect(device.supportsRuntimeMode(BuildMode.profile), isTrue);
      expect(device.supportsRuntimeMode(BuildMode.release), isTrue);
      expect(device.supportsRuntimeMode(BuildMode.jitRelease), isFalse);
    });
  });

  // The on-device VM Service lookup polls mDNS up to this budget. It is the
  // difference between "hot reload works on device" and a session that connects
  // to nothing, so the override must not be misread — and a bad value must not
  // pass silently, or a typo looks like it took effect.
  group('TvosDevice mDNS resolve timeout', () {
    late BufferLogger logger;

    // The environment reaches the device through the Platform override, not the
    // constructor — the device reads it via globals at call time.
    void testEnv(String description, Map<String, String> environment, void Function(TvosDevice) body) {
      testUsingContext(
        description,
        () async {
          logger = BufferLogger.test();
          body(TvosDevice('tv', name: 'Apple TV', logger: logger, isSimulator: false));
        },
        overrides: <Type, Generator>{
          Platform: () => FakePlatform(operatingSystem: 'macos', environment: environment),
        },
      );
    }

    testEnv('defaults to 60s when unset', <String, String>{}, (TvosDevice device) {
      expect(device.resolveMdnsTimeoutForTesting(), const Duration(seconds: 60));
      expect(logger.warningText, isEmpty);
    });

    testEnv('honours a valid override', <String, String>{
      'FLUTTER_TVOS_MDNS_TIMEOUT_SECONDS': '15',
    }, (TvosDevice device) {
      expect(device.resolveMdnsTimeoutForTesting(), const Duration(seconds: 15));
      expect(logger.warningText, isEmpty);
    });

    testEnv('warns and falls back on a non-numeric override', <String, String>{
      'FLUTTER_TVOS_MDNS_TIMEOUT_SECONDS': 'soon',
    }, (TvosDevice device) {
      expect(device.resolveMdnsTimeoutForTesting(), const Duration(seconds: 60));
      expect(logger.warningText, contains('soon'));
    });

    // Zero would turn the poll loop into a single pass with no budget at all,
    // which reads as "the device never publishes" on every run.
    testEnv('warns and falls back on a non-positive override', <String, String>{
      'FLUTTER_TVOS_MDNS_TIMEOUT_SECONDS': '0',
    }, (TvosDevice device) {
      expect(device.resolveMdnsTimeoutForTesting(), const Duration(seconds: 60));
      expect(logger.warningText, contains('positive'));
    });
  });

  // devicectl keeps reporting `potentialHostnames` for a paired Apple TV long
  // after its CoreDevice tunnel drops, and those `*.coredevice.local` names are
  // registered locally by `remoted` — once the tunnel is down they resolve for
  // no process on the machine. Handing one back unchecked would satisfy the
  // caller's non-null test and skip the entire mDNS retry budget, leaving the
  // resident runner dialling a host that cannot be looked up. The gate below is
  // what keeps that from happening, so pin both of its answers.
  group('devicectl host gate', () {
    late TvosDevice device;

    setUp(() {
      device = TvosDevice(
        'tv',
        name: 'Apple TV',
        logger: BufferLogger.test(),
        isSimulator: false,
      );
    });

    testWithoutContext('accepts a numeric address', () async {
      // Short-circuits inside lookup(), so this asserts the fast path is not
      // accidentally gated behind a real resolver query.
      expect(await device.hostResolvesForTesting('127.0.0.1'), isTrue);
    });

    testWithoutContext('rejects a coredevice name that does not resolve', () async {
      expect(
        await device.hostResolvesForTesting(
          'flutter-tvos-no-such-device.coredevice.local',
        ),
        isFalse,
      );
    });
  });
}
