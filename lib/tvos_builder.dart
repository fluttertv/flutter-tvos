// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/analyze_size.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/dart/package_map.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/base/logger.dart';

import 'build_targets/application.dart';
import 'tvos_build_info.dart';
import 'tvos_plugins.dart';
import 'tvos_project.dart';

/// The define to control what tvOS target is built for.
const String kTargetBackendType = 'TargetBackendType';

class TvosBuilder {
  static Future<void> buildBundle({
    required FlutterProject project,
    required TvosBuildInfo tvosBuildInfo,
    required String targetFile,
    SizeAnalyzer? sizeAnalyzer,
  }) async {
    final TvosProject tvosProject = TvosProject.fromFlutter(project);
    if (!tvosProject.existsSync()) {
      throwToolExit(
        'This project is not configured for tvOS.\n'
        'To fix this problem, create a new project by running `flutter-tvos create <app-dir>`.',
      );
    }

    final Directory outputDir = project.directory.childDirectory('build').childDirectory('tvos');
    final BuildInfo buildInfo = tvosBuildInfo.buildInfo;
    final String buildModeName = buildInfo.mode.cliName;

    // Used by AotElfBase to generate an AOT snapshot.
    final String targetPlatformName = getNameForTargetPlatform(TargetPlatform.ios);

    final Environment environment = Environment(
      projectDir: project.directory,
      outputDir: outputDir,
      buildDir: project.dartTool.childDirectory('flutter_build'),
      cacheDir: globals.cache.getRoot(),
      flutterRootDir: globals.fs.directory(Cache.flutterRoot),
      engineVersion: globals.flutterVersion.engineRevision,
      // generateDartPluginRegistry propagates to KernelSnapshot as
      // `checkDartPluginRegistry`, which tells frontend-server to link
      // `_PluginRegistrant.register()` into the kernel blob via
      // --source=<path>/dart_plugin_registrant.dart. We need this so the
      // engine's FindAndInvokeDartPluginRegistrant() actually fires at
      // isolate startup.
      //
      // On stock Flutter this also triggers DartPluginRegistrantTarget to
      // generate a registrant based on Android/iOS/macOS plugins — which
      // for a tvOS project would route to `_foundation` plugins that have
      // no native code in our bundle. We side-step that by using
      // TvosKernelSnapshot (see build_targets/application.dart), which
      // substitutes TvosDartPluginRegistrantTarget for the upstream one.
      generateDartPluginRegistry: true,
      defines: <String, String>{
        kTargetFile: targetFile,
        kBuildMode: buildModeName,
        kTargetPlatform: targetPlatformName,
        ...buildInfo.toBuildSystemEnvironment(),
      },
      artifacts: globals.artifacts!,
      fileSystem: globals.fs,
      logger: globals.logger,
      processManager: globals.processManager,
      platform: globals.platform,
      analytics: globals.analytics,
      packageConfigPath: findPackageConfigFileOrDefault(project.directory).path,
    );

    final Target target = buildInfo.isDebug
        ? DebugTvosApplication(tvosBuildInfo)
        : ReleaseTvosApplication(tvosBuildInfo);

    // Write the tvOS dart plugin registrant BEFORE the kernel compiles so
    // that Dart-side federated plugins (e.g. shared_preferences_tvos) call
    // registerWith() instead of the iOS implementations. Flutter's build
    // system would otherwise emit a registrant that routes to iOS plugins
    // (Platform.isIOS == true on tvOS). We disabled generateDartPluginRegistry
    // above so Flutter won't overwrite this file during the build.
    writeTvosDartPluginRegistrant(project);

    final Status status = globals.logger.startProgress(
        'Building a tvOS application in $buildModeName mode for ${tvosBuildInfo.targetArch} target...');
    try {
      final BuildResult result = await globals.buildSystem.build(target, environment);
      if (!result.success) {
        for (final ExceptionMeasurement measurement in result.exceptions.values) {
          globals.printError(measurement.exception.toString());
        }
        throwToolExit('The build failed.');
      }

      // These pseudo targets cannot be skipped and should be invoked whenever
      // the build is run.
      await NativeTvosBundle(tvosBuildInfo, targetFile).build(environment);
    } finally {
      status.stop();
    }
  }
}
