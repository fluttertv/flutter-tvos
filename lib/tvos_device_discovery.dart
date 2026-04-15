// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/flutter_device_manager.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

import 'tvos_doctor.dart';
import 'tvos_emulator.dart';

/// Extended device manager for tvOS.
///
/// Adds [TvosDeviceDiscovery] to the standard Flutter device discoverers.
class TvosDeviceManager extends FlutterDeviceManager {
  TvosDeviceManager({
    required super.logger,
    required super.processManager,
    required super.platform,
    required super.androidSdk,
    required super.iosSimulatorUtils,
    required super.featureFlags,
    required super.fileSystem,
    required super.iosWorkflow,
    required super.artifacts,
    required super.flutterVersion,
    required super.androidWorkflow,
    required super.xcDevice,
    required super.userMessages,
    required super.windowsWorkflow,
    required super.macOSWorkflow,
    required super.operatingSystemUtils,
    required super.customDevicesConfig,
    required super.nativeAssetsBuilder,
    required this.tvosWorkflow,
  });

  final TvosWorkflow tvosWorkflow;

  @override
  List<DeviceDiscovery> get deviceDiscoverers => <DeviceDiscovery>[
        ...super.deviceDiscoverers,
        TvosDeviceDiscovery(
          tvosWorkflow: tvosWorkflow,
          logger: globals.logger,
        ),
      ];
}

/// Discovers tvOS devices and simulators via `xcrun simctl`.
class TvosDeviceDiscovery extends PollingDeviceDiscovery {
  TvosDeviceDiscovery({
    required TvosWorkflow tvosWorkflow,
    required Logger logger,
  })  : _tvosWorkflow = tvosWorkflow,
        _logger = logger,
        super('tvOS devices');

  final TvosWorkflow _tvosWorkflow;
  final Logger _logger;

  @override
  bool get supportsPlatform => _tvosWorkflow.canListDevices;

  @override
  bool get canListAnything => _tvosWorkflow.canListDevices;

  @override
  List<String> get wellKnownIds => const <String>[];

  @override
  Future<List<Device>> pollingGetDevices({Duration? timeout, bool forWirelessDiscovery = false}) async {
    final List<Device> devices = <Device>[];

    try {
      devices.addAll(await TvosEmulator.getConnectedSimulators(_logger));
    } on Exception catch (err) {
      _logger.printTrace('Failed to discover tvOS simulators: $err');
    }

    try {
      devices.addAll(await TvosEmulator.getPhysicalDevices(_logger));
    } on Exception catch (err) {
      _logger.printTrace('Failed to discover physical tvOS devices: $err');
    }

    return devices;
  }

  @override
  Future<List<String>> getDiagnostics() async => const <String>[];
}
