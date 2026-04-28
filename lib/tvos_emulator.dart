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
  /// Queries `xcrun simctl list --json` for tvOS simulators.
  ///
  /// Matches stock Flutter's iOS simulator behaviour: by default, only
  /// **booted** simulators are returned (those are what `flutter devices`
  /// reports). Pass [includeShutdown] true to get every available simulator
  /// — used by `flutter-tvos emulators` and the device manager when
  /// `--device-id <id>` resolves to a shutdown sim that needs booting.
  static Future<List<TvosDevice>> getConnectedSimulators(
    Logger logger, {
    ProcessUtils? processUtils,
    bool includeShutdown = false,
  }) async {
    final ProcessUtils pUtils = processUtils ?? globals.processUtils;
    final devices = <TvosDevice>[];

    try {
      final RunResult result = await pUtils.run(<String>[
        'xcrun',
        'simctl',
        'list',
        'devices',
        '--json',
      ]);

      if (result.exitCode == 0) {
        final json = jsonDecode(result.stdout) as Map<String, dynamic>;
        final devicesList = json['devices'] as Map<String, dynamic>;

        for (final String runtime in devicesList.keys) {
          if (!runtime.contains('tvOS')) {
            continue;
          }
          final String runtimeVersion = _parseRuntimeVersion(runtime);
          final simulators = devicesList[runtime] as List<dynamic>;
          for (final dynamic simulator in simulators) {
            final sim = simulator as Map<String, dynamic>;
            if (sim['isAvailable'] != true) {
              continue;
            }
            final String state = (sim['state'] as String?) ?? 'Shutdown';
            if (!includeShutdown && state != 'Booted') {
              continue;
            }
            devices.add(
              TvosDevice(
                sim['udid'] as String,
                name: sim['name'] as String,
                logger: logger,
                isSimulator: true,
                osVersion: runtimeVersion,
              ),
            );
          }
        }
      }
    } on Exception catch (e) {
      logger.printTrace('Error querying simctl: $e');
    }

    return devices;
  }

  /// Converts `com.apple.CoreSimulator.SimRuntime.tvOS-18-4` → `tvOS 18.4`.
  static String _parseRuntimeVersion(String runtime) {
    final RegExpMatch? m = RegExp(r'tvOS[-_](\d+)[-_](\d+)(?:[-_](\d+))?').firstMatch(runtime);
    if (m == null) {
      return 'tvOS';
    }
    final String major = m.group(1)!;
    final String minor = m.group(2)!;
    final String? patch = m.group(3);
    return patch == null ? 'tvOS $major.$minor' : 'tvOS $major.$minor.$patch';
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
    final devices = <TvosDevice>[];

    try {
      // devicectl writes JSON to a file, not stdout
      final String tempPath = globals.fs.path.join(
        globals.fs.systemTempDirectory.path,
        'flutter_tvos_devicectl_${DateTime.now().millisecondsSinceEpoch}.json',
      );

      final RunResult result = await pUtils.run(<String>[
        'xcrun',
        'devicectl',
        'list',
        'devices',
        '--json-output',
        tempPath,
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
  ///
  /// Hides devices that are paired but currently unreachable — devicectl
  /// reports them with `connectionProperties.tunnelState == "unavailable"`
  /// and emits a separate "Browsing on the local area network..." error.
  /// Stock `flutter devices` doesn't surface those either.
  @visibleForTesting
  static List<TvosDevice> parseDevicectlOutput(String jsonContent, Logger logger) {
    final devices = <TvosDevice>[];
    final json = jsonDecode(jsonContent) as Map<String, dynamic>;
    final resultMap = json['result'] as Map<String, dynamic>?;
    if (resultMap == null) {
      return devices;
    }

    final deviceList = resultMap['devices'] as List<dynamic>?;
    if (deviceList == null) {
      return devices;
    }

    for (final Object? device in deviceList) {
      final deviceMap = device! as Map<String, dynamic>;
      final hardware = deviceMap['hardwareProperties'] as Map<String, dynamic>?;
      final deviceProps = deviceMap['deviceProperties'] as Map<String, dynamic>?;
      final connection = deviceMap['connectionProperties'] as Map<String, dynamic>?;

      if (hardware == null) {
        continue;
      }

      final platform = hardware['platform'] as String?;
      final reality = hardware['reality'] as String?;

      // Only include physical tvOS devices
      if (platform != 'tvOS' || reality != 'physical') {
        continue;
      }

      // Filter out paired-but-offline devices.
      final tunnelState = connection?['tunnelState'] as String?;
      if (tunnelState == 'unavailable') {
        final offlineName = deviceProps?['name'] as String?;
        logger.printTrace(
          'Skipping offline tvOS device "${offlineName ?? '?'}" '
          '(tunnelState=$tunnelState).',
        );
        continue;
      }

      final udid = deviceMap['identifier'] as String?;
      final String? name = deviceProps?['name'] as String? ?? hardware['marketingName'] as String?;

      if (udid == null || name == null) {
        continue;
      }

      // Build the OS version string the same way stock iOS does:
      // "<version> <build>" (e.g. "18.6 22M84"). Falls back gracefully if
      // either piece is missing.
      final osVersionNumber = deviceProps?['osVersionNumber'] as String?;
      final osBuildUpdate = deviceProps?['osBuildUpdate'] as String?;
      final String osVersion = <String?>[
        if (osVersionNumber != null) 'tvOS $osVersionNumber',
        osBuildUpdate,
      ].whereType<String>().join(' ');

      devices.add(
        TvosDevice(
          udid,
          name: name,
          logger: logger,
          isSimulator: false,
          osVersion: osVersion.isEmpty ? null : osVersion,
        ),
      );
    }

    return devices;
  }
}
