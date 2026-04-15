// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Process;

import 'package:flutter_tools/src/application_package.dart';
import 'package:meta/meta.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/device_port_forwarder.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/protocol_discovery.dart';
import 'package:flutter_tools/src/vmservice.dart';

import 'tvos_application_package.dart';
import 'tvos_build_info.dart';
import 'tvos_builder.dart';

/// A log reader that captures logs from a physical tvOS device via devicectl.
///
/// Uses `xcrun devicectl device process launch --console` output or
/// `log stream` via devicectl to capture the VM service URL.
class TvosPhysicalDeviceLogReader implements DeviceLogReader {
  TvosPhysicalDeviceLogReader(this.name);

  final StreamController<String> _linesController =
      StreamController<String>.broadcast();

  Process? _logProcess;

  @override
  final String name;

  @override
  Stream<String> get logLines => _linesController.stream;

  /// Starts streaming logs from the physical device using `log stream` via devicectl.
  Future<void> startLogStream(String deviceId) async {
    _logProcess = await globals.processManager.start(<String>[
      'xcrun', 'devicectl', 'device', 'process', 'launch',
      '--terminate-existing',
      '--device', deviceId,
      '--console',
      // The bundle ID will be set separately when launching
    ]);

    _logProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      _processLine(line);
    });

    _logProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      _processLine(line);
    });
  }

  /// Attaches to a running process's log output.
  Future<void> startLogStreamForBundle(String deviceId, String bundleId) async {
    // Use syslog stream filtered for the app
    _logProcess = await globals.processManager.start(<String>[
      'xcrun', 'devicectl', 'device', 'process', 'launch',
      '--terminate-existing',
      '--console',
      '--device', deviceId,
      bundleId,
    ]);

    _logProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      _processLine(line);
    });

    _logProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      _processLine(line);
    });
  }

  void _processLine(String line) {
    if (!_linesController.isClosed) {
      _linesController.add(line);
    }
  }

  /// Processes a single line for testing.
  @visibleForTesting
  void processLogLine(String line) => _processLine(line);

  @override
  void dispose() {
    _logProcess?.kill();
    if (!_linesController.isClosed) {
      _linesController.close();
    }
  }

  @override
  Future<void> provideVmService(FlutterVmService connectedVmService) async {}
}

/// A log reader that captures logs from a tvOS simulator app via unified logging.
///
/// Uses `xcrun simctl spawn <device> log stream --style json` to capture
/// os_log output (where Flutter prints the VM service URL).
class TvosSimulatorLogReader implements DeviceLogReader {
  TvosSimulatorLogReader(this.name);

  final StreamController<String> _linesController =
      StreamController<String>.broadcast();

  Process? _logProcess;

  @override
  final String name;

  @override
  Stream<String> get logLines => _linesController.stream;

  /// Starts streaming unified logs from the simulator, filtered for the app.
  Future<void> startLogStream(String deviceId) async {
    // Only capture logs from the Flutter framework. This gives us the VM service
    // URL and Dart print() output without all the system framework noise.
    const String predicate = 'senderImagePath ENDSWITH "/Flutter"';

    _logProcess = await globals.processManager.start(<String>[
      'xcrun', 'simctl', 'spawn', deviceId,
      'log', 'stream', '--style', 'json', '--predicate', predicate,
    ]);

    _logProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      _onUnifiedLoggingLine(line);
    });

    _logProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      _onUnifiedLoggingLine(line);
    });
  }

  // Parse JSON-style unified log output to extract eventMessage.
  // Each log entry looks like: { ... "eventMessage" : "flutter: The Dart VM service is listening on ..." ... }
  static final RegExp _eventMessageRegex = RegExp(r'"eventMessage"\s*:\s*(".*?")');

  /// Processes a single line from the unified log stream.
  @visibleForTesting
  void processLogLine(String line) => _onUnifiedLoggingLine(line);

  void _onUnifiedLoggingLine(String line) {
    final Match? match = _eventMessageRegex.firstMatch(line);
    if (match != null) {
      final String rawMessage = match.group(1)!;
      try {
        final Object? decoded = jsonDecode(rawMessage);
        if (decoded is String && !_linesController.isClosed) {
          _linesController.add(decoded);
        }
      } on FormatException {
        // Non-JSON message, add raw
        if (!_linesController.isClosed) {
          _linesController.add(rawMessage);
        }
      }
    }
  }

  @override
  void dispose() {
    _logProcess?.kill();
    if (!_linesController.isClosed) {
      _linesController.close();
    }
  }

  @override
  Future<void> provideVmService(FlutterVmService connectedVmService) async {}
}

class TvosDevice extends Device {
  TvosDevice(
    super.id, {
    required this.name,
    required this.logger,
    required this.isSimulator,
  }) : super(
            category: Category.mobile,
            platformType: PlatformType.custom,
            ephemeral: true,
            logger: logger);

  @override
  final String name;
  final Logger logger;
  final bool isSimulator;

  DeviceLogReader? _logReader;

  @override
  Future<TargetPlatform> get targetPlatform async => TargetPlatform.ios;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> get isLocalEmulator async => isSimulator;

  @override
  Future<String?> get emulatorId async => isSimulator ? id : null;

  @override
  Future<String> get sdkNameAndVersion async => 'tvOS';

  @override
  bool supportsRuntimeMode(BuildMode buildMode) => buildMode != BuildMode.jitRelease;

  @override
  Future<bool> isAppInstalled(covariant ApplicationPackage app, {String? userIdentifier}) async => false;

  @override
  Future<bool> isLatestBuildInstalled(covariant ApplicationPackage app) async => false;

  @override
  Future<bool> installApp(covariant ApplicationPackage app, {String? userIdentifier}) async {
    final TvosApp tvosApp = app as TvosApp;

    if (isSimulator) {
      final String appPath = tvosApp.bundlePath(BuildMode.debug, isSimulator: true);
      final RunResult result = await globals.processUtils.run(<String>[
        'xcrun', 'simctl', 'install', id, appPath,
      ]);
      if (result.exitCode != 0) {
        logger.printError('simctl install failed:\n${result.stderr}');
        return false;
      }
      return true;
    }

    // Physical device: use devicectl
    final String appPath = tvosApp.bundlePath(BuildMode.release, isSimulator: false);
    logger.printStatus('Installing on physical Apple TV ($id)...');

    final RunResult result = await globals.processUtils.run(<String>[
      'xcrun', 'devicectl', 'device', 'install', 'app',
      '--device', id,
      appPath,
    ]);

    if (result.exitCode != 0) {
      logger.printError('devicectl install failed:\n${result.stderr}');
      return false;
    }
    return true;
  }

  @override
  Future<bool> uninstallApp(covariant ApplicationPackage app, {String? userIdentifier}) async {
    if (isSimulator) {
      final RunResult result = await globals.processUtils.run(<String>[
        'xcrun', 'simctl', 'uninstall', id, app.id,
      ]);
      return result.exitCode == 0;
    }

    // Physical device: use devicectl to uninstall
    final RunResult result = await globals.processUtils.run(<String>[
      'xcrun', 'devicectl', 'device', 'uninstall', 'app',
      '--device', id,
      app.id,
    ]);
    return result.exitCode == 0;
  }

  @override
  Future<LaunchResult> startApp(
    covariant ApplicationPackage? package, {
    String? mainPath,
    String? route,
    required DebuggingOptions debuggingOptions,
    Map<String, Object?> platformArgs = const <String, Object?>{},
    bool prebuiltApplication = false,
    String? userIdentifier,
  }) async {
    final FlutterProject project = FlutterProject.current();

    // 1. Build the tvOS app (unless prebuilt)
    if (!prebuiltApplication) {
      final TvosBuildInfo tvosBuildInfo = TvosBuildInfo(
        debuggingOptions.buildInfo,
        targetArch: 'arm64',
        simulator: isSimulator,
      );

      logger.printStatus('Building tvOS application...');
      await TvosBuilder.buildBundle(
        project: project,
        tvosBuildInfo: tvosBuildInfo,
        targetFile: mainPath ?? 'lib/main.dart',
      );
    }

    if (isSimulator) {
      return _startAppOnSimulator(project, package, debuggingOptions);
    } else {
      return _startAppOnDevice(project, package, debuggingOptions);
    }
  }

  Future<LaunchResult> _startAppOnSimulator(
    FlutterProject project,
    ApplicationPackage? package,
    DebuggingOptions debuggingOptions,
  ) async {
    // 2. Determine app bundle path
    final String configuration = debuggingOptions.buildInfo.isDebug ? 'Debug' : 'Release';
    final String appPath = globals.fs.path.join(
      project.directory.path,
      'build', 'tvos',
      '$configuration-appletvsimulator',
      'Runner.app',
    );

    if (!globals.fs.directory(appPath).existsSync()) {
      logger.printError('App bundle not found at: $appPath');
      return LaunchResult.failed();
    }

    // 3. Boot simulator and open Simulator.app window
    await globals.processUtils.run(<String>['xcrun', 'simctl', 'boot', id]);
    await globals.processUtils.run(<String>['open', '-a', 'Simulator']);

    // 4. Install app
    logger.printStatus('Installing on Apple TV simulator ($id)...');
    final RunResult installResult = await globals.processUtils.run(<String>[
      'xcrun', 'simctl', 'install', id, appPath,
    ]);
    if (installResult.exitCode != 0) {
      logger.printError('simctl install failed: ${installResult.stderr}');
      return LaunchResult.failed();
    }

    // 5. Determine bundle ID
    final String bundleId = package?.id ?? _readBundleId(project);

    // 6. Start log stream BEFORE launching so we don't miss the VM service URL
    logger.printStatus('Launching $bundleId on Apple TV...');
    final TvosSimulatorLogReader logReader =
        (_logReader ??= TvosSimulatorLogReader(name)) as TvosSimulatorLogReader;
    await logReader.startLogStream(id);

    // 7. Launch the app
    final RunResult launchResult = await globals.processUtils.run(<String>[
      'xcrun', 'simctl', 'launch', id, bundleId,
    ]);
    if (launchResult.exitCode != 0) {
      logger.printError('simctl launch failed: ${launchResult.stderr}');
      return LaunchResult.failed();
    }

    // 8. Discover VM service URI from unified log stream
    final ProtocolDiscovery discovery = ProtocolDiscovery.vmService(
      logReader,
      ipv6: false,
      logger: logger,
    );

    final Uri? vmServiceUri = await discovery.uri.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    await discovery.cancel();

    if (vmServiceUri != null) {
      logger.printStatus('VM service available at: $vmServiceUri');
      return LaunchResult.succeeded(vmServiceUri: vmServiceUri);
    }

    logger.printStatus('Application launched (VM service not found).');
    return LaunchResult.succeeded();
  }

  Future<LaunchResult> _startAppOnDevice(
    FlutterProject project,
    ApplicationPackage? package,
    DebuggingOptions debuggingOptions,
  ) async {
    // 2. Determine app bundle path
    final String configuration = debuggingOptions.buildInfo.isDebug ? 'Debug' : 'Release';
    final String appPath = globals.fs.path.join(
      project.directory.path,
      'build', 'tvos',
      '$configuration-appletvos',
      'Runner.app',
    );

    if (!globals.fs.directory(appPath).existsSync()) {
      logger.printError('App bundle not found at: $appPath');
      return LaunchResult.failed();
    }

    // 3. Install app on physical device
    logger.printStatus('Installing on Apple TV ($id)...');
    final RunResult installResult = await globals.processUtils.run(<String>[
      'xcrun', 'devicectl', 'device', 'install', 'app',
      '--device', id,
      appPath,
    ]);
    if (installResult.exitCode != 0) {
      logger.printError('devicectl install failed: ${installResult.stderr}');
      return LaunchResult.failed();
    }

    // 4. Determine bundle ID
    final String bundleId = package?.id ?? _readBundleId(project);

    // 5. Launch with console output to capture VM service URL
    logger.printStatus('Launching $bundleId on Apple TV...');
    final TvosPhysicalDeviceLogReader logReader =
        (_logReader ??= TvosPhysicalDeviceLogReader(name)) as TvosPhysicalDeviceLogReader;
    await logReader.startLogStreamForBundle(id, bundleId);

    // 6. Discover VM service URI from console output
    final ProtocolDiscovery discovery = ProtocolDiscovery.vmService(
      logReader,
      ipv6: false,
      logger: logger,
    );

    final Uri? vmServiceUri = await discovery.uri.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    await discovery.cancel();

    if (vmServiceUri != null) {
      logger.printStatus('VM service available at: $vmServiceUri');
      return LaunchResult.succeeded(vmServiceUri: vmServiceUri);
    }

    logger.printStatus('Application launched (VM service not found).');
    return LaunchResult.succeeded();
  }

  /// Reads PRODUCT_BUNDLE_IDENTIFIER from the tvOS project.pbxproj.
  String _readBundleId(FlutterProject project) {
    final String pbxprojPath = globals.fs.path.join(
      project.directory.path, 'tvos', 'Runner.xcodeproj', 'project.pbxproj',
    );
    final file = globals.fs.file(pbxprojPath);
    if (file.existsSync()) {
      final String content = file.readAsStringSync();
      final RegExp regex = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(.*?);');
      final Match? match = regex.firstMatch(content);
      if (match != null) {
        final String? id = match.group(1)?.trim();
        if (id != null && !id.contains('RunnerTests')) {
          return id;
        }
      }
    }
    return 'com.example.${project.directory.basename.replaceAll('-', '_')}';
  }

  @override
  Future<bool> stopApp(covariant ApplicationPackage? app, {String? userIdentifier}) async {
    if (app == null) return false;

    _logReader?.dispose();
    _logReader = null;

    if (isSimulator) {
      final RunResult result = await globals.processUtils.run(<String>[
        'xcrun', 'simctl', 'terminate', id, app.id,
      ]);
      return result.exitCode == 0;
    }

    // Physical device: use devicectl to send SIGTERM
    final RunResult result = await globals.processUtils.run(<String>[
      'xcrun', 'devicectl', 'device', 'process', 'terminate',
      '--device', id,
      '--pid', '0', // Will terminate by bundle ID below
    ]);
    // Fallback: devicectl doesn't have a clean "terminate by bundle" command,
    // but the log reader process kill will detach the console session
    return result.exitCode == 0;
  }

  @override
  void clearLogs() {}

  @override
  FutureOr<DeviceLogReader> getLogReader({
    covariant ApplicationPackage? app,
    bool includePastLogs = false,
  }) {
    if (isSimulator) {
      return _logReader ??= TvosSimulatorLogReader(name);
    }
    return _logReader ??= TvosPhysicalDeviceLogReader(name);
  }

  @override
  final DevicePortForwarder portForwarder = const NoOpDevicePortForwarder();

  @override
  bool get supportsScreenshot => false;

  @override
  bool isSupportedForProject(FlutterProject flutterProject) {
    return flutterProject.directory.childDirectory('tvos').existsSync();
  }

  @override
  Future<void> dispose() async {
    _logReader?.dispose();
  }
}
