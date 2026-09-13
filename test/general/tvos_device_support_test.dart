// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tvos/tvos_device.dart';
import 'package:flutter_tvos/tvos_device_support.dart';
import 'package:flutter_tvos/tvos_emulator.dart';

import '../src/common.dart';

void main() {
  late FileSystem fs;
  late Directory home;

  setUp(() {
    fs = MemoryFileSystem.test();
    home = fs.directory('/Users/dev')..createSync(recursive: true);
  });

  TvosDeviceSupport support({
    Directory? homeDirectory,
    String? modelCode = 'AppleTV14,1',
    String? version = '26.6 (23L773)',
  }) => TvosDeviceSupport(
    homeDirectory: homeDirectory ?? home,
    modelCode: modelCode,
    operatingSystemVersion: version,
  );

  Directory deviceDir() => home
      .childDirectory('Library/Developer/Xcode/tvOS DeviceSupport')
      .childDirectory('AppleTV14,1 26.6 (23L773)');

  group('TvosDeviceSupport', () {
    testWithoutContext('looks in tvOS DeviceSupport, named the way Xcode names it', () {
      expect(
        support().deviceDirectory!.path,
        '/Users/dev/Library/Developer/Xcode/tvOS DeviceSupport/AppleTV14,1 26.6 (23L773)',
      );
    });

    testWithoutContext('never gives lldb a sysroot, even when symbols exist', () {
      deviceDir().childDirectory('Symbols').createSync(recursive: true);
      deviceDir().childFile('.finalized').createSync();

      // A non-null value makes LLDB send `platform select remote-ios` before
      // attaching to the Apple TV.
      expect(support().existingDeviceSupportSymbols, isNull);
    });

    testWithoutContext('no warning once Xcode has finished preparing the device', () {
      deviceDir().childDirectory('Symbols').createSync(recursive: true);
      deviceDir().childFile('.finalized').createSync();

      expect(support().missingSymbolsWarning(), isNull);
      expect(support().missingSymbolsWarning(warnWhenSymbolsExist: true), isNull);
    });

    testWithoutContext(
      'warns that the copy is unfinished when the lock files are all there is',
      () {
        deviceDir().childDirectory('Symbols').createSync(recursive: true);
        deviceDir().childFile('.copying_lock').createSync();
        deviceDir().childFile('.processing_lock').createSync();

        final String? warning = support().missingSymbolsWarning();
        expect(warning, contains('has not finished preparing'));
        expect(warning, contains('tvOS DeviceSupport/AppleTV14,1 26.6 (23L773)'));
        expect(warning, isNot(contains('iOS DeviceSupport')));
      },
    );

    testWithoutContext('warns that support is missing when there is no directory', () {
      final String? warning = support().missingSymbolsWarning();
      expect(warning, contains('has not prepared debugger support'));
      expect(warning, isNot(contains('finished')));
    });

    testWithoutContext('says nothing when the device cannot be identified', () {
      expect(support(modelCode: null).missingSymbolsWarning(), isNull);
      expect(support(version: null).missingSymbolsWarning(), isNull);
      expect(support(modelCode: null).deviceDirectory, isNull);
    });

    testWithoutContext('prepareDeviceSupport does nothing', () async {
      await support().prepareDeviceSupport();
      expect(deviceDir().existsSync(), isFalse);
    });
  });

  group('devicectl discovery', () {
    testWithoutContext('carries the model and Device Support version onto the device', () {
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput('''
{"result": {"devices": [{
  "identifier": "00008110-000A1B2C3D4E5F60",
  "deviceProperties": {"name": "Living Room", "osVersionNumber": "26.6", "osBuildUpdate": "23L773"},
  "hardwareProperties": {"platform": "tvOS", "reality": "physical", "productType": "AppleTV14,1"}
}]}}
''', BufferLogger.test());

      expect(devices, hasLength(1));
      expect(devices.single.modelCode, 'AppleTV14,1');
      expect(devices.single.deviceSupportVersion, '26.6 (23L773)');
    });

    testWithoutContext('leaves the version null without a build number', () {
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput('''
{"result": {"devices": [{
  "identifier": "00008110-000A1B2C3D4E5F60",
  "deviceProperties": {"name": "Living Room", "osVersionNumber": "26.6"},
  "hardwareProperties": {"platform": "tvOS", "reality": "physical"}
}]}}
''', BufferLogger.test());

      expect(devices.single.modelCode, isNull);
      expect(devices.single.deviceSupportVersion, isNull);
    });
  });
}
