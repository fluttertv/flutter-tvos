// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/commands/downgrade.dart';
import 'package:flutter_tvos/tvos_releases.dart';
import 'package:flutter_tvos/tvos_tool_state.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';
import '../src/test_flutter_command_runner.dart';

void main() {
  setUpAll(() {
    Cache.disableLocking();
  });

  late FakeProcessManager processManager;
  late BufferLogger logger;
  late FileSystem fileSystem;
  late TvosReleases releases;
  late TvosToolState toolState;

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    fileSystem = MemoryFileSystem.test();
    fileSystem.directory('/repo/.git').createSync(recursive: true);
    releases = TvosReleases(
      workingDirectory: '/repo',
      processUtils: ProcessUtils(processManager: processManager, logger: logger),
    );
    toolState = TvosToolState(repoRoot: '/repo', fileSystem: fileSystem);
  });

  testUsingContext('with nothing recorded, says so and points at versions', () async {
    final command = TvosDowngradeCommand(releases: releases, toolState: toolState);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['downgrade']),
      allOf(contains('no previous'), contains('versions')),
    );
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('switches back to the recorded tag', () async {
    toolState.writePreviousTag('v3.44.7-tvos.1.4.2');
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: 'v3.44.7-tvos.1.4.2\nv3.32.8-tvos.1.0.0\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', 'v3.44.7-tvos.1.4.2^{commit}'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'cafebabecafebabecafebabecafebabecafebabe\n',
      ),
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        stdout: 'v3.32.8-tvos.1.0.0\n',
      ),
      const FakeCommand(command: <String>['git', 'status', '-s']),
      const FakeCommand(
        command: <String>[
          'git',
          'reset',
          '--hard',
          'aaaabbbbccccddddeeeeffff0000111122223333',
        ],
      ),
    ]);
    final command = TvosDowngradeCommand(
      releases: releases,
      toolState: toolState,
      runBootstrap: (_) async => 0,
    );

    await createTestCommandRunner(command).run(<String>['downgrade']);

    expect(processManager, hasNoRemainingExpectations);
    // Going back records where we came from, so downgrade is reversible.
    expect(toolState.readPreviousTag(), 'v3.32.8-tvos.1.0.0');
  }, overrides: <Type, Generator>{Logger: () => logger});
}
