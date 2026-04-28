// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tvos/tvos_device.dart';

import '../src/common.dart';

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
}
