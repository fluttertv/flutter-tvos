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
import 'package:flutter_tools/src/ios/xcode_debug.dart';
import 'package:flutter_tools/src/macos/xcode.dart';
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
    r'\[(Scene|Storyboard|UIFocus|UIKitCore|FocusOverlay|'
    r'FocusEffect|PreviewsAgentExecutorLibrary)\]',
  );
  // The OS hang tracker self-suppresses while the debugger is attached, but
  // still emits a one-line breadcrumb. Drop the breadcrumb — if there were a
  // genuine hang the user wants to see, it would be reported (no debugger
  // attached → different message without this suffix).
  static final RegExp _benignHangDetected = RegExp(
    r'Hang detected:.*\(debugger attached, not reporting\)',
  );
  // BackBoardServices asks the app for a snapshot when it goes to background
  // (used for the app switcher thumbnail / suspended-state preview).
  // Flutter apps don't expose a synchronous UIKit view hierarchy for BBS to
  // snapshot, so the request always fails with `response-not-possible`. The
  // failure is harmless — the app continues to run and the OS just shows a
  // generic placeholder thumbnail. Logged on every background transition.
  static final RegExp _backboardSnapshotFailure = RegExp(
    r'\[Common\] Snapshot request 0x[0-9a-fA-F]+ complete with error:.*'
    r'BSActionErrorDomain.*response-not-possible',
  );
  static final List<String> _verbatimNoise = <String>[
    'Launched application with',
    'Waiting for the application to terminate',
    'CLIENT OF UIKIT REQUIRES UPDATE',
    // tvOS state-restoration trying to write a marker for an app that doesn't
    // explicitly opt into restoration. Self-recoverable and cosmetic.
    'Unable to create restoration in progress marker file',
    // System cache layer (asset/font cache) not finding its data file on
    // first launch and rebuilding it. The "Invalidating cache..." line is
    // the recovery, not a failure.
    'fopen failed for data file:',
    'Errors found! Invalidating cache...',
    // Apple's GameController.framework misreads the Siri Remote axis
    // descriptor on every launch. Bug present in every tvOS app, including
    // Apple's own — we just don't want it in the user's terminal.
    'Axis min is a CFBoolean but expected a CFNumber',
    // Companion line the kernel emits before/after the hang breadcrumb
    // we already filter via _benignHangDetected. Same self-suppress
    // signal — fires on every launch, hot reload, and hot restart while
    // the debugger is attached.
    'App is being debugged, do not track this hang',
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
    if (_benignHangDetected.hasMatch(line)) {
      return true;
    }
    if (_backboardSnapshotFailure.hasMatch(line)) {
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
  XcodeDebug? _xcodeDebug;

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
    //
    // The install URL we get here is reused for `_findAppPid` below — it
    // saves an otherwise-redundant `devicectl info apps` round-trip that
    // would have happened immediately after this one.
    logger.printTrace('Waiting for $bundleId to register...');
    final String? installUrl = await _waitForAppRegistration(id, bundleId);
    if (installUrl == null) {
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
    // Debug mode on a physical Apple TV ALWAYS needs a debugger: the engine's
    // ptrace_check (`ptrace(PT_TRACE_ME)`) refuses to create a FlutterEngine in
    // debug mode unless the process is traced, and lldb is the only tracer
    // available via the tooling on tvOS. So `enable-lldb-debugging: false` is
    // NOT honoured here — without lldb the app aborts with "Cannot create a
    // FlutterEngine instance in debug mode". For fast, lldb-free debug
    // iteration use the tvOS *simulator* (JIT works there without a debugger).
    final bool needsDebugger = debuggingOptions.buildInfo.isDebug;
    logger.printTrace('Launching $bundleId on Apple TV...');
    final logReader =
        (_logReader ??= TvosPhysicalDeviceLogReader(name)) as TvosPhysicalDeviceLogReader;
    await logReader.startLogStreamForBundle(id, bundleId, startStopped: needsDebugger);

    if (needsDebugger) {
      // Path 1: lldb (fast when it works). On a USB-attached Apple TV this is
      // reliable; over a wireless tunnel the attach can stall or drop the
      // CoreDevice connection.
      var attached = false;
      final int? pid = await _findAppPid(id, bundleId, installUrl: installUrl);
      if (pid != null) {
        logger.printTrace('Attaching lldb to pid $pid for JIT debugging...');
        final LLDBLogForwarder lldbForwarder = _lldbLogForwarder ??= LLDBLogForwarder();
        lldbForwarder.logLines.listen((String line) {
          logger.printTrace('[lldb] $line');
        });
        final LLDB lldb = _lldb ??= LLDB(logger: logger, processUtils: globals.processUtils);
        // lldb.attachAndStart only prints a "taking longer than expected"
        // *warning* after 60s — it never gives up on its own. Over a wireless
        // tunnel the attach routinely hangs forever, so cap it ourselves and
        // hand off to the Xcode debugger when it doesn't attach in time. (USB
        // attaches in a few seconds, well under this.)
        attached = await lldb
            .attachAndStart(
              deviceId: id,
              appProcessId: pid,
              lldbLogForwarder: lldbForwarder,
              mode: debuggingOptions.buildInfo.mode,
            )
            .timeout(
              const Duration(seconds: 75),
              onTimeout: () {
                logger.printTrace('lldb attach timed out after 75s; falling back.');
                return false;
              },
            );
      }

      if (!attached) {
        // Path 2: Xcode debugger fallback — the same path stock Flutter uses
        // for iOS Core Devices (devices.dart `_startAppOnCoreDevice`), and the
        // mechanism Xcode itself uses to reliably debug a wirelessly-paired
        // Apple TV. Tear down our devicectl launch + lldb first so Xcode can
        // take the device over cleanly, then let Xcode install/launch/attach.
        logger.printStatus(
          'lldb debugging did not attach — falling back to the Xcode debugger. '
          'You may be prompted to allow controlling Xcode '
          '(Settings ▸ Privacy & Security ▸ Automation).',
        );
        await _teardownDeviceLaunch();
        final bool xcodeStarted = await _launchViaXcodeDebugger(
          project: project,
          debuggingOptions: debuggingOptions,
        );
        if (!xcodeStarted) {
          logger.printError('Failed to start a debug session on the device.');
          return LaunchResult.failed();
        }
        // Xcode launched the app; its console output isn't routed through our
        // log reader, so resolve the VM Service purely via mDNS (Bonjour) using
        // the device's LAN IP — exactly how stock iOS resolves it for wireless.
        //
        // This can throwToolExit (multiple Dart VM services on the LAN, or
        // denied macOS Local Network permission). The app is already running
        // under the Xcode debugger at this point, so a throw escaping here would
        // crash `run` and leave that debug session attached with no teardown.
        // Catch it and degrade gracefully to a launched-but-no-hot-reload
        // result with an actionable warning (see below).
        Uri? xcodeUri;
        try {
          xcodeUri = await MDnsVmServiceDiscovery.instance!.getVMServiceUriForAttach(
            bundleId,
            this,
            useDeviceIPAsHost: true,
            timeout: const Duration(seconds: 60),
          );
        } on Object catch (e) {
          logger.printTrace('mDNS VM Service lookup failed: $e');
        }
        if (xcodeUri != null) {
          logger.printTrace('VM service (via Xcode + mDNS) available at: $xcodeUri');
          return LaunchResult.succeeded(vmServiceUri: xcodeUri);
        }
        // Returning succeeded() with no vmServiceUri makes the resident runner
        // report success while hot reload / DevTools silently do nothing — warn
        // so the user isn't left with a mute, broken-feeling session.
        logger.printWarning(
          'App launched via Xcode, but its Dart VM Service was not found over '
          'mDNS within 60s — hot reload, hot restart, and DevTools will be '
          'unavailable. Check that this Mac has Local Network permission '
          '(System Settings ▸ Privacy & Security ▸ Local Network) and that the '
          'Apple TV is on the same network.',
        );
        return LaunchResult.succeeded();
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

    // The app is installed and launched, but we never resolved a reachable VM
    // Service URI — returning a bare succeeded() makes the runner report success
    // while hot reload / DevTools silently do nothing. Tell the user why.
    logger.printWarning(
      'App launched, but its Dart VM Service was not found within the timeout — '
      'hot reload, hot restart, and DevTools will be unavailable. Check that '
      'this Mac has Local Network permission (System Settings ▸ Privacy & '
      'Security ▸ Local Network) and that the Apple TV is on the same network.',
    );
    return LaunchResult.succeeded();
  }

  /// Tears down the in-flight devicectl `--console` launch and lldb session so
  /// the Xcode debugger can take the device over cleanly. Killing the
  /// `--console` launch process (held by the log reader) terminates the
  /// `--start-stopped` app instance on the device.
  Future<void> _teardownDeviceLaunch() async {
    _lldb?.exit();
    _lldb = null;
    unawaited(_lldbLogForwarder?.exit());
    _lldbLogForwarder = null;
    _logReader?.dispose();
    _logReader = null;
  }

  /// Launches + debugs the app through Xcode (AppleScript automation), mirroring
  /// stock Flutter's iOS Core Device Xcode fallback
  /// (`IOSCoreDeviceLauncher.launchAppWithXcodeDebugger`). Xcode reliably
  /// establishes the debugserver connection to a wirelessly-paired Apple TV,
  /// which is what makes on-device debug + hot reload + DevTools work.
  Future<bool> _launchViaXcodeDebugger({
    required FlutterProject project,
    required DebuggingOptions debuggingOptions,
  }) async {
    final Directory tvosDir = project.directory.childDirectory('tvos');
    final Directory workspace = tvosDir.childDirectory('Runner.xcworkspace');
    final Directory xcodeproj = tvosDir.childDirectory('Runner.xcodeproj');
    if (!workspace.existsSync()) {
      logger.printError(
        'Xcode debugger fallback unavailable: ${workspace.path} not found. '
        'Run the app once so CocoaPods generates the workspace, or attach the '
        'Apple TV via USB for lldb debugging.',
      );
      return false;
    }

    // This fallback fires *because* something already went wrong (lldb didn't
    // attach), so don't compound it with a force-unwrap crash. On a box where
    // Xcode isn't selected (`xcode-select` → Command Line Tools, fresh CI),
    // `globals.xcode` is null; fail with an actionable message instead of a bare
    // "Null check operator used on a null value". Upstream IOSDevice passes the
    // nullable `globals.xcode` for the same reason.
    final Xcode? xcode = globals.xcode;
    if (xcode == null) {
      logger.printError(
        'Xcode is required for the wireless debug fallback but is not selected.\n'
        'Open Xcode once, or run '
        '`sudo xcode-select -s /Applications/Xcode.app`, '
        'or attach the Apple TV via USB for lldb debugging.',
      );
      return false;
    }

    final xcodeDebug = XcodeDebug(
      logger: logger,
      processManager: globals.processManager,
      xcode: xcode,
      fileSystem: globals.fs,
    );
    _xcodeDebug = xcodeDebug;

    // Ensure the Runner scheme has a debugger launch action (Xcode needs it to
    // attach the debugger when it runs the scheme). This is read-only
    // validation, but upstream `ensureXcodeDebuggerLaunchAction` throwToolExits
    // when the scheme's Run action doesn't select the LLDB debugger — guard it
    // so a misconfigured scheme returns false (→ "Failed to start a debug
    // session") instead of aborting the whole `run`.
    final File schemeFile = xcodeproj
        .childDirectory('xcshareddata')
        .childDirectory('xcschemes')
        .childFile('Runner.xcscheme');
    if (schemeFile.existsSync()) {
      try {
        xcodeDebug.ensureXcodeDebuggerLaunchAction(schemeFile);
      } on Object catch (e) {
        logger.printError(
          'Could not prepare the Runner scheme for debugging: $e\n'
          'Open tvos/Runner.xcodeproj in Xcode and make sure the Runner '
          "scheme's Run action uses the LLDB debugger.",
        );
        return false;
      }
    }

    // Build the Dart VM launch arguments the same way stock iOS does. Core
    // Devices are debugged through Xcode, so drop the ios-deploy-only flags.
    final List<String> launchArguments = debuggingOptions.getIOSLaunchArguments(
      EnvironmentType.physical,
      null,
      const <String, Object?>{},
      interfaceType: DeviceConnectionInterface.wireless,
    )..removeWhere(
        (String a) => a == '--enable-checked-mode' || a == '--verify-entry-points',
      );
    // tvOS wireless essentials (same flags our lldb/devicectl launch forces):
    // - bind the VM on every interface so the Mac can reach it over the LAN.
    // - drop the VM Service auth token so a bare host:port from mDNS connects
    //   (without this the connection is rejected: "ended too early").
    // - enable Dart profiling so DevTools' timeline works.
    for (final flag in <String>[
      '--vm-service-host=0.0.0.0',
      '--disable-service-auth-codes',
      '--enable-dart-profiling',
    ]) {
      if (!launchArguments.contains(flag)) {
        launchArguments.add(flag);
      }
    }

    final debugProject = XcodeDebugProject(
      scheme: 'Runner',
      xcodeWorkspace: workspace,
      xcodeProject: xcodeproj,
      hostAppProjectName: 'Runner',
      verboseLogging: logger.isVerbose,
    );

    // Xcode identifies devices by their hardware UDID (00008110-…), not the
    // CoreDevice identifier (a GUID) that `devicectl` and our [id] use. Resolve
    // and pass the UDID so Xcode can find the target device.
    final String? resolvedUdid = await _resolveDeviceUdid(id);
    if (resolvedUdid == null) {
      logger.printTrace(
        'Could not resolve a hardware UDID; passing the CoreDevice id "$id" to '
        'Xcode. If Xcode reports the device cannot be found, this is why.',
      );
    }
    final String xcodeDeviceId = resolvedUdid ?? id;

    return xcodeDebug.debugApp(
      project: debugProject,
      deviceId: xcodeDeviceId,
      launchArguments: launchArguments,
    );
  }

  /// Resolves the device's hardware UDID (`00008110-…`) from its CoreDevice
  /// identifier. Xcode's automation matches devices by UDID, not the GUID
  /// `devicectl` uses.
  Future<String?> _resolveDeviceUdid(String deviceId) async {
    final Directory tmp = globals.fs.systemTempDirectory.createTempSync('devicectl_udid.');
    try {
      final File out = tmp.childFile('info.json');
      final RunResult r = await globals.processUtils.run(<String>[
        'xcrun',
        'devicectl',
        'device',
        'info',
        'details',
        '--device',
        deviceId,
        '--json-output',
        out.path,
      ]);
      if (r.exitCode != 0 || !out.existsSync()) {
        logger.printTrace(
          'devicectl UDID lookup failed (exit ${r.exitCode}); '
          'falling back to the raw device id. stderr: ${r.stderr}',
        );
        return null;
      }
      final String? udid = parseDeviceUdid(out.readAsStringSync());
      if (udid == null) {
        logger.printTrace(
          'devicectl returned 0 but no result.hardwareProperties.udid was '
          'found (JSON shape may have changed); falling back to the raw id.',
        );
      }
      return udid;
    } on Object catch (e) {
      logger.printTrace('Failed to resolve device UDID: $e');
      return null;
    } finally {
      tmp.deleteSync(recursive: true);
    }
  }

  /// Extracts the hardware UDID (e.g. `00008110-00114D2E36F0A01E`) from the JSON
  /// emitted by `xcrun devicectl device info details --json-output`. Returns
  /// null if the JSON is malformed or has no `result.hardwareProperties.udid`.
  ///
  /// Xcode's automation identifies a device by this UDID, whereas `devicectl`
  /// and [id] use the CoreDevice identifier (a GUID).
  static String? parseDeviceUdid(String jsonOutput) {
    try {
      final dynamic decoded = jsonDecode(jsonOutput);
      final dynamic result = (decoded is Map) ? decoded['result'] : null;
      final dynamic hw = (result is Map) ? result['hardwareProperties'] : null;
      if (hw is Map && hw['udid'] is String) {
        return hw['udid'] as String;
      }
    } on FormatException {
      return null;
    }
    return null;
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
  ///
  /// [installUrl] is the `file://...Runner.app` path returned by
  /// [_waitForAppRegistration]. When supplied we skip the otherwise
  /// redundant `devicectl info apps` round-trip and go straight to the
  /// process listing — saves ~300–500 ms per debug launch.
  Future<int?> _findAppPid(
    String deviceId,
    String bundleId, {
    String? installUrl,
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    if (installUrl == null) {
      // Fallback path used when the caller doesn't already know the install
      // URL. Look it up via `devicectl info apps`.
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
  ///
  /// On success returns the install URL (e.g. `file:///private/var/...
  /// /Applications/.../Runner.app`). The caller forwards this to
  /// [_findAppPid] so we don't have to query `info apps` a second time
  /// just to translate the bundle id back into a path.
  ///
  /// LaunchServices typically indexes within 200–400 ms, so a 200 ms
  /// poll captures the registration on the first or second poll while
  /// adding negligible cost (~50 ms per `info apps` call).
  Future<String?> _waitForAppRegistration(
    String deviceId,
    String bundleId, {
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 200),
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
        String? foundUrl;
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
                  final dynamic url = app['url'];
                  // Some OS versions report `url: "unknown"` while indexing
                  // is still in progress — keep polling until we get a
                  // file:// URL we can match against process executables.
                  if (url is String && url.startsWith('file://')) {
                    foundUrl = url;
                  }
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
          'fileExists=$fileExists bodyLen=$bodyLen '
          'foundUrl=${foundUrl ?? "null"} jsonPath=${jsonOut.path}',
        );
        if (foundUrl != null) {
          return foundUrl;
        }
        await Future<void>.delayed(pollInterval);
      }
      return null;
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
    unawaited(_xcodeDebug?.exit());
    _xcodeDebug = null;

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
    // dispose() runs on abnormal teardown, `flutter-tvos attach` exit, and
    // hot-restart — paths where stopApp() may not fire. If the Xcode debugger
    // fallback was active, exit it here too so the osascript automation process
    // doesn't leak and the debug session doesn't stay attached on the device.
    unawaited(_xcodeDebug?.exit());
    _xcodeDebug = null;
  }
}
