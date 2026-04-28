// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Process;

import 'package:file/file.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/device_port_forwarder.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/ios/lldb.dart';
import 'package:flutter_tools/src/mdns_discovery.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/protocol_discovery.dart';
import 'package:flutter_tools/src/vmservice.dart';
import 'package:meta/meta.dart';

import 'tvos_application_package.dart';
import 'tvos_build_info.dart';
import 'tvos_builder.dart';

/// A log reader that captures logs from a physical tvOS device via devicectl.
///
/// Uses `xcrun devicectl device process launch --console` output or
/// `log stream` via devicectl to capture the VM service URL.
class TvosPhysicalDeviceLogReader implements DeviceLogReader {
  /// Creates a log reader for a physical tvOS device.
  ///
  /// [logger] is used for noise-filtered lines (demoted to printTrace). If
  /// omitted, falls back to the DI-injected [globals.logger] — safe for
  /// production use. Pass an explicit logger in unit tests to avoid needing
  /// a full Zone context.
  TvosPhysicalDeviceLogReader(this.name, {Logger? logger}) : _logger = logger;

  /// Logger for noise-filtered lines. Lazily resolved from globals so that
  /// production code doesn't need to pass it, but tests can inject explicitly.
  final Logger? _logger;
  Logger get _log => _logger ?? globals.logger;

  final StreamController<String> _linesController = StreamController<String>.broadcast();

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

    _logProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
      _processLine(line);
    });

    _logProcess!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
      _processLine(line);
    });
  }

  /// Launches the app on device (optionally paused with --start-stopped) and
  /// streams its console output as log lines. When `startStopped` is true the
  /// caller is responsible for attaching a debugger (lldb) to resume the
  /// process — JIT on tvOS 14+ requires this.
  Future<void> startLogStreamForBundle(
    String deviceId,
    String bundleId, {
    bool startStopped = false,
  }) async {
    // Wrap in `script -t 0 /dev/null` to convince devicectl it has a TTY and
    // forward child stdout. `--console` blocks the process until the app
    // exits, which is exactly what we want for a persistent log stream.
    final cmd = <String>[
      'script', '-t', '0', '/dev/null',
      'xcrun', 'devicectl', 'device', 'process', 'launch',
      '--device', deviceId,
      '--console',
      '--environment-variables', '{"OS_ACTIVITY_DT_MODE": "enable"}',
      if (startStopped) '--start-stopped',
      bundleId,
      // Launch arguments forwarded to the Flutter app's main(). These mirror
      // what flutter-iOS passes for a wirelessly-connected Core Device:
      // - vm-service-host=0.0.0.0 makes the Dart VM bind on every interface
      //   (default is loopback only, unreachable from the Mac).
      // - enable-dart-profiling so DevTools timeline is populated.
      // - disable-service-auth-codes drops the URL path token, making it
      //   easy to construct the final URI from mDNS host:port.
      '--enable-dart-profiling',
      '--disable-service-auth-codes',
      '--vm-service-host=0.0.0.0',
    ];
    _logProcess = await globals.processManager.start(cmd);

    _logProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
      _processLine(line);
    });

    _logProcess!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
      _processLine(line);
    });
  }

  // Lines we hide from the `flutter-tvos run` console because they're
  // implementation chatter (devicectl progress) or non-actionable system
  // framework warnings. Stock `flutter run` for iOS doesn't surface these,
  // so we shouldn't either. Verbose mode (`-v`) bypasses the filter via
  // printTrace.
  //
  // Devicectl progress chatter is timestamped like "07:49:03  Acquired ..."
  // and surrounding `script -t 0` adds "Script started/done" wrappers.
  // System log lines look like "2026-04-25 07:49:03.225578+0200 Runner[...]"
  // followed by a bracketed subsystem tag we want to drop.
  static final RegExp _devicectlProgress = RegExp(
    r'^\d{2}:\d{2}:\d{2}\s+(Acquired|Enabling|Establishing|Resolved|Granted)',
  );
  static final RegExp _scriptWrapper = RegExp(r'^Script (started|done), output file');
  static final RegExp _systemNoise = RegExp(
    r'\[(Scene|Storyboard|UIFocus|MetalLibInterposer|UIKitCore|FocusOverlay|FocusEffect)\]',
  );
  static final List<String> _verbatimNoise = <String>[
    'Launched application with',
    'Waiting for the application to terminate',
    'CLIENT OF UIKIT REQUIRES UPDATE',
  ];

  bool _isNoise(String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    if (_devicectlProgress.hasMatch(trimmed)) {
      return true;
    }
    if (_scriptWrapper.hasMatch(trimmed)) {
      return true;
    }
    if (_systemNoise.hasMatch(line)) {
      return true;
    }
    for (final String n in _verbatimNoise) {
      if (line.contains(n)) {
        return true;
      }
    }
    return false;
  }

  void _processLine(String line) {
    if (_linesController.isClosed) {
      return;
    }
    if (_isNoise(line)) {
      _log.printTrace(line);
      return;
    }
    _linesController.add(line);
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

  final StreamController<String> _linesController = StreamController<String>.broadcast();

  Process? _logProcess;

  @override
  final String name;

  @override
  Stream<String> get logLines => _linesController.stream;

  /// Starts streaming unified logs from the simulator, filtered for the app.
  Future<void> startLogStream(String deviceId) async {
    // Only capture logs from the Flutter framework. This gives us the VM service
    // URL and Dart print() output without all the system framework noise.
    const predicate = 'senderImagePath ENDSWITH "/Flutter"';

    _logProcess = await globals.processManager.start(<String>[
      'xcrun',
      'simctl',
      'spawn',
      deviceId,
      'log',
      'stream',
      '--style',
      'json',
      '--predicate',
      predicate,
    ]);

    _logProcess!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
      _onUnifiedLoggingLine(line);
    });

    _logProcess!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((
      String line,
    ) {
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
    this.osVersion,
  }) : super(
         category: Category.mobile,
         platformType: PlatformType.custom,
         ephemeral: true,
         logger: logger,
       );

  @override
  final String name;
  final Logger logger;
  final bool isSimulator;

  /// Human-readable OS version such as `tvOS 18.6 22M84` (physical) or
  /// `tvOS 18.4` (simulator). Used by [sdkNameAndVersion] so `flutter-tvos
  /// devices` shows the same version detail stock `flutter devices` does
  /// for iOS.
  final String? osVersion;

  DeviceLogReader? _logReader;
  LLDB? _lldb;
  LLDBLogForwarder? _lldbLogForwarder;

  @override
  Future<TargetPlatform> get targetPlatform async => TargetPlatform.ios;

  // Override the display name so `flutter-tvos devices` shows `tvos` in the
  // platform column instead of the inherited `ios`. The build pipeline still
  // sees `TargetPlatform.ios` (we ride on the iOS toolchain), but at the user
  // surface tvOS devices are clearly distinct.
  @override
  Future<String> get targetPlatformDisplayName async => 'tvos';

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> get isLocalEmulator async => isSimulator;

  @override
  Future<String?> get emulatorId async => isSimulator ? id : null;

  @override
  Future<String> get sdkNameAndVersion async => osVersion ?? 'tvOS';

  @override
  bool supportsRuntimeMode(BuildMode buildMode) => buildMode != BuildMode.jitRelease;

  @override
  Future<bool> isAppInstalled(covariant ApplicationPackage app, {String? userIdentifier}) async =>
      false;

  @override
  Future<bool> isLatestBuildInstalled(covariant ApplicationPackage app) async => false;

  @override
  Future<bool> installApp(covariant ApplicationPackage app, {String? userIdentifier}) async {
    final tvosApp = app as TvosApp;

    // Prefer Release bundle if present (device/release builds); fall back to Debug.
    String appPath = tvosApp.bundlePath(BuildMode.release, isSimulator: isSimulator);
    if (!globals.fs.directory(appPath).existsSync()) {
      appPath = tvosApp.bundlePath(BuildMode.debug, isSimulator: isSimulator);
    }

    if (isSimulator) {
      final RunResult result = await globals.processUtils.run(<String>[
        'xcrun',
        'simctl',
        'install',
        id,
        appPath,
      ]);
      if (result.exitCode != 0) {
        logger.printError('simctl install failed:\n${result.stderr}');
        return false;
      }
      return true;
    }

    // Physical device: use devicectl
    logger.printTrace('Installing on physical Apple TV ($id)...');

    final RunResult result = await globals.processUtils.run(<String>[
      'xcrun',
      'devicectl',
      'device',
      'install',
      'app',
      '--device',
      id,
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
        'xcrun',
        'simctl',
        'uninstall',
        id,
        app.id,
      ]);
      return result.exitCode == 0;
    }

    // Physical device: use devicectl to uninstall
    final RunResult result = await globals.processUtils.run(<String>[
      'xcrun',
      'devicectl',
      'device',
      'uninstall',
      'app',
      '--device',
      id,
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
      final tvosBuildInfo = TvosBuildInfo(
        debuggingOptions.buildInfo,
        targetArch: 'arm64',
        simulator: isSimulator,
      );

      logger.printTrace('Building tvOS application...');
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
    final configuration = debuggingOptions.buildInfo.isDebug ? 'Debug' : 'Release';
    final String appPath = globals.fs.path.join(
      project.directory.path,
      'build',
      'tvos',
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
    logger.printStatus('Installing and launching...');
    logger.printTrace('Installing on Apple TV simulator ($id)...');
    final RunResult installResult = await globals.processUtils.run(<String>[
      'xcrun',
      'simctl',
      'install',
      id,
      appPath,
    ]);
    if (installResult.exitCode != 0) {
      logger.printError('simctl install failed: ${installResult.stderr}');
      return LaunchResult.failed();
    }

    // 5. Determine bundle ID
    final String bundleId = package?.id ?? _readBundleId(project);

    // 6. Start log stream BEFORE launching so we don't miss the VM service URL
    logger.printTrace('Launching $bundleId on Apple TV...');
    final logReader = (_logReader ??= TvosSimulatorLogReader(name)) as TvosSimulatorLogReader;
    await logReader.startLogStream(id);

    // 7. Launch the app
    final RunResult launchResult = await globals.processUtils.run(<String>[
      'xcrun',
      'simctl',
      'launch',
      id,
      bundleId,
    ]);
    if (launchResult.exitCode != 0) {
      logger.printError('simctl launch failed: ${launchResult.stderr}');
      return LaunchResult.failed();
    }

    // 8. Discover VM service URI from unified log stream
    final discovery = ProtocolDiscovery.vmService(logReader, ipv6: false, logger: logger);

    final Uri? vmServiceUri = await discovery.uri.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    await discovery.cancel();

    if (vmServiceUri != null) {
      // HotRunner prints "A Dart VM Service on <device> is available at: ..."
      // and the DevTools URL itself once it has connected, so we only trace
      // here to avoid duplicating the line stock flutter doesn't print.
      logger.printTrace('VM service available at: $vmServiceUri');
      return LaunchResult.succeeded(vmServiceUri: vmServiceUri);
    }

    return LaunchResult.succeeded();
  }

  Future<LaunchResult> _startAppOnDevice(
    FlutterProject project,
    ApplicationPackage? package,
    DebuggingOptions debuggingOptions,
  ) async {
    // 2. Determine app bundle path
    final configuration = debuggingOptions.buildInfo.isDebug ? 'Debug' : 'Release';
    final String appPath = globals.fs.path.join(
      project.directory.path,
      'build',
      'tvos',
      '$configuration-appletvos',
      'Runner.app',
    );

    if (!globals.fs.directory(appPath).existsSync()) {
      logger.printError('App bundle not found at: $appPath');
      return LaunchResult.failed();
    }

    // 3. Install app on physical device
    logger.printStatus('Installing and launching...');
    logger.printTrace('Installing on Apple TV ($id)...');
    final RunResult installResult = await globals.processUtils.run(<String>[
      'xcrun',
      'devicectl',
      'device',
      'install',
      'app',
      '--device',
      id,
      appPath,
    ]);
    logger.printTrace(installResult.stdout);
    if (installResult.exitCode != 0) {
      logger.printError('devicectl install failed: ${installResult.stderr}');
      return LaunchResult.failed();
    }

    // 4. Determine bundle ID
    final String bundleId = package?.id ?? _readBundleId(project);

    // tvOS LaunchServices needs a moment after install to index the new
    // bundle. Without this pause, the immediate `devicectl process launch`
    // fails with "application is not installed" even though the install just
    // reported success (launchServicesIdentifier in the install output is
    // "unknown" at this point, which is the giveaway). Poll until the app
    // shows up in `devicectl device info apps`, up to 15s.
    logger.printTrace('Waiting for $bundleId to register...');
    final bool appReady = await _waitForAppRegistration(id, bundleId);
    if (!appReady) {
      logger.printError(
        'Timed out waiting for $bundleId to register on the device. '
        'The app was installed but LaunchServices did not index it.',
      );
      return LaunchResult.failed();
    }

    // 5. Launch with console output to capture VM service URL.
    // Debug builds need JIT, which tvOS 14+ only allows when a debugger is
    // attached. Launch `--start-stopped`, then attach lldb (mirrors what
    // Xcode does) and resume the process.
    final bool needsDebugger = debuggingOptions.buildInfo.isDebug;
    logger.printTrace('Launching $bundleId on Apple TV...');
    final logReader =
        (_logReader ??= TvosPhysicalDeviceLogReader(name)) as TvosPhysicalDeviceLogReader;
    await logReader.startLogStreamForBundle(id, bundleId, startStopped: needsDebugger);

    if (needsDebugger) {
      final int? pid = await _findAppPid(id, bundleId);
      if (pid == null) {
        logger.printError(
          'Could not find the launched process on the device. '
          'lldb attach skipped; debug-mode JIT will fail.',
        );
        return LaunchResult.failed();
      }
      logger.printTrace('Attaching lldb to pid $pid for JIT debugging...');
      final LLDBLogForwarder lldbForwarder = _lldbLogForwarder ??= LLDBLogForwarder();
      lldbForwarder.logLines.listen((String line) {
        logger.printTrace('[lldb] $line');
      });
      final LLDB lldb = _lldb ??= LLDB(logger: logger, processUtils: globals.processUtils);
      final bool attached = await lldb.attachAndStart(
        deviceId: id,
        appProcessId: pid,
        lldbLogForwarder: lldbForwarder,
      );
      if (!attached) {
        logger.printError('lldb failed to attach; debug-mode JIT will fail.');
        return LaunchResult.failed();
      }
    }

    // 6. Discover the Mac-reachable VM service URI. Two paths run in parallel:
    //    a) ProtocolDiscovery scans the console stream and finds the loopback
    //       URL (e.g. http://127.0.0.1:52281/) printed by the Dart VM. That
    //       host isn't reachable from the Mac, but the port is real.
    //    b) MDnsVmServiceDiscovery looks for the `_dartVmService._tcp.local`
    //       Bonjour record the Dart VM publishes, which gives us the device's
    //       LAN IP and the same port. With --vm-service-host=0.0.0.0 set on
    //       the launch line, this URL IS reachable from the Mac.
    //    We prefer (b). If mDNS fails but (a) succeeded, we substitute the
    //    device IP we resolved separately so DevTools can still connect.
    final discovery = ProtocolDiscovery.vmService(logReader, ipv6: false, logger: logger);

    Uri? vmServiceUri = await discovery.uri.timeout(
      const Duration(seconds: 30),
      onTimeout: () => null,
    );
    await discovery.cancel();

    if (vmServiceUri != null &&
        (vmServiceUri.host == '127.0.0.1' || vmServiceUri.host == '0.0.0.0')) {
      // Console URL host is unreachable from the Mac. Use mDNS to find the
      // device's LAN address by matching the port we just discovered (the
      // SRV target name doesn't match our Device.name verbatim — it's the
      // hardware-suffixed Bonjour name like `Bedroom-C4F7C15554D7.local.`,
      // so we skip the deviceName filter and rely on the port).
      final int devicePort = vmServiceUri.port;
      final String authPath = vmServiceUri.path;
      try {
        // `queryForLaunch` is annotated `@visibleForTesting` upstream, but it
        // is the only iOS-mDNS code path that handles paired-but-LAN-resolved
        // Apple TVs (where devicectl reports the loopback URL but the host
        // can only reach the device by its `*.coredevice.local` Bonjour name).
        // Stock Flutter's iOS device manager calls it the same way for the
        // physical device flow.
        final MDnsVmServiceDiscoveryResult? result =
            // ignore: invalid_use_of_visible_for_testing_member
            await MDnsVmServiceDiscovery.instance!.queryForLaunch(
              applicationId: bundleId,
              deviceVmservicePort: devicePort,
              useDeviceIPAsHost: true,
              timeout: const Duration(seconds: 10),
            );
        if (result != null && result.ipAddress != null) {
          vmServiceUri = Uri(
            scheme: 'http',
            host: result.ipAddress!.address,
            port: result.port,
            path: authPath,
          );
        } else {
          // Fallback: use devicectl hostname (e.g. bedroom.coredevice.local).
          // Only useful if Bonjour is reachable from the Mac.
          final String? deviceIp = await _resolveDeviceIp(id);
          if (deviceIp != null) {
            vmServiceUri = vmServiceUri.replace(host: deviceIp);
          }
        }
      } on Object catch (e) {
        logger.printTrace('mDNS lookup failed: $e');
      }
    }

    if (vmServiceUri != null) {
      // Suppressed: HotRunner prints the user-facing VM service + DevTools
      // URLs once it has connected, matching stock `flutter run`.
      logger.printTrace('VM service available at: $vmServiceUri');
      return LaunchResult.succeeded(vmServiceUri: vmServiceUri);
    }

    return LaunchResult.succeeded();
  }

  /// Asks devicectl for the device's network IP. Used as a fallback when
  /// mDNS discovery fails — we still want to give DevTools a reachable URL
  /// instead of the loopback one printed by the Dart VM.
  Future<String?> _resolveDeviceIp(String deviceId) async {
    final Directory tmp = globals.fs.systemTempDirectory.createTempSync('devicectl_ip.');
    try {
      final File out = tmp.childFile('device.json');
      final RunResult r = await globals.processUtils.run(<String>[
        'xcrun',
        'devicectl',
        'list',
        'devices',
        '--json-output',
        out.path,
      ]);
      if (r.exitCode != 0 || !out.existsSync()) {
        return null;
      }
      try {
        final dynamic decoded = jsonDecode(out.readAsStringSync());
        final dynamic devices = (decoded is Map && decoded['result'] is Map)
            ? (decoded['result'] as Map)['devices']
            : null;
        if (devices is! List) {
          return null;
        }
        for (final Object? d in devices) {
          if (d is! Map) {
            continue;
          }
          final dynamic hp = d['hardwareProperties'];
          final dynamic identifier = d['identifier'];
          if (identifier != deviceId) {
            continue;
          }
          final dynamic conn = d['connectionProperties'];
          if (conn is Map) {
            // Prefer numeric IPv4 from networkAddresses if present.
            final dynamic netAddrs = conn['networkAddresses'];
            if (netAddrs is List) {
              for (final Object? a in netAddrs) {
                if (a is String && RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(a)) {
                  return a;
                }
              }
            }
            // devicectl exposes mDNS-resolvable hostnames like
            // "Bedroom.coredevice.local" under potentialHostnames. Pick the
            // shortest (friendliest) one — the udid-based hostname is also
            // valid but less readable.
            final dynamic hostnames = conn['potentialHostnames'];
            if (hostnames is List) {
              String? best;
              for (final Object? h in hostnames) {
                if (h is! String) {
                  continue;
                }
                if (!h.endsWith('.coredevice.local')) {
                  continue;
                }
                if (best == null || h.length < best.length) {
                  best = h;
                }
              }
              if (best != null) {
                return best;
              }
            }
            // localHostnames as a last resort.
            final dynamic addrs = conn['localHostnames'];
            if (addrs is List && addrs.isNotEmpty) {
              for (final Object? h in addrs) {
                if (h is String && h.endsWith('.local')) {
                  return h;
                }
              }
            }
          }
          if (hp is Map && hp['address'] is String) {
            return hp['address'] as String;
          }
        }
      } on FormatException {
        return null;
      }
      return null;
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        /* ignore */
      }
    }
  }

  /// Polls `devicectl device info processes` until a process whose executable
  /// lives inside a bundle matching [bundleId] appears, returning its pid.
  /// Needed after `--start-stopped` so we can hand the pid to lldb.
  Future<int?> _findAppPid(
    String deviceId,
    String bundleId, {
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    // First look up the bundle's installation URL so we can match the
    // process's executable path against it.
    String? installUrl;
    {
      final Directory tmp = globals.fs.systemTempDirectory.createTempSync('devicectl_url.');
      try {
        final File out = tmp.childFile('apps.json');
        final RunResult r = await globals.processUtils.run(<String>[
          'xcrun',
          'devicectl',
          'device',
          'info',
          'apps',
          '--device',
          deviceId,
          '--json-output',
          out.path,
        ]);
        if (r.exitCode == 0 && out.existsSync()) {
          try {
            final dynamic decoded = jsonDecode(out.readAsStringSync());
            final dynamic apps = (decoded is Map && decoded['result'] is Map)
                ? (decoded['result'] as Map)['apps']
                : null;
            if (apps is List) {
              for (final Object? a in apps) {
                if (a is Map && a['bundleIdentifier'] == bundleId) {
                  final dynamic u = a['url'];
                  if (u is String) {
                    installUrl = u;
                  }
                  break;
                }
              }
            }
          } on FormatException {
            /* ignore */
          }
        }
      } finally {
        try {
          tmp.deleteSync(recursive: true);
        } on FileSystemException {
          /* ignore */
        }
      }
    }
    if (installUrl == null) {
      return null;
    }

    final sw = Stopwatch()..start();
    final Directory tmp = globals.fs.systemTempDirectory.createTempSync('devicectl_ps.');
    try {
      while (sw.elapsed < timeout) {
        final File out = tmp.childFile('ps.json');
        if (out.existsSync()) {
          out.deleteSync();
        }
        final RunResult r = await globals.processUtils.run(<String>[
          'xcrun',
          'devicectl',
          'device',
          'info',
          'processes',
          '--device',
          deviceId,
          '--json-output',
          out.path,
        ]);
        if (r.exitCode == 0 && out.existsSync()) {
          try {
            final dynamic decoded = jsonDecode(out.readAsStringSync());
            final dynamic procs = (decoded is Map && decoded['result'] is Map)
                ? (decoded['result'] as Map)['runningProcesses']
                : null;
            if (procs is List) {
              for (final Object? p in procs) {
                if (p is Map) {
                  final dynamic exe = p['executable'];
                  final dynamic pid = p['processIdentifier'];
                  if (exe is String &&
                      pid is int &&
                      exe.contains(installUrl.replaceFirst('file://', ''))) {
                    return pid;
                  }
                }
              }
            }
          } on FormatException {
            /* ignore */
          }
        }
        await Future<void>.delayed(pollInterval);
      }
      return null;
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        /* ignore */
      }
    }
  }

  /// Polls `devicectl device info apps` until the given bundle ID shows up
  /// or the timeout expires. After `devicectl device install app` returns
  /// successfully, the app is copied to the device but LaunchServices still
  /// has to index it — during that gap, `devicectl process launch` fails
  /// spuriously with "application is not installed".
  Future<bool> _waitForAppRegistration(
    String deviceId,
    String bundleId, {
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    final sw = Stopwatch()..start();
    var attempts = 0;
    final Directory tmp = globals.fs.systemTempDirectory.createTempSync('devicectl_apps.');
    try {
      while (sw.elapsed < timeout) {
        attempts++;
        final File jsonOut = tmp.childFile('apps_$attempts.json');
        final RunResult result = await globals.processUtils.run(<String>[
          'xcrun',
          'devicectl',
          'device',
          'info',
          'apps',
          '--device',
          deviceId,
          '--json-output',
          jsonOut.path,
        ]);
        var found = false;
        var bodyLen = -1;
        final bool fileExists = jsonOut.existsSync();
        if (fileExists) {
          final String body = jsonOut.readAsStringSync();
          bodyLen = body.length;
          try {
            final dynamic decoded = jsonDecode(body);
            final dynamic apps = (decoded is Map && decoded['result'] is Map)
                ? (decoded['result'] as Map)['apps']
                : null;
            if (apps is List) {
              for (final Object? app in apps) {
                if (app is Map && app['bundleIdentifier'] == bundleId) {
                  found = true;
                  break;
                }
              }
            }
          } on FormatException {
            // JSON not ready yet.
          }
        }
        globals.logger.printTrace(
          '  [attempt $attempts] exit=${result.exitCode} '
          'fileExists=$fileExists bodyLen=$bodyLen found=$found '
          'jsonPath=${jsonOut.path}',
        );
        if (found) {
          return true;
        }
        await Future<void>.delayed(pollInterval);
      }
      return false;
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort cleanup; tempdir may already be gone.
      }
    }
  }

  /// Reads PRODUCT_BUNDLE_IDENTIFIER from the tvOS project.pbxproj.
  String _readBundleId(FlutterProject project) {
    final String pbxprojPath = globals.fs.path.join(
      project.directory.path,
      'tvos',
      'Runner.xcodeproj',
      'project.pbxproj',
    );
    final File file = globals.fs.file(pbxprojPath);
    if (file.existsSync()) {
      final String content = file.readAsStringSync();
      final regex = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(.*?);');
      final Match? match = regex.firstMatch(content);
      if (match != null) {
        String? id = match.group(1)?.trim();
        if (id != null && id.length >= 2 && id.startsWith('"') && id.endsWith('"')) {
          id = id.substring(1, id.length - 1);
        }
        if (id != null && !id.contains('RunnerTests')) {
          return id;
        }
      }
    }
    return 'com.example.${project.directory.basename.replaceAll('-', '_')}';
  }

  @override
  Future<bool> stopApp(covariant ApplicationPackage? app, {String? userIdentifier}) async {
    if (app == null) {
      return false;
    }

    _logReader?.dispose();
    _logReader = null;
    _lldb?.exit();
    _lldb = null;
    unawaited(_lldbLogForwarder?.exit());
    _lldbLogForwarder = null;

    if (isSimulator) {
      final RunResult result = await globals.processUtils.run(<String>[
        'xcrun',
        'simctl',
        'terminate',
        id,
        app.id,
      ]);
      return result.exitCode == 0;
    }

    // Physical device: terminate by bundle identifier. devicectl's terminate
    // subcommand requires a real PID, which we don't track here — fall back to
    // killing the launch console session (which unlocks the app) and consider
    // that success. A follow-up `devicectl device process launch` would replace it.
    // The log reader dispose() above already terminates the launch console.
    return true;
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
