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
        workingDirectory: '/repo',
        stdout: 'v3.44.7-tvos.1.4.2\nv3.32.8-tvos.1.0.0\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', 'v3.44.7-tvos.1.4.2^{commit}'],
        workingDirectory: '/repo',
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        workingDirectory: '/repo',
        stdout: 'cafebabecafebabecafebabecafebabecafebabe\n',
      ),
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        workingDirectory: '/repo',
        stdout: 'v3.32.8-tvos.1.0.0\n',
      ),
      const FakeCommand(command: <String>['git', 'status', '-s']),
      const FakeCommand(
        command: <String>[
          'git',
          'checkout',
          '--force',
          '--detach',
          'aaaabbbbccccddddeeeeffff0000111122223333',
        ],
        workingDirectory: '/repo',
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

  testUsingContext('refuses a version argument instead of ignoring it', () async {
    // It inherits --force from TvosUseCommand, so silently discarding the
    // argument means `downgrade 3.32.8 --force` discards the user's uncommitted
    // work and switches to the *recorded* tag rather than the one they typed.
    // `use` trains people that a version goes on the command line, so the
    // mistake is likely rather than exotic. Stock flutter refuses it too.
    toolState.writePreviousTag('v3.44.7-tvos.1.4.2');
    final command = TvosDowngradeCommand(releases: releases, toolState: toolState);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['downgrade', '3.32.8', '--force']),
      allOf(contains('does not take a version'), contains('flutter-tvos use 3.32.8')),
    );
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

}
