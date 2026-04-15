// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/commands/drive.dart';
import 'package:flutter_tools/src/project.dart';

import '../tvos_cache.dart';
import '../tvos_plugins.dart';

class TvosDriveCommand extends DriveCommand with TvosRequiredArtifacts {
  TvosDriveCommand({
    required super.verboseHelp,
    required super.fileSystem,
    required super.logger,
    required super.platform,
    required super.signals,
    required super.terminal,
    required super.outputPreferences,
  });

  @override
  Future<void> validateCommand() async {
    final FlutterProject project = FlutterProject.current();
    await ensureReadyForTvosTooling(project);
    return super.validateCommand();
  }
}
