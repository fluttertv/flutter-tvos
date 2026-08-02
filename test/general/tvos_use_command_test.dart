// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/commands/use.dart';
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

  const String tagList = 'v3.44.7-tvos.1.4.2\n'
      'v3.44.5-tvos.1.4.0\n'
      'v3.32.8-tvos.1.0.0\n';

  /// resolve() -> current() ordering, matching TvosUseCommand.
  void stubResolveThenCurrent({
    required String targetTag,
    required String targetHash,
    String headTag = 'v3.44.7-tvos.1.4.2',
  }) {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: tagList,
      ),
      FakeCommand(
        command: <String>['git', 'rev-parse', '$targetTag^{commit}'],
        stdout: '$targetHash\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      FakeCommand(
        command: const <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        stdout: '$headTag\n',
      ),
    ]);
  }

  testUsingContext('is a no-op when already on the requested version', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.44.7-tvos.1.4.2',
      targetHash: 'aaaabbbbccccddddeeeeffff0000111122223333',
    );
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await createTestCommandRunner(command).run(<String>['use', '3.44.7']);

    expect(logger.statusText, contains('already on'));
    expect(processManager, hasNoRemainingExpectations);
    // No reset, and no breadcrumb written for a switch that did not happen.
    expect(toolState.readPreviousTag(), isNull);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('the already-on-target check runs before the dirty-tree guard', () async {
    // A user with local edits who names the version they are already on must
    // not be refused an operation that would do nothing. If the guard ran
    // first this test would fail with a tool exit, and `git status` would be
    // consumed from the fake.
    stubResolveThenCurrent(
      targetTag: 'v3.44.7-tvos.1.4.2',
      targetHash: 'aaaabbbbccccddddeeeeffff0000111122223333',
    );
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await createTestCommandRunner(command).run(<String>['use', '3.44.7']);

    expect(logger.statusText, contains('already on'));
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('refuses a dirty checkout and names --force', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommand(
      const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ' M lib/foo.dart\n'),
    );
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.32.8']),
      allOf(contains('uncommitted changes'), contains('--force')),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('records the previous tag before resetting', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ''),
      const FakeCommand(
        command: <String>[
          'git',
          'reset',
          '--hard',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      toolState: toolState,
      runBootstrap: (_) async => 0,
    );

    await createTestCommandRunner(command).run(<String>['use', '3.32.8']);

    expect(toolState.readPreviousTag(), 'v3.44.7-tvos.1.4.2');
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('prints the recovery command when the target will not build', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ''),
      const FakeCommand(
        command: <String>[
          'git',
          'reset',
          '--hard',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      toolState: toolState,
      runBootstrap: (_) async => 1, // the target toolchain fails to build
    );

    // Past the reset the user cannot run `flutter-tvos` at all, so the message
    // must carry the literal git command that undoes it.
    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.32.8']),
      allOf(
        contains('git -C /repo reset --hard v3.44.7-tvos.1.4.2'),
        contains('3.32.8'),
      ),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('an unknown version exits without touching the checkout', () async {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: tagList,
      ),
    ]);
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.99.0']),
      contains('3.99.0'),
    );
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});
}
