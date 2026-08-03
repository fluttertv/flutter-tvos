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

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    fileSystem = MemoryFileSystem.test();
    fileSystem.directory('/repo/.git').createSync(recursive: true);
    releases = TvosReleases(
      workingDirectory: '/repo',
      processUtils: ProcessUtils(processManager: processManager, logger: logger),
    );
  });

  const tagList = 'v3.44.7-tvos.1.4.2\n'
      'v3.44.5-tvos.1.4.0\n'
      'v3.32.8-tvos.1.0.0\n';

  /// resolve() -> current() ordering, matching TvosUseCommand.
  void stubResolveThenCurrent({
    required String targetTag,
    required String targetHash,
    String headTag = 'v3.44.7-tvos.1.4.2',
  }) {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags', '--force']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        workingDirectory: '/repo',
        stdout: tagList,
      ),
      FakeCommand(
        command: <String>['git', 'rev-parse', '$targetTag^{commit}'],
        workingDirectory: '/repo',
        stdout: '$targetHash\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        workingDirectory: '/repo',
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      FakeCommand(
        command: const <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        stdout: '$headTag\n',
      ),
      const FakeCommand(
        command: <String>['git', 'symbolic-ref', '-q', '--short', 'HEAD'],
        workingDirectory: '/repo',
        exitCode: 1,
      ),
    ]);
  }

  testUsingContext('is a no-op when already on the requested version', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.44.7-tvos.1.4.2',
      targetHash: 'aaaabbbbccccddddeeeeffff0000111122223333',
    );
    final command = TvosUseCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['use', '3.44.7']);

    expect(logger.statusText, contains('already on'));
    expect(processManager, hasNoRemainingExpectations);
    // No reset, and no breadcrumb written for a switch that did not happen.
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
    final command = TvosUseCommand(releases: releases);

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
      const FakeCommand(command: <String>['git', 'status', '-s'], workingDirectory: '/repo', stdout: ' M lib/foo.dart\n'),
    );
    final command = TvosUseCommand(releases: releases);

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
      const FakeCommand(command: <String>['git', 'status', '-s']),
      const FakeCommand(
        command: <String>[
          'git',
          'checkout',
          '--force',
          '--detach',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
        workingDirectory: '/repo',
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      runBootstrap: (_) async => 0,
    );

    await createTestCommandRunner(command).run(<String>['use', '3.32.8']);

    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('prints the recovery command when the target will not build', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'status', '-s']),
      const FakeCommand(
        command: <String>[
          'git',
          'checkout',
          '--force',
          '--detach',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
        workingDirectory: '/repo',
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      runBootstrap: (_) async => 1, // the target toolchain fails to build
    );

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.32.8']),
      contains('3.32.8'),
    );

    // Past the checkout the user cannot run `flutter-tvos` at all, so the way
    // back has to already be on screen. It is printed when the checkout moves
    // rather than from the failure path, so a Ctrl-C or a process that cannot
    // be spawned cannot take it with them.
    expect(
      logger.statusText,
      contains('git -C /repo checkout --force --detach v3.44.7-tvos.1.4.2'),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('an unknown version exits without touching the checkout', () async {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags', '--force']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        workingDirectory: '/repo',
        stdout: tagList,
      ),
    ]);
    final command = TvosUseCommand(releases: releases);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.99.0']),
      contains('3.99.0'),
    );
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('--force switches past a dirty tree', () async {
    // The refusal message advertises --force; nothing was checking the flag
    // actually does anything. Deleting `!boolArg('force') &&` from the guard
    // passed the whole suite.
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      // No `git status -s` stub: with --force the guard must not run at all.
      const FakeCommand(
        command: <String>[
          'git',
          'checkout',
          '--force',
          '--detach',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
        workingDirectory: '/repo',
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      runBootstrap: (_) async => 0,
    );

    await createTestCommandRunner(command).run(<String>['use', '3.32.8', '--force']);

    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('bootstraps in the order the design depends on', () async {
    // The probe must come FIRST -- it is what distinguishes "this release line
    // does not build" from "an artifact download failed", and reordering it
    // after precache silently destroys that distinction. precache must carry
    // --force, or the previous version's engine artifacts survive the switch.
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'status', '-s'], workingDirectory: '/repo'),
      const FakeCommand(
        command: <String>[
          'git',
          'checkout',
          '--force',
          '--detach',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
        workingDirectory: '/repo',
      ),
    ]);
    final invocations = <List<String>>[];
    final command = TvosUseCommand(
      releases: releases,
      runBootstrap: (List<String> args) async {
        invocations.add(args);
        return 0;
      },
    );

    await createTestCommandRunner(command).run(<String>['use', '3.32.8']);

    expect(invocations, <List<String>>[
      <String>['--version'],
      <String>['precache', '--force'],
      <String>['doctor'],
    ]);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('a precache failure is reported as itself, not as a broken toolchain', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'status', '-s'], workingDirectory: '/repo'),
      const FakeCommand(
        command: <String>[
          'git',
          'checkout',
          '--force',
          '--detach',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
        workingDirectory: '/repo',
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      // The probe succeeds, so the toolchain builds; only precache fails.
      runBootstrap: (List<String> args) async => args.first == 'precache' ? 1 : 0,
    );

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.32.8']),
      allOf(contains('engine artifacts'), contains('precache --force')),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});


  testUsingContext('the recovery command puts you back on your branch', () async {
    // Switching detaches, so a recovery that names the tag or hash leaves a
    // contributor at the right commit but not on the branch they were working
    // on -- and the branch is where they were.
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags', '--force'], workingDirectory: '/repo'),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        workingDirectory: '/repo',
        stdout: tagList,
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', 'v3.32.8-tvos.1.0.0^{commit}'],
        workingDirectory: '/repo',
        stdout: 'cafebabecafebabecafebabecafebabecafebabe\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        workingDirectory: '/repo',
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      // Untagged: a development checkout, which is exactly the case that used
      // to lose the branch.
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        workingDirectory: '/repo',
        exitCode: 128,
      ),
      const FakeCommand(
        command: <String>['git', 'symbolic-ref', '-q', '--short', 'HEAD'],
        workingDirectory: '/repo',
        stdout: 'main\n',
      ),
      const FakeCommand(command: <String>['git', 'status', '-s'], workingDirectory: '/repo'),
      const FakeCommand(
        command: <String>[
          'git',
          'checkout',
          '--force',
          '--detach',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
        workingDirectory: '/repo',
      ),
    ]);
    final command = TvosUseCommand(releases: releases, runBootstrap: (_) async => 0);

    await createTestCommandRunner(command).run(<String>['use', '3.32.8']);

    expect(logger.statusText, contains('git -C /repo checkout --force main'));
    // Not the detaching form, which would land them at the commit but off the
    // branch.
    expect(logger.statusText, isNot(contains('--detach aaaabbbb')));
  }, overrides: <Type, Generator>{Logger: () => logger});

}
