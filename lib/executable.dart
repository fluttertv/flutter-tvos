// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools/runner.dart' as runner;
import 'package:flutter_tools/src/android/android_workflow.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/build_system/build_targets.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/assemble.dart';
import 'package:flutter_tools/src/commands/channel.dart';
import 'package:flutter_tools/src/commands/config.dart';
import 'package:flutter_tools/src/commands/daemon.dart';
import 'package:flutter_tools/src/commands/debug_adapter.dart';
import 'package:flutter_tools/src/commands/doctor.dart';
import 'package:flutter_tools/src/commands/downgrade.dart';
import 'package:flutter_tools/src/commands/emulators.dart';
import 'package:flutter_tools/src/commands/generate.dart';
import 'package:flutter_tools/src/commands/generate_localizations.dart';
import 'package:flutter_tools/src/commands/install.dart';
import 'package:flutter_tools/src/commands/logs.dart';
import 'package:flutter_tools/src/commands/packages.dart';
import 'package:flutter_tools/src/commands/screenshot.dart';
import 'package:flutter_tools/src/commands/shell_completion.dart';
import 'package:flutter_tools/src/commands/symbolize.dart';
import 'package:flutter_tools/src/commands/update_packages.dart';
import 'package:flutter_tools/src/commands/upgrade.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/build_targets.dart';
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/macos/macos_workflow.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/windows/windows_workflow.dart';
import 'package:path/path.dart';

import 'commands/attach.dart';
import 'commands/build.dart';
import 'commands/clean.dart';
import 'commands/create.dart';
import 'commands/devices.dart';
import 'commands/drive.dart';
import 'commands/precache.dart';
import 'commands/run.dart';
import 'commands/test.dart';
import 'tvos_application_package.dart';
import 'tvos_artifacts.dart';
import 'tvos_cache.dart';
import 'tvos_device_discovery.dart';
import 'tvos_doctor.dart';
import 'tvos_logger.dart';

/// Main entry point for commands.
///
/// Source: `flutter.main` in `executable.dart` (some commands and options were omitted)
Future<void> main(List<String> args) async {
  final bool veryVerbose = args.contains('-vv');
  final bool verbose = args.contains('-v') || args.contains('--verbose') || veryVerbose;

  final bool doctor =
      (args.isNotEmpty && args.first == 'doctor') ||
      (args.length == 2 && verbose && args.last == 'doctor');
  final bool help =
      args.contains('-h') ||
      args.contains('--help') ||
      (args.isNotEmpty && args.first == 'help') ||
      (args.length == 1 && verbose);
  final bool muteCommandLogging = (help || doctor) && !veryVerbose;
  final bool verboseHelp = help && verbose;

  args = <String>[
    '--suppress-analytics', // Suppress flutter analytics by default.
    '--no-version-check',
    ...args,
  ];

  Cache.flutterRoot = join(rootPath, 'flutter');

  await runner.run(
    args,
    () => <FlutterCommand>[
      // Commands forwarded directly from flutter_tools — these have no
      // tvOS-specific behaviour, so we register them as-is. Anything we
      // do NOT register here would print "Could not find a command named
      // X" on `flutter-tvos X`, even though plain `flutter X` works.
      AssembleCommand(verboseHelp: verboseHelp, buildSystem: globals.buildSystem),
      ChannelCommand(verboseHelp: verboseHelp),
      ConfigCommand(verboseHelp: verboseHelp),
      DaemonCommand(hidden: !verboseHelp),
      DebugAdapterCommand(verboseHelp: verboseHelp),
      DoctorCommand(verbose: verbose),
      DowngradeCommand(verboseHelp: verboseHelp, logger: globals.logger),
      EmulatorsCommand(),
      GenerateCommand(),
      GenerateLocalizationsCommand(
        fileSystem: globals.fs,
        logger: globals.logger,
        artifacts: globals.artifacts!,
        processManager: globals.processManager,
      ),
      InstallCommand(verboseHelp: verboseHelp),
      LogsCommand(sigint: ProcessSignal.sigint, sigterm: ProcessSignal.sigterm),
      // Upstream `pub` (and its alias `packages`) — registers `pub get`,
      // `pub upgrade`, `pub add`, `pub remove`, `pub publish`, `pub
      // outdated`, `pub deps`, `pub cache`, `pub run`, `pub global`,
      // `pub token`. Without this, `flutter-tvos pub get` fails with
      // "Could not find a command named 'pub'" — an invisible regression
      // because the `flutter test` / `flutter run` pre-step runs pub-get
      // internally, so users only notice when they invoke pub directly.
      PackagesCommand(),
      ScreenshotCommand(fs: globals.fs),
      ShellCompletionCommand(),
      SymbolizeCommand(stdio: globals.stdio, fileSystem: globals.fs),
      UpdatePackagesCommand(verboseHelp: verboseHelp),
      UpgradeCommand(verboseHelp: verboseHelp),
      // Commands extended for tvOS.
      TvosAttachCommand(
        verboseHelp: verboseHelp,
        stdio: globals.stdio,
        logger: globals.logger,
        terminal: globals.terminal,
        signals: globals.signals,
        platform: globals.platform,
        processInfo: globals.processInfo,
        fileSystem: globals.fs,
      ),
      TvosBuildCommand(
        fileSystem: globals.fs,
        buildSystem: globals.buildSystem,
        osUtils: globals.os,
        logger: globals.logger,
        androidSdk: globals.androidSdk,
        verboseHelp: verboseHelp,
      ),
      TvosCleanCommand(verbose: verbose),
      TvosCreateCommand(verboseHelp: verboseHelp),
      TvosDevicesCommand(verboseHelp: verboseHelp),
      TvosDriveCommand(
        verboseHelp: verboseHelp,
        fileSystem: globals.fs,
        logger: globals.logger,
        platform: globals.platform,
        signals: globals.signals,
        terminal: globals.terminal,
        outputPreferences: globals.outputPreferences,
      ),
      TvosPrecacheCommand(
        verboseHelp: verboseHelp,
        cache: globals.cache,
        logger: globals.logger,
        platform: globals.platform,
        featureFlags: featureFlags,
      ),
      TvosRunCommand(verboseHelp: verboseHelp),
      TvosTestCommand(verboseHelp: verboseHelp),
    ],
    verbose: verbose,
    verboseHelp: verboseHelp,
    muteCommandLogging: muteCommandLogging,
    reportCrashes: false,
    overrides: <Type, Generator>{
      ApplicationPackageFactory: () => TvosApplicationPackageFactory(),
      BuildTargets: () => const BuildTargetsImpl(),
      Cache: () => TvosFlutterCache(
        fileSystem: globals.fs,
        logger: globals.logger,
        platform: globals.platform,
        osUtils: globals.os,
        projectFactory: globals.projectFactory,
        processManager: globals.processManager,
      ),
      TemplateRenderer: () => const MustacheTemplateRenderer(),
      Artifacts: () => TvosArtifacts(
        fileSystem: globals.fs,
        cache: globals.cache,
        platform: globals.platform,
        operatingSystemUtils: globals.os,
      ),
      DoctorValidatorsProvider: () => TvosDoctorValidatorsProvider(),
      TvosWorkflow: () => TvosWorkflow(operatingSystemUtils: globals.os),
      DeviceManager: () => TvosDeviceManager(
        logger: globals.logger,
        processManager: globals.processManager,
        platform: globals.platform,
        androidSdk: globals.androidSdk,
        iosSimulatorUtils: globals.iosSimulatorUtils!,
        featureFlags: featureFlags,
        fileSystem: globals.fs,
        iosWorkflow: globals.iosWorkflow!,
        artifacts: globals.artifacts!,
        flutterVersion: globals.flutterVersion,
        androidWorkflow: AndroidWorkflow(
          androidSdk: globals.androidSdk,
          featureFlags: featureFlags,
        ),
        xcDevice: globals.xcdevice!,
        userMessages: globals.userMessages,
        windowsWorkflow: WindowsWorkflow(featureFlags: featureFlags, platform: globals.platform),
        macOSWorkflow: MacOSWorkflow(platform: globals.platform, featureFlags: featureFlags),
        operatingSystemUtils: globals.os,
        customDevicesConfig: globals.customDevicesConfig,
        nativeAssetsBuilder: globals.nativeAssetsBuilder,
        tvosWorkflow: tvosWorkflow!,
      ),
      TvosValidator: () => TvosValidator(processManager: globals.processManager),
      // Always wrap the logger with TvosCategoryRewritingLogger so the
      // device list shows `(tv)` instead of `(mobile)` for tvOS devices.
      // The wrapper is a no-op on every other line. In verbose mode,
      // VerboseLogger sits inside ours so timestamps still apply.
      Logger: () => TvosCategoryRewritingLogger(
        verbose && !muteCommandLogging
            ? VerboseLogger(
                StdoutLogger(
                  stdio: globals.stdio,
                  terminal: globals.terminal,
                  outputPreferences: globals.outputPreferences,
                ),
              )
            : StdoutLogger(
                stdio: globals.stdio,
                terminal: globals.terminal,
                outputPreferences: globals.outputPreferences,
              ),
      ),
    },
    shutdownHooks: globals.shutdownHooks,
  );
}

/// See: [Cache.defaultFlutterRoot] in `cache.dart`
String get rootPath {
  final String scriptPath = Platform.script.toFilePath();
  return normalize(join(scriptPath, scriptPath.endsWith('.snapshot') ? '../../..' : '../..'));
}
