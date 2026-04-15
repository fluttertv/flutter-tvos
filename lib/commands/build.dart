// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/android/android_sdk.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tvos_build_info.dart';
import '../tvos_builder.dart';
import '../tvos_cache.dart';
import '../tvos_plugins.dart';

class TvosBuildCommand extends BuildCommand {
  TvosBuildCommand({
    required FileSystem fileSystem,
    required BuildSystem buildSystem,
    required OperatingSystemUtils osUtils,
    required Logger logger,
    required AndroidSdk? androidSdk,
    required bool verboseHelp,
  }) : super(
          fileSystem: fileSystem,
          buildSystem: buildSystem,
          osUtils: osUtils,
          logger: logger,
          androidSdk: androidSdk,
          verboseHelp: verboseHelp,
        ) {
    addSubcommand(BuildTvosCommand(logger: logger, verboseHelp: verboseHelp));
  }
}

class BuildTvosCommand extends BuildSubCommand with TvosRequiredArtifacts {
  BuildTvosCommand({
    required super.logger,
    required bool verboseHelp,
  }) : super(verboseHelp: verboseHelp) {
    addCommonDesktopBuildOptions(verboseHelp: verboseHelp);
    argParser.addFlag(
      'simulator',
      help: 'Build for the tvOS Simulator instead of a physical device.',
      defaultsTo: false,
    );
  }

  @override
  final String name = 'tvos';

  @override
  final String description = 'Build an Apple tvOS application.';

  @override
  Future<void> validateCommand() async {
    final FlutterProject project = FlutterProject.current();
    await ensureReadyForTvosTooling(project);
    return super.validateCommand();
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    final FlutterProject project = FlutterProject.current();
    final bool simulator = boolArg('simulator');
    final TvosBuildInfo tvosBuildInfo = TvosBuildInfo(
      await getBuildInfo(),
      targetArch: 'arm64',
      simulator: simulator,
    );

    await TvosBuilder.buildBundle(
      project: project,
      tvosBuildInfo: tvosBuildInfo,
      targetFile: targetFile,
    );
    return FlutterCommandResult.success();
  }
}
