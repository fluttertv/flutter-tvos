// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/src/interface/directory.dart';
import 'package:flutter_tools/src/commands/precache.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

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

  // The `--android` umbrella flag stands in for its three child artifacts.
  static const Map<String, String> _umbrellaForArtifact = <String, String>{
    'android_gen_snapshot': 'android',
    'android_maven': 'android',
    'android_internal_build': 'android',
  };

  // Non-platform artifacts a tvOS build always needs (fonts, sky_engine,
  // flutter_patched_sdk, font-subset, host USB-deploy tools, engine stamp).
  static const Set<String> _alwaysOn = <String>{'universal', 'informative'};

  /// The non-tvOS artifacts to fetch for the given flags. With no platform
  /// flags this is only [_alwaysOn]; `--all-platforms` and explicit per-platform
  /// flags add their artifacts, and a flag for an `--android` child works either
  /// via `--android` or the child's own flag. Feature-gated platforms are
  /// skipped when their feature is disabled. Pure (no I/O) so it is unit-tested
  /// directly — see `test/general/tvos_precache_test.dart`.
  @visibleForTesting
  static Set<DevelopmentArtifact> selectRequiredArtifacts({
    required FeatureFlags featureFlags,
    required bool allPlatforms,
    required bool Function(String flagName) isFlagOn,
  }) {
    final requiredArtifacts = <DevelopmentArtifact>{};
    for (final DevelopmentArtifact artifact in DevelopmentArtifact.values) {
      if (artifact.feature != null && !featureFlags.isEnabled(artifact.feature!)) {
        continue;
      }
      final String? umbrella = _umbrellaForArtifact[artifact.name];
      final bool explicitlyRequested =
          isFlagOn(artifact.name) || (umbrella != null && isFlagOn(umbrella));
      if (allPlatforms || _alwaysOn.contains(artifact.name) || explicitlyRequested) {
        requiredArtifacts.add(artifact);
      }
    }
    return requiredArtifacts;
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

    final Set<DevelopmentArtifact> requiredArtifacts = selectRequiredArtifacts(
      featureFlags: featureFlags,
      allPlatforms: allPlatforms,
      // `ArgResults.wasParsed` throws on an option the command never defined, so
      // guard with `options.containsKey` — a future Flutter `DevelopmentArtifact`
      // without a matching precache flag then can't crash us.
      isFlagOn: (String name) =>
          argParser.options.containsKey(name) && argResults!.wasParsed(name) && boolArg(name),
    );

    // `updateAll` is idempotent — it checks each artifact's stamp and re-downloads
    // only what is stale, so there is no need (and no reliable way, since the
    // cache also tracks platforms we intentionally skip) to short-circuit on a
    // global `isUpToDate()` check.
    await globals.cache.updateAll(requiredArtifacts);
    return FlutterCommandResult.success();
  }
}
