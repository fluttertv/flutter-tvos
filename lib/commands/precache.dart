// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/src/interface/directory.dart';
import 'package:flutter_tools/src/commands/precache.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tvos_cache.dart';

class TvosPrecacheCommand extends PrecacheCommand {
  TvosPrecacheCommand({
    required super.verboseHelp,
    required super.cache,
    required super.logger,
    required super.platform,
    required super.featureFlags,
  }) {
    argParser.addFlag('tvos', defaultsTo: true, help: 'Precache artifacts for tvOS development.');
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (boolArg('tvos')) {
      if (boolArg('force')) {
        final Directory artifactDir = tvosArtifactDirectory(globals.fs);
        if (artifactDir.existsSync()) {
          artifactDir.deleteSync(recursive: true);
        }
      }
      await globals.cache.updateAll(<DevelopmentArtifact>{TvosDevelopmentArtifact.tvos});
    }

    // Stock `flutter precache` with no platform flags downloads *every* enabled
    // platform's artifacts (Android, iOS, web, macOS). A tvOS embedder needs
    // none of those — only the universal artifacts (fonts, sky_engine,
    // flutter_patched_sdk, font-subset) and the engine stamp, on top of the
    // tvOS engine set fetched above. So drive the cache ourselves instead of
    // delegating to `super.runCommand()`, while still honouring the stock
    // per-platform flags (`--ios`, `--android`, `--all-platforms`, …) for anyone
    // who explicitly asks for them.
    if (globals.platform.environment['FLUTTER_ALREADY_LOCKED'] != 'true') {
      await globals.cache.lock();
    }
    if (boolArg('force')) {
      globals.cache.clearStampFiles();
    }
    final bool allPlatforms = boolArg('all-platforms');
    if (allPlatforms) {
      globals.cache.includeAllPlatforms = true;
    }
    if (boolArg('use-unsigned-mac-binaries')) {
      globals.cache.useUnsignedMacBinaries = true;
    }

    // The `--android` umbrella flag stands in for its three child artifacts.
    const umbrellaForArtifact = <String, String>{
      'android_gen_snapshot': 'android',
      'android_maven': 'android',
      'android_internal_build': 'android',
    };
    // Non-platform artifacts a tvOS build needs; always fetched.
    const alwaysOn = <String>{'universal', 'informative'};

    final requiredArtifacts = <DevelopmentArtifact>{};
    for (final DevelopmentArtifact artifact in DevelopmentArtifact.values) {
      if (artifact.feature != null && !featureFlags.isEnabled(artifact.feature!)) {
        continue;
      }
      final String flagName = umbrellaForArtifact[artifact.name] ?? artifact.name;
      final bool explicitlyRequested = argResults!.wasParsed(flagName) && boolArg(flagName);
      if (allPlatforms || alwaysOn.contains(artifact.name) || explicitlyRequested) {
        requiredArtifacts.add(artifact);
      }
    }

    if (!await globals.cache.isUpToDate()) {
      await globals.cache.updateAll(requiredArtifacts);
    } else {
      globals.logger.printStatus('Already up-to-date.');
    }
    return FlutterCommandResult.success();
  }
}
