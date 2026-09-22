// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/version.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/ios/device_support.dart';
import 'package:flutter_tools/src/ios/lldb.dart';
import 'package:flutter_tools/src/ios/xcodeproj.dart';
import 'package:flutter_tvos/tvos_device.dart';
import 'package:flutter_tvos/tvos_device_support.dart';
import 'package:flutter_tvos/tvos_emulator.dart';
import 'package:test/fake.dart';

import '../src/common.dart';
import '../src/context.dart';

const String _devicectlAppleTv = '''
{"result": {"devices": [{
  "identifier": "00008110-000A1B2C3D4E5F60",
  "deviceProperties": {"name": "Living Room", "osVersionNumber": "26.6", "osBuildUpdate": "23L773"},
  "hardwareProperties": {"platform": "tvOS", "reality": "physical", "productType": "AppleTV14,1"}
}]}}
''';

const String _deviceDirPath =
    '/Users/dev/Library/Developer/Xcode/tvOS DeviceSupport/AppleTV14,1 26.6 (23L773)';

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

  Directory deviceDir() => fs.directory(_deviceDirPath);

  // A home directory in the memory file system is all the device reads from
  // the context; nothing here launches a process.
  Map<Type, Generator> overrides() => <Type, Generator>{
    FileSystem: () => fs,
    ProcessManager: () => FakeProcessManager.empty(),
    Platform: () => FakePlatform(environment: <String, String>{'HOME': '/Users/dev'}),
  };

  // What upstream's slow-attach timer prints when the warning is null.
  const upstreamBugReport = 'flutter/flutter/issues';

  group('TvosDeviceSupport', () {
    testWithoutContext('looks in tvOS DeviceSupport, named the way Xcode names it', () {
      expect(support().deviceDirectory!.path, _deviceDirPath);
    });

    testWithoutContext('never gives lldb a sysroot, even when symbols exist', () {
      deviceDir().childDirectory('Symbols').createSync(recursive: true);
      deviceDir().childFile('.finalized').createSync();

      // A non-null value makes LLDB send `platform select remote-ios` before
      // attaching to the Apple TV.
      expect(support().existingDeviceSupportSymbols, isNull);
    });

    testWithoutContext('blames the network, not Flutter, for a slow attach with symbols ready', () {
      deviceDir().childDirectory('Symbols').createSync(recursive: true);
      deviceDir().childFile('.finalized').createSync();

      final String? warning = support().missingSymbolsWarning();
      expect(warning, contains('most likely the wireless connection'));
      expect(warning, contains('FLUTTER_TVOS_LLDB_ATTACH_TIMEOUT_SECONDS'));
      expect(warning, isNot(contains(upstreamBugReport)));
      // LLDB drops the stale-copy warning's trigger once this has printed, so
      // this message has to name that cause too.
      expect(warning, contains('may be stale'));
      expect(warning, contains('rm -rf "$_deviceDirPath"'));
    });

    testWithoutContext('calls a prepared copy stale when lldb still reads from the device', () {
      deviceDir().childDirectory('Symbols').createSync(recursive: true);
      deviceDir().childFile('.finalized').createSync();

      final String? warning = support().missingSymbolsWarning(warnWhenSymbolsExist: true);
      expect(warning, contains('probably stale or incomplete'));
      expect(warning, contains('rm -rf "$_deviceDirPath"'));
    });

    testWithoutContext('accepts symbols one level down, the Xcode 27 iOS layout', () {
      deviceDir().childDirectory('arm64e').childDirectory('Symbols').createSync(recursive: true);
      deviceDir().childFile('.finalized').createSync();

      expect(support().missingSymbolsWarning(), contains('wireless connection'));
    });

    testWithoutContext(
      'warns that the copy is unfinished when the lock files are all there is',
      () {
        deviceDir().childDirectory('Symbols').createSync(recursive: true);
        deviceDir().childFile('.copying_lock').createSync();
        deviceDir().childFile('.processing_lock').createSync();

        final String? warning = support().missingSymbolsWarning();
        expect(warning, contains('has not finished preparing'));
        expect(warning, contains(_deviceDirPath));
        expect(warning, isNot(contains('iOS DeviceSupport')));
      },
    );

    testWithoutContext('does not count .finalized without symbols as finished', () {
      deviceDir().createSync(recursive: true);
      deviceDir().childFile('.finalized').createSync();

      expect(support().missingSymbolsWarning(), contains('has not finished preparing'));
      expect(
        support().missingSymbolsWarning(warnWhenSymbolsExist: true),
        contains('has not finished preparing'),
      );
    });

    testWithoutContext('warns that support is missing when there is no directory', () {
      final String? warning = support().missingSymbolsWarning();
      expect(warning, contains('has not prepared debugger support'));
      expect(warning, isNot(contains('finished')));
    });

    testWithoutContext('still warns, without a path, when the device cannot be identified', () {
      for (final unknown in <TvosDeviceSupport>[support(modelCode: null), support(version: null)]) {
        expect(unknown.deviceDirectory, isNull);
        final String? warning = unknown.missingSymbolsWarning();
        expect(warning, contains('could not work out where Xcode keeps debugger support'));
        expect(warning, isNot(contains(upstreamBugReport)));
      }
    });

    testWithoutContext('prepareDeviceSupport does nothing', () async {
      await support().prepareDeviceSupport();
      expect(deviceDir().existsSync(), isFalse);
    });
  });

  group('devicectl discovery', () {
    testWithoutContext('carries the model and Device Support version onto the device', () {
      final List<TvosDevice> devices = TvosEmulator.parseDevicectlOutput(
        _devicectlAppleTv,
        BufferLogger.test(),
      );

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

    testWithoutContext('reads the tvOS version lldb needs off the device', () {
      // LLDB drives stops by hand from 27 on, so this is the value that picks
      // the attach path.
      final TvosDevice device = TvosEmulator.parseDevicectlOutput(
        _devicectlAppleTv,
        BufferLogger.test(),
      ).single;

      expect(device.tvosVersion, Version(26, 6, 0));
    });

    testWithoutContext('leaves the tvOS version null when the device reports none', () {
      final TvosDevice device = TvosEmulator.parseDevicectlOutput('''
{"result": {"devices": [{
  "identifier": "00008110-000A1B2C3D4E5F60",
  "deviceProperties": {"name": "Living Room"},
  "hardwareProperties": {"platform": "tvOS", "reality": "physical"}
}]}}
''', BufferLogger.test()).single;

      expect(device.tvosVersion, isNull);
    });

    testWithoutContext('does not read a version out of a bare build number', () {
      // devicectl reported a build and no version. `23L773` is not tvOS 23:
      // answering that would claim "below 27" for a device that may be on 27.
      final TvosDevice device = TvosEmulator.parseDevicectlOutput('''
{"result": {"devices": [{
  "identifier": "00008110-000A1B2C3D4E5F60",
  "deviceProperties": {"name": "Living Room", "osBuildUpdate": "23L773"},
  "hardwareProperties": {"platform": "tvOS", "reality": "physical"}
}]}}
''', BufferLogger.test()).single;

      expect(device.osVersion, '23L773');
      expect(device.tvosVersion, isNull);
    });

    testWithoutContext('reads a simulator runtime version, and nothing from a nameless one', () {
      expect(
        TvosDevice(
          'sim',
          name: 'Apple TV',
          logger: BufferLogger.test(),
          isSimulator: true,
          osVersion: 'tvOS 18.4',
        ).tvosVersion,
        Version(18, 4, 0),
      );
      expect(
        TvosDevice(
          'sim',
          name: 'Apple TV',
          logger: BufferLogger.test(),
          isSimulator: true,
          osVersion: 'tvOS',
        ).tvosVersion,
        isNull,
      );
    });

    testWithoutContext('hands lldb the device version, not nothing', () {
      // The reason this PR exists, and the only place the version is decided:
      // LLDB keeps it private, so the factory is where it can be observed.
      final TvosDevice device = TvosEmulator.parseDevicectlOutput(
        _devicectlAppleTv,
        BufferLogger.test(),
      ).single;
      Version? handedOver;
      var created = 0;
      final fake = _FakeLLDB(LLDBLogForwarder());
      device.lldbFactory = (TvosDevice d, XcodeProjectInterpreter i, Version? version) {
        created++;
        handedOver = version;
        return fake;
      };

      expect(device.lldbForDebugSession(_FakeXcodeProjectInterpreter()), fake);
      expect(handedOver, Version(26, 6, 0));
      // Created once, then reused for the life of the device. Counted, because
      // the factory returns the same instance either way.
      expect(device.lldbForDebugSession(_FakeXcodeProjectInterpreter()), fake);
      expect(created, 1);
    });

    testUsingContext("builds the device's support from its home directory, model and build", () {
      final TvosDevice device = TvosEmulator.parseDevicectlOutput(
        _devicectlAppleTv,
        BufferLogger.test(),
      ).single;

      expect(device.deviceSupport.deviceDirectory?.path, _deviceDirPath);
    }, overrides: overrides());
  });

  group('TvosDevice.attachLldb', () {
    testUsingContext(
      "hands lldb the device's own support, and surfaces lldb's missing-symbols line",
      () async {
        final logger = BufferLogger.test();
        final TvosDevice device = TvosEmulator.parseDevicectlOutput(
          _devicectlAppleTv,
          logger,
        ).single;
        final forwarder = LLDBLogForwarder();
        final lldb = _FakeLLDB(forwarder);

        final bool attached = await device.attachLldb(
          lldb: lldb,
          lldbLogForwarder: forwarder,
          pid: 42,
          mode: BuildMode.debug,
          timeout: const Duration(minutes: 3),
        );
        // Let the broadcast stream deliver the line.
        await pumpEventQueue();

        expect(attached, isTrue);
        expect(lldb.receivedSupport, same(device.deviceSupport));
        expect(lldb.receivedPid, 42);
        expect(logger.warningText, contains('has not prepared debugger support'));
        expect(logger.warningText, contains(_deviceDirPath));
        expect(logger.traceText, contains('[lldb] warning: libobjc.A.dylib'));
      },
      overrides: overrides(),
    );

    testUsingContext('gives up at the timeout instead of waiting on lldb forever', () async {
      final logger = BufferLogger.test();
      final TvosDevice device = TvosEmulator.parseDevicectlOutput(_devicectlAppleTv, logger).single;
      final forwarder = LLDBLogForwarder();

      final bool attached = await device.attachLldb(
        lldb: _FakeLLDB(forwarder, never: true),
        lldbLogForwarder: forwarder,
        pid: 42,
        mode: BuildMode.debug,
        timeout: const Duration(milliseconds: 10),
      );

      expect(attached, isFalse);
      expect(logger.traceText, contains('lldb attach timed out'));
    }, overrides: overrides());
  });
}

class _FakeXcodeProjectInterpreter extends Fake implements XcodeProjectInterpreter {}

class _FakeLLDB extends Fake implements LLDB {
  _FakeLLDB(this._forwarder, {this.never = false});

  final LLDBLogForwarder _forwarder;
  final bool never;

  IOSDeviceSupport? receivedSupport;
  int? receivedPid;

  @override
  Future<bool> attachAndStart({
    required String deviceId,
    required int appProcessId,
    required LLDBLogForwarder lldbLogForwarder,
    required BuildMode mode,
    required IOSDeviceSupport deviceSupport,
  }) {
    receivedSupport = deviceSupport;
    receivedPid = appProcessId;
    if (never) {
      return Completer<bool>().future;
    }
    _forwarder.addLog(
      'warning: libobjc.A.dylib is being read from process memory. This may '
      'slow down debugging.',
    );
    return Future<bool>.value(true);
  }
}
