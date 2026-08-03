// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/commands/build.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tvos_build_info.dart';
import '../tvos_builder.dart';
import '../tvos_cache.dart';
import '../tvos_plugins.dart';

/// `flutter-tvos build` — registers only the subcommands this toolchain
/// actually supports.
///
/// Deliberately extends [FlutterCommand] rather than upstream's [BuildCommand].
/// Inheriting the latter bought four trivial members -- a name, a description,
/// a category and a failing `runCommand` -- and cost seventeen constructor
/// parameters forwarded straight through, none of which this class reads. They
/// exist to build the Android, iOS, macOS, web, Linux and Windows subcommands,
/// so we were paying upstream's dependency-injection churn to register twelve
/// commands a tvOS tool should not offer: `flutter-tvos build ios` would have
/// built an iOS app against an engine compiled for tvOS.
///
/// `build bundle` goes with them, despite being nominally platform-neutral.
/// BundleBuilder resolves `globals.buildTargets.copyFlutterBundle`, and
/// executable.dart registers upstream's BuildTargetsImpl — so it runs
/// upstream's CopyFlutterBundle / KernelSnapshot / DartPluginRegistrantTarget,
/// which are precisely what TvosCopyFlutterBundle, TvosKernelSnapshot and
/// TvosDartPluginRegistrantTarget exist to replace. The bundle it produces has
/// no `*_tvos` plugin registration, and `--target-platform` has no tvos value
/// and defaults to android-arm. A command that silently returns the wrong
/// answer is worse than one that is absent.
///
/// That forwarding was also, on its own, half the work of porting this CLI to
/// another Flutter version -- twelve of the twenty-five analyzer errors against
/// 3.32.8 came from this constructor. Composing instead of inheriting removes
/// them permanently: upstream can reshape BuildCommand's injection freely now.
class TvosBuildCommand extends FlutterCommand {
  TvosBuildCommand({required Logger logger, required bool verboseHelp}) {
    addSubcommand(BuildTvosCommand(logger: logger, verboseHelp: verboseHelp));
  }

  @override
  final String name = 'build';

  @override
  final String description = 'Build a tvOS app or install bundle.';

  @override
  String get category => FlutterCommandCategory.project;

  @override
  Future<FlutterCommandResult> runCommand() async => FlutterCommandResult.fail();
}

class BuildTvosCommand extends BuildSubCommand with TvosRequiredArtifacts {
  BuildTvosCommand({required super.logger, required bool verboseHelp})
    : super(verboseHelp: verboseHelp) {
    addCommonDesktopBuildOptions(verboseHelp: verboseHelp);
    argParser.addFlag(
      'simulator',
      help: 'Build for the tvOS Simulator instead of a physical device.',
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
    final tvosBuildInfo = TvosBuildInfo(
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
