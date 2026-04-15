// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/commands/precache.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import 'package:flutter_tools/src/globals.dart' as globals;
import '../tvos_cache.dart';

class TvosPrecacheCommand extends PrecacheCommand {
  TvosPrecacheCommand({
    required super.verboseHelp,
    required super.cache,
    required super.logger,
    required super.platform,
    required super.featureFlags,
  }) {
    argParser.addFlag(
      'tvos',
      negatable: true,
      defaultsTo: true,
      help: 'Precache artifacts for tvOS development.',
    );
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (boolArg('tvos')) {
      if (boolArg('force')) {
        final artifactDir = tvosArtifactDirectory(globals.fs);
        if (artifactDir.existsSync()) {
          artifactDir.deleteSync(recursive: true);
        }
      }
      await globals.cache.updateAll(<DevelopmentArtifact>{
        TvosDevelopmentArtifact.tvos,
      });
    }
    return await super.runCommand();
  }
}
