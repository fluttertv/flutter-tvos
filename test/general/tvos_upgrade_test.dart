// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tvos/commands/upgrade.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';

void main() {
  group('TvosUpgradeCommandRunner.latestReleaseTag', () {
    // Mimics `git tag -l --sort=-v:refname` output: newest first.
    const realTags = <String>[
      'v3.44.1-tvos.1.2.0',
      'v3.44.0-tvos.1.1.1',
      'v3.44.0-tvos.1.1.0',
      'v3.41.9-tvos.1.1.0',
      'v3.41.9-tvos.1.0.1',
      'v3.41.4-tvos.1.0.0',
    ];

    test('picks the newest release tag from a version-sorted list', () {
      expect(TvosUpgradeCommandRunner.latestReleaseTag(realTags), 'v3.44.1-tvos.1.2.0');
    });

    test('ignores tags that are not flutter-tvos release tags', () {
      final tags = <String>[
        'nightly',
        'latest',
        'v3.44.1', // plain Flutter-style tag, not ours
        'tvos.1.2.0', // missing the v<flutter> prefix
        'v3.44.0-tvos.1.1.1', // first real match
        'v3.41.4-tvos.1.0.0',
      ];
      expect(TvosUpgradeCommandRunner.latestReleaseTag(tags), 'v3.44.0-tvos.1.1.1');
    });

    test('returns null when there are no release tags', () {
      expect(TvosUpgradeCommandRunner.latestReleaseTag(const <String>['nightly', 'foo']), isNull);
      expect(TvosUpgradeCommandRunner.latestReleaseTag(const <String>[]), isNull);
    });

    test('trims surrounding whitespace on the matched tag', () {
      expect(
        TvosUpgradeCommandRunner.latestReleaseTag(const <String>['  v3.44.1-tvos.1.2.0  ']),
        'v3.44.1-tvos.1.2.0',
      );
    });

    test('release tag pattern only matches the v<flutter>-tvos.<tool> shape', () {
      final RegExp p = TvosUpgradeCommandRunner.releaseTagPattern;
      expect(p.hasMatch('v3.44.1-tvos.1.2.0'), isTrue);
      expect(p.hasMatch('v10.0.0-tvos.12.34.56'), isTrue);
      expect(p.hasMatch('v3.44.1-tvos.1.2'), isFalse); // tool version needs 3 parts
      expect(p.hasMatch('3.44.1-tvos.1.2.0'), isFalse); // missing leading v
      expect(p.hasMatch('v3.44.1-ios.1.2.0'), isFalse); // wrong platform infix
    });
  });

  group('TvosUpgradeCommandRunner.fetchLatestReleaseVersion', () {
    late FakeProcessManager processManager;
    late TvosUpgradeCommandRunner runner;

    setUp(() {
      processManager = FakeProcessManager.empty();
      runner = TvosUpgradeCommandRunner(
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      )..workingDirectory = '/repo';
    });

    test('peels annotated release tags to the underlying commit SHA', () async {
      // An annotated tag: `git rev-parse <tag>` would return the tag-object
      // SHA, but `<tag>^{commit}` must resolve to the commit so the result is
      // comparable to `git rev-parse HEAD`.
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'v3.44.1-tvos.1.2.0\nv3.44.0-tvos.1.1.1\n',
        ),
        const FakeCommand(
          command: <String>['git', 'rev-parse', 'v3.44.1-tvos.1.2.0^{commit}'],
          stdout: '840123adb831536a3512df43355dd355c9a77878\n',
        ),
      ]);

      final TvosVersion upstream = await runner.fetchLatestReleaseVersion();

      expect(upstream.tag, 'v3.44.1-tvos.1.2.0');
      expect(upstream.hash, '840123adb831536a3512df43355dd355c9a77878');
      expect(processManager, hasNoRemainingExpectations);
    });

    test('skips non-release tags when choosing the newest', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'nightly\nlatest\nv3.44.0-tvos.1.1.1\nv3.41.4-tvos.1.0.0\n',
        ),
        const FakeCommand(
          command: <String>['git', 'rev-parse', 'v3.44.0-tvos.1.1.1^{commit}'],
          stdout: 'cafebabecafebabecafebabecafebabecafebabe\n',
        ),
      ]);

      final TvosVersion upstream = await runner.fetchLatestReleaseVersion();

      expect(upstream.tag, 'v3.44.0-tvos.1.1.1');
      expect(upstream.hash, 'cafebabecafebabecafebabecafebabecafebabe');
      expect(processManager, hasNoRemainingExpectations);
    });

    test('throws a tool exit when no release tags exist', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'nightly\nlatest\n',
        ),
      ]);

      await expectToolExitLater(runner.fetchLatestReleaseVersion(), contains('no release tags'));
    });
  });

  group('TvosUpgradeCommandRunner.fetchCurrentVersion', () {
    late FakeProcessManager processManager;
    late TvosUpgradeCommandRunner runner;

    setUp(() {
      processManager = FakeProcessManager.empty();
      runner = TvosUpgradeCommandRunner(
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      )..workingDirectory = '/repo';
    });

    test('returns the commit hash and exact tag when HEAD is tagged', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
          stdout: '840123adb831536a3512df43355dd355c9a77878\n',
        ),
        const FakeCommand(
          command: <String>['git', 'describe', '--exact-match', '--tags', 'HEAD'],
          stdout: 'v3.44.1-tvos.1.2.0\n',
        ),
      ]);

      final TvosVersion current = await runner.fetchCurrentVersion();

      expect(current.hash, '840123adb831536a3512df43355dd355c9a77878');
      expect(current.tag, 'v3.44.1-tvos.1.2.0');
      expect(current.label, 'v3.44.1-tvos.1.2.0');
      expect(processManager, hasNoRemainingExpectations);
    });

    test('leaves tag null on a development checkout with no exact tag', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
          stdout: 'cafef00dcafef00dcafef00dcafef00dcafef00d\n',
        ),
        // `git describe --exact-match` exits non-zero when HEAD is not on a tag.
        const FakeCommand(
          command: <String>['git', 'describe', '--exact-match', '--tags', 'HEAD'],
          exitCode: 128,
        ),
      ]);

      final TvosVersion current = await runner.fetchCurrentVersion();

      expect(current.hash, 'cafef00dcafef00dcafef00dcafef00dcafef00d');
      expect(current.tag, isNull);
      expect(current.label, 'cafef00dca'); // short hash fallback
      expect(processManager, hasNoRemainingExpectations);
    });
  });

  group('TvosUpgradeCommandRunner.runCommandFirstHalf', () {
    late FakeProcessManager processManager;
    late BufferLogger logger;

    setUp(() {
      processManager = FakeProcessManager.empty();
      logger = BufferLogger.test();
    });

    const sha = '840123adb831536a3512df43355dd355c9a77878';

    testUsingContext(
      'reports already up to date when HEAD is the latest (annotated) release',
      () async {
        processManager.addCommands(<FakeCommand>[
          const FakeCommand(command: <String>['git', 'fetch', '--tags']),
          const FakeCommand(
            command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
            stdout: 'v3.44.1-tvos.1.2.0\n',
          ),
          const FakeCommand(
            command: <String>['git', 'rev-parse', 'v3.44.1-tvos.1.2.0^{commit}'],
            stdout: '$sha\n',
          ),
          const FakeCommand(
            command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
            stdout: '$sha\n',
          ),
          const FakeCommand(
            command: <String>['git', 'describe', '--exact-match', '--tags', 'HEAD'],
            stdout: 'v3.44.1-tvos.1.2.0\n',
          ),
        ]);

        final runner = TvosUpgradeCommandRunner()..workingDirectory = '/repo';
        await runner.runCommandFirstHalf(force: false, testFlow: true, verifyOnly: false);

        expect(logger.statusText, contains('already up to date at v3.44.1-tvos.1.2.0'));
        expect(processManager, hasNoRemainingExpectations);
      },
      overrides: <Type, Generator>{
        ProcessManager: () => processManager,
        Logger: () => logger,
      },
    );

    testUsingContext(
      'refuses to upgrade a dirty checkout without --force',
      () async {
        processManager.addCommands(<FakeCommand>[
          const FakeCommand(command: <String>['git', 'fetch', '--tags']),
          const FakeCommand(
            command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
            stdout: 'v3.44.1-tvos.1.2.0\n',
          ),
          const FakeCommand(
            command: <String>['git', 'rev-parse', 'v3.44.1-tvos.1.2.0^{commit}'],
            stdout: '$sha\n',
          ),
          const FakeCommand(
            command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
            stdout: 'feedfacefeedfacefeedfacefeedfacefeedface\n',
          ),
          const FakeCommand(
            command: <String>['git', 'describe', '--exact-match', '--tags', 'HEAD'],
            exitCode: 128,
          ),
          const FakeCommand(
            command: <String>['git', 'status', '-s'],
            stdout: ' M lib/foo.dart\n',
          ),
        ]);

        final runner = TvosUpgradeCommandRunner()..workingDirectory = '/repo';
        await expectToolExitLater(
          runner.runCommandFirstHalf(force: false, testFlow: true, verifyOnly: false),
          contains('uncommitted changes'),
        );
        expect(processManager, hasNoRemainingExpectations);
      },
      overrides: <Type, Generator>{
        ProcessManager: () => processManager,
        Logger: () => logger,
      },
    );
  });

  group('TvosVersion', () {
    test('label is the tag when tagged', () {
      const version = TvosVersion(hash: 'abcdef1234567890', tag: 'v3.44.1-tvos.1.2.0');
      expect(version.label, 'v3.44.1-tvos.1.2.0');
    });

    test('label falls back to the short hash when untagged', () {
      const version = TvosVersion(hash: 'abcdef1234567890', tag: null);
      expect(version.label, 'abcdef1234');
      expect(version.hashShort, 'abcdef1234');
    });

    test('hashShort tolerates a hash shorter than 10 chars', () {
      const version = TvosVersion(hash: 'abc123', tag: null);
      expect(version.hashShort, 'abc123');
    });
  });
}
