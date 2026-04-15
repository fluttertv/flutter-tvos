// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/commands/test.dart';
import 'package:flutter_tools/src/project.dart';

import '../tvos_plugins.dart';

class TvosTestCommand extends TestCommand {
  TvosTestCommand({required super.verboseHelp});

  @override
  Future<void> validateCommand() async {
    final FlutterProject project = FlutterProject.current();
    await ensureReadyForTvosTooling(project);
    return super.validateCommand();
  }
}
