// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/commands/create.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/test_flutter_command_runner.dart';

void main() {
  group('TvosCreateCommand', () {
    testUsingContext(
      'exits with the usage message (code 2) when no output directory is given, '
      'instead of crashing on rest.first',
      () async {
        final command = TvosCreateCommand(verboseHelp: false);
        await expectLater(
          createTestCommandRunner(command).run(<String>['create']),
          throwsToolExit(
            exitCode: 2,
            message: 'No option specified for the output directory',
          ),
        );
      },
    );
  });
}
