// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tvos/tvos_device.dart';
import 'package:flutter_tvos/tvos_emulator.dart';

import '../src/common.dart';

void main() {
  group('TvosEmulator.parseDevicectlOutput', () {
    testWithoutContext('parses physical Apple TV from devicectl JSON', () {
      const jsonOutput = '''
{
  "result": {
    "devices": [
      {
        "identifier": "00001234-ABCDEFGH1234",
        "deviceProperties": {
          "name": "Living Room Apple TV",
          "osVersionNumber": "17.1"
        },
        "hardwareProperties": {
          "platform": "tvOS",
          "reality": "physical",
          "marketingName": "Apple TV 4K (3rd generation)"
        }
      }
    ]
  },
  "info": {
    "outcome": "success"
  }
}
''';
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(
        jsonOutput,
        BufferLogger.test(),
      );

      expect(devices, hasLength(1));
      expect(devices.first.id, equals('00001234-ABCDEFGH1234'));
      expect(devices.first.name, equals('Living Room Apple TV'));
      expect(devices.first.isSimulator, isFalse);
    });

    testWithoutContext('filters out non-tvOS devices', () {
      const jsonOutput = '''
{
  "result": {
    "devices": [
      {
        "identifier": "iphone-udid-1234",
        "deviceProperties": {
          "name": "My iPhone"
        },
        "hardwareProperties": {
          "platform": "iOS",
          "reality": "physical",
          "marketingName": "iPhone 15 Pro"
        }
      },
      {
        "identifier": "appletv-udid-5678",
        "deviceProperties": {
          "name": "Apple TV"
        },
        "hardwareProperties": {
          "platform": "tvOS",
          "reality": "physical",
          "marketingName": "Apple TV 4K"
        }
      }
    ]
  }
}
''';
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(
        jsonOutput,
        BufferLogger.test(),
      );

      expect(devices, hasLength(1));
      expect(devices.first.id, equals('appletv-udid-5678'));
    });

    testWithoutContext('filters out virtual devices', () {
      const jsonOutput = '''
{
  "result": {
    "devices": [
      {
        "identifier": "sim-udid-1234",
        "deviceProperties": {
          "name": "Apple TV Simulator"
        },
        "hardwareProperties": {
          "platform": "tvOS",
          "reality": "virtual",
          "marketingName": "Apple TV 4K Simulator"
        }
      }
    ]
  }
}
''';
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(
        jsonOutput,
        BufferLogger.test(),
      );

      expect(devices, isEmpty);
    });

    testWithoutContext('returns empty list for empty devices array', () {
      const jsonOutput = '{"result": {"devices": []}}';
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(
        jsonOutput,
        BufferLogger.test(),
      );

      expect(devices, isEmpty);
    });

    testWithoutContext('returns empty list when result is missing', () {
      const jsonOutput = '{"info": {"outcome": "success"}}';
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(
        jsonOutput,
        BufferLogger.test(),
      );

      expect(devices, isEmpty);
    });

    testWithoutContext('filters out paired-but-offline devices (tunnelState=unavailable)', () {
      const jsonOutput = '''
{
  "result": {
    "devices": [
      {
        "identifier": "online-atv-udid",
        "deviceProperties": {
          "name": "Living Room Apple TV"
        },
        "hardwareProperties": {
          "platform": "tvOS",
          "reality": "physical",
          "marketingName": "Apple TV 4K"
        },
        "connectionProperties": {
          "tunnelState": "connected"
        }
      },
      {
        "identifier": "offline-atv-udid",
        "deviceProperties": {
          "name": "Entertainment Room"
        },
        "hardwareProperties": {
          "platform": "tvOS",
          "reality": "physical",
          "marketingName": "Apple TV 4K"
        },
        "connectionProperties": {
          "tunnelState": "unavailable"
        }
      }
    ]
  }
}
''';
      final logger = BufferLogger.test();
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(jsonOutput, logger);

      expect(devices, hasLength(1));
      expect(devices.first.id, equals('online-atv-udid'));
      // The offline device should be logged as a trace message.
      expect(logger.traceText, contains('Entertainment Room'));
    });

    testWithoutContext('falls back to marketingName when name is missing', () {
      const jsonOutput = '''
{
  "result": {
    "devices": [
      {
        "identifier": "atv-udid",
        "hardwareProperties": {
          "platform": "tvOS",
          "reality": "physical",
          "marketingName": "Apple TV 4K (3rd generation) Wi-Fi"
        }
      }
    ]
  }
}
''';
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(
        jsonOutput,
        BufferLogger.test(),
      );

      expect(devices, hasLength(1));
      expect(devices.first.name, equals('Apple TV 4K (3rd generation) Wi-Fi'));
    });
  });

  group('TvosPhysicalDeviceLogReader', () {
    testWithoutContext('emits lines to log stream', () async {
      final reader = TvosPhysicalDeviceLogReader('test', logger: BufferLogger.test());
      final lines = <String>[];
      reader.logLines.listen(lines.add);

      reader.processLogLine(
        'flutter: The Dart VM service is listening on http://127.0.0.1:12345/abc=/',
      );
      await Future<void>.delayed(Duration.zero);

      expect(lines, hasLength(1));
      expect(lines.first, contains('Dart VM service'));

      reader.dispose();
    });

    testWithoutContext('emits non-noise lines to log stream', () async {
      final reader = TvosPhysicalDeviceLogReader('test', logger: BufferLogger.test());
      final lines = <String>[];
      reader.logLines.listen(lines.add);

      reader.processLogLine('Some debug output');
      reader.processLogLine('flutter: Hello!');
      reader.processLogLine('Another line');
      await Future<void>.delayed(Duration.zero);

      expect(lines, hasLength(3));

      reader.dispose();
    });

    testWithoutContext('suppresses devicectl progress chatter', () async {
      final testLogger = BufferLogger.test();
      final reader = TvosPhysicalDeviceLogReader('test', logger: testLogger);
      final lines = <String>[];
      reader.logLines.listen(lines.add);

      // These patterns come from `script -t 0 /dev/null` wrapping devicectl.
      reader.processLogLine('Script started, output file is /dev/null');
      reader.processLogLine('07:49:03  Acquired tunnel connection to device.');
      reader.processLogLine('07:49:03  Enabling developer mode throttling override.');
      reader.processLogLine('07:49:04  Establishing a tunnel connection to the device.');
      reader.processLogLine('07:49:05  Resolved tunnel endpoint.');
      reader.processLogLine('Script done, output file is /dev/null');
      // System framework noise
      reader.processLogLine(
        '2026-04-25 07:49:05.123+0200 Runner[1234] [UIFocus] Focus update started',
      );
      // Empty line
      reader.processLogLine('');
      // This one should pass through
      reader.processLogLine('flutter: VM service listening on http://0.0.0.0:12345/abc=/');
      await Future<void>.delayed(Duration.zero);

      expect(lines, hasLength(1));
      expect(lines.first, contains('VM service'));

      reader.dispose();
    });
  });

  group('TvosDevice physical properties', () {
    testWithoutContext('physical device reports not emulator', () async {
      final device = TvosDevice(
        'physical-atv-id',
        name: 'Living Room Apple TV',
        logger: BufferLogger.test(),
        isSimulator: false,
      );

      expect(await device.isLocalEmulator, isFalse);
      expect(await device.emulatorId, isNull);
      expect(device.isSimulator, isFalse);
    });

    testWithoutContext('physical device supports all modes except jitRelease', () {
      final device = TvosDevice(
        'physical-atv-id',
        name: 'Apple TV',
        logger: BufferLogger.test(),
        isSimulator: false,
      );

      expect(device.supportsRuntimeMode(BuildMode.debug), isTrue);
      expect(device.supportsRuntimeMode(BuildMode.profile), isTrue);
      expect(device.supportsRuntimeMode(BuildMode.release), isTrue);
      expect(device.supportsRuntimeMode(BuildMode.jitRelease), isFalse);
    });

    testWithoutContext('getLogReader returns physical log reader for device', () async {
      final device = TvosDevice(
        'physical-id',
        name: 'Apple TV',
        logger: BufferLogger.test(),
        isSimulator: false,
      );

      final DeviceLogReader logReader = await device.getLogReader();
      expect(logReader, isA<TvosPhysicalDeviceLogReader>());
    });

    testWithoutContext('getLogReader returns simulator log reader for simulator', () async {
      final device = TvosDevice(
        'sim-id',
        name: 'Apple TV Simulator',
        logger: BufferLogger.test(),
        isSimulator: true,
      );

      final DeviceLogReader logReader = await device.getLogReader();
      expect(logReader, isA<TvosSimulatorLogReader>());
    });
  });
}
