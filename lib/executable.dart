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
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/build_targets.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/assemble.dart';
import 'package:flutter_tools/src/commands/config.dart';
import 'package:flutter_tools/src/commands/daemon.dart';
import 'package:flutter_tools/src/commands/debug_adapter.dart';
import 'package:flutter_tools/src/commands/doctor.dart';
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
import 'package:flutter_tools/src/context/android_context.dart';
import 'package:flutter_tools/src/context/apple_context.dart';
import 'package:flutter_tools/src/context/tool_context.dart';
import 'package:flutter_tools/src/context/tool_dependencies.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/emulator.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/hook_runner.dart' show FlutterHookRunner;
import 'package:flutter_tools/src/isolated/build_targets.dart';
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/macos/macos_workflow.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/windows/windows_workflow.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

import 'build_targets/tvos_hooks.dart' show TvosHookRunner;
import 'commands/attach.dart';
import 'commands/build.dart';
import 'commands/clean.dart';
import 'commands/create.dart';
import 'commands/devices.dart';
import 'commands/drive.dart';
import 'commands/plugin.dart';
import 'commands/precache.dart';
import 'commands/run.dart';
import 'commands/test.dart';
import 'commands/upgrade.dart';
import 'commands/use.dart';
import 'commands/versions.dart';
import 'tvos_application_package.dart';
import 'tvos_artifacts.dart';
import 'tvos_cache.dart';
import 'tvos_device_discovery.dart';
import 'tvos_doctor.dart';
import 'tvos_logger.dart';
import 'tvos_platform_args.dart';

/// The command set `flutter-tvos` exposes.
///
/// Named rather than inlined into [main] so a test can assert what is and is
/// not registered. `channel` being absent is load-bearing — stock
/// ChannelCommand resets --hard inside the vendored SDK and breaks the
/// flutter.version to engine-artifact pin — and nothing else in the suite
/// would notice it coming back.
///
/// Like stock `generateCommands` (Flutter 3.50 and later), it takes the
/// tool's [ToolDependencies] and hands each command the contexts and services
/// it uses. `runner.run` builds those dependencies from the tool's context, so
/// they carry the tvOS overrides [main] installs (cache, artifacts, device
/// manager, doctor validators, build targets, …).
///
/// No command is given the tool-extension managers stock passes (`doctor`,
/// `config`, `create`): tool extensions are experimental in this release of
/// Flutter, and a doctor given a manager builds stock's validator list, which
/// has no tvOS entry.
@visibleForTesting
List<FlutterCommand> tvosCommands({
  required ToolDependencies toolDependencies,
  required bool verbose,
  required bool verboseHelp,
}) {
  final ToolDependencies(
    :AndroidContext androidContext,
    :AppleContext appleContext,
    :BuildSystem buildSystem,
    :DeviceManager deviceManager,
    :Doctor doctor,
    :EmulatorManager emulatorManager,
    :FeatureFlags featureFlags,
    :ToolContext toolContext,
  ) = toolDependencies;
  // What the `BuildTargets` context override in [main] provides. Up to Flutter
  // 3.47 attach, drive and the daemon read it from the context; since 3.50
  // they are handed it, and stock hands them `const BuildTargetsImpl()`.
  final BuildTargets buildTargets = toolDependencies.buildTargets ?? const BuildTargetsImpl();
  return <FlutterCommand>[
    // Commands forwarded directly from flutter_tools — these have no
    // tvOS-specific behaviour, so we register them as-is. Anything we
    // do NOT register here would print "Could not find a command named
    // X" on `flutter-tvos X`, even though plain `flutter X` works.
    AssembleCommand(
      buildSystem: buildSystem,
      featureFlags: featureFlags,
      toolContext: toolContext,
      verboseHelp: verboseHelp,
    ),
    ConfigCommand(
      androidContext: androidContext,
      featureFlags: featureFlags,
      toolContext: toolContext,
      verboseHelp: verboseHelp,
    ),
    DaemonCommand(
      androidContext: androidContext,
      androidWorkflow: androidWorkflow,
      buildSystem: buildSystem,
      buildTargets: buildTargets,
      deviceManager: deviceManager,
      hidden: !verboseHelp,
      toolContext: toolContext,
      xcode: appleContext.xcode,
    ),
    DebugAdapterCommand(toolContext: toolContext, verboseHelp: verboseHelp),
    DoctorCommand(doctor: doctor, toolContext: toolContext, verbose: verbose),
    EmulatorsCommand(
      doctor: doctor,
      emulatorManager: emulatorManager,
      toolContext: toolContext,
      verboseHelp: verboseHelp,
    ),
    GenerateCommand(toolContext: toolContext),
    GenerateLocalizationsCommand(toolContext: toolContext),
    InstallCommand(toolContext: toolContext, verboseHelp: verboseHelp),
    LogsCommand(toolContext: toolContext),
    // Upstream `pub` (and its alias `packages`) — registers `pub get`,
    // `pub upgrade`, `pub add`, `pub remove`, `pub publish`, `pub
    // outdated`, `pub deps`, `pub cache`, `pub run`, `pub global`,
    // `pub token`. Without this, `flutter-tvos pub get` fails with
    // "Could not find a command named 'pub'" — an invisible regression
    // because the `flutter test` / `flutter run` pre-step runs pub-get
    // internally, so users only notice when they invoke pub directly.
    PackagesCommand(buildSystem: buildSystem, toolContext: toolContext, verboseHelp: verboseHelp),
    ScreenshotCommand(toolContext: toolContext),
    ShellCompletionCommand(toolContext: toolContext),
    SymbolizeCommand(toolContext: toolContext),
    UpdatePackagesCommand(toolContext: toolContext, verboseHelp: verboseHelp),
    // Commands extended for tvOS.
    // `upgrade` is overridden so it upgrades the flutter-tvos toolchain to its
    // latest release tag instead of moving the pinned Flutter SDK upstream
    // (which stock UpgradeCommand would do, breaking the engine-artifact pin).
    TvosUpgradeCommand(toolContext: toolContext, verboseHelp: verboseHelp),
    TvosAttachCommand(
      buildSystem: buildSystem,
      buildTargets: buildTargets,
      toolContext: toolContext,
      xcode: appleContext.xcode,
      verboseHelp: verboseHelp,
    ),
    TvosBuildCommand(logger: toolContext.logger, verboseHelp: verboseHelp),
    TvosCleanCommand(
      toolContext: toolContext,
      xcode: appleContext.xcode,
      xcodeProjectInterpreter: appleContext.xcodeProjectInterpreter,
      verbose: verbose,
    ),
    TvosCreateCommand(
      androidContext: androidContext,
      appleContext: appleContext,
      templateRenderer: const MustacheTemplateRenderer(),
      toolContext: toolContext,
      verboseHelp: verboseHelp,
    ),
    TvosDevicesCommand(
      deviceManager: deviceManager,
      doctor: doctor,
      toolContext: toolContext,
      verboseHelp: verboseHelp,
    ),
    TvosDriveCommand(
      buildSystem: buildSystem,
      buildTargets: buildTargets,
      toolContext: toolContext,
      verboseHelp: verboseHelp,
    ),
    TvosPluginCommand(verboseHelp: verboseHelp),
    TvosPrecacheCommand(
      verboseHelp: verboseHelp,
      cache: toolContext.cache,
      logger: toolContext.logger,
      platform: toolContext.platform,
      featureFlags: featureFlags,
    ),
    TvosRunCommand(toolContext: toolContext, verboseHelp: verboseHelp),
    // As in 1.11.x: no native-assets builder (a host test builds no code
    // assets for tvOS) and stock's default verbosity.
    TvosTestCommand(toolContext: toolContext, verboseHelp: verboseHelp),
    TvosUseCommand(),
    TvosVersionsCommand(),
  ];
}

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

  // Make `flutter-tvos create --platforms=tvos` first-class. Upstream
  // Flutter's `--platforms` rejects `tvos` at parse time; rewrite it here
  // (the one argv seam we own) before the runner parses.
  args = expandTvosPlatformArgs(args);

  Cache.flutterRoot = join(rootPath, 'flutter');

  await runner.run(
    args,
    (ToolDependencies toolDependencies) => tvosCommands(
      toolDependencies: toolDependencies,
      verbose: verbose,
      verboseHelp: verboseHelp,
    ),
    verbose: verbose,
    verboseHelp: verboseHelp,
    muteCommandLogging: muteCommandLogging,
    reportCrashes: false,
    overrides: <Type, Generator>{
      // Runs the build hooks during a resident session. `RunCommand` already
      // passes this through as the resident runner's `dartBuilder`, and
      // `HotRunner._updateDevFS` calls it whenever the asset bundle needs
      // rebuilding — but the getter reads it out of the context, so without an
      // override it was null and the call was skipped for the whole session. A
      // package that generates its assets from a build hook then served
      // whatever the last full build happened to leave behind.
      //
      // What counts as "needs rebuilding" is upstream's
      // `AssetBundle.needsBuild()`, untouched here; this restores the call it
      // gates, not the gate.
      //
      // This is tvOS's own runner rather than upstream's, so a reload names the
      // same target OS a build does. Upstream's asks for data assets alone,
      // which carries no target OS at all, and a package choosing an output
      // from it would swap in a different one every time the two took turns.
      FlutterHookRunner: () => TvosHookRunner(),
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
