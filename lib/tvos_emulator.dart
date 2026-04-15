// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'package:file/file.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import 'tvos_device.dart';

class TvosEmulator {
  /// Queries `xcrun simctl list --json` to find available Apple TV simulators.
  static Future<List<TvosDevice>> getConnectedSimulators(
    Logger logger, {
    ProcessUtils? processUtils,
  }) async {
    final ProcessUtils pUtils = processUtils ?? globals.processUtils;
    final List<TvosDevice> devices = <TvosDevice>[];

    try {
      final RunResult result = await pUtils.run(<String>[
        'xcrun',
        'simctl',
        'list',
        'devices',
        '--json'
      ]);

      if (result.exitCode == 0) {
        final Map<String, dynamic> json = jsonDecode(result.stdout) as Map<String, dynamic>;
        final Map<String, dynamic> devicesList = json['devices'] as Map<String, dynamic>;

        for (final String runtime in devicesList.keys) {
          if (runtime.contains('tvOS')) {
            final List<dynamic> simulators = devicesList[runtime] as List<dynamic>;
            for (final dynamic simulator in simulators) {
              final Map<String, dynamic> sim = simulator as Map<String, dynamic>;
              if (sim['isAvailable'] == true) {
                devices.add(TvosDevice(
                  sim['udid'] as String,
                  name: sim['name'] as String,
                  logger: logger,
                  isSimulator: true,
                ));
              }
            }
          }
        }
      }
    } on Exception catch (e) {
      logger.printTrace('Error querying simctl: $e');
    }

    return devices;
  }

  /// Queries `xcrun devicectl list devices` to find connected physical Apple TV devices.
  ///
  /// Requires Xcode 15+ with CoreDevice support. The JSON output is written to
  /// a temporary file (devicectl does not support stdout JSON output).
  static Future<List<TvosDevice>> getPhysicalDevices(
    Logger logger, {
    ProcessUtils? processUtils,
  }) async {
    final ProcessUtils pUtils = processUtils ?? globals.processUtils;
    final List<TvosDevice> devices = <TvosDevice>[];

    try {
      // devicectl writes JSON to a file, not stdout
      final String tempPath = globals.fs.path.join(
        globals.fs.systemTempDirectory.path,
        'flutter_tvos_devicectl_${DateTime.now().millisecondsSinceEpoch}.json',
      );

      final RunResult result = await pUtils.run(<String>[
        'xcrun', 'devicectl', 'list', 'devices', '--json-output', tempPath,
      ]);

      if (result.exitCode != 0) {
        logger.printTrace('devicectl list devices failed: ${result.stderr}');
        return devices;
      }

      final File jsonFile = globals.fs.file(tempPath);
      if (!jsonFile.existsSync()) {
        logger.printTrace('devicectl JSON output not found at $tempPath');
        return devices;
      }

      try {
        final String jsonContent = jsonFile.readAsStringSync();
        devices.addAll(parseDevicectlOutput(jsonContent, logger));
      } finally {
        jsonFile.deleteSync();
      }
    } on Exception catch (e) {
      logger.printTrace('Error querying devicectl: $e');
    }

    return devices;
  }

  /// Parses devicectl JSON output and returns physical Apple TV devices.
  @visibleForTesting
  static List<TvosDevice> parseDevicectlOutput(String jsonContent, Logger logger) {
    final List<TvosDevice> devices = <TvosDevice>[];
    final Map<String, dynamic> json = jsonDecode(jsonContent) as Map<String, dynamic>;
    final Map<String, dynamic>? resultMap = json['result'] as Map<String, dynamic>?;
    if (resultMap == null) return devices;

    final List<dynamic>? deviceList = resultMap['devices'] as List<dynamic>?;
    if (deviceList == null) return devices;

    for (final dynamic device in deviceList) {
      final Map<String, dynamic> deviceMap = device as Map<String, dynamic>;
      final Map<String, dynamic>? hardware =
          deviceMap['hardwareProperties'] as Map<String, dynamic>?;
      final Map<String, dynamic>? deviceProps =
          deviceMap['deviceProperties'] as Map<String, dynamic>?;

      if (hardware == null) continue;

      final String? platform = hardware['platform'] as String?;
      final String? reality = hardware['reality'] as String?;

      // Only include physical tvOS devices
      if (platform != 'tvOS' || reality != 'physical') continue;

      final String? udid = deviceMap['identifier'] as String?;
      final String? name = deviceProps?['name'] as String? ??
          hardware['marketingName'] as String?;

      if (udid == null || name == null) continue;

      devices.add(TvosDevice(
        udid,
        name: name,
        logger: logger,
        isSimulator: false,
      ));
    }

    return devices;
  }
}
