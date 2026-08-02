// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tvos/tvos_releases.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';

void main() {
  group('TvosRelease.parse', () {
    test('splits a release tag into its Flutter and tool versions', () {
      final TvosRelease? r = TvosRelease.parse('v3.44.7-tvos.1.4.2');
      expect(r, isNotNull);
      expect(r!.tag, 'v3.44.7-tvos.1.4.2');
      expect(r.flutterVersion, '3.44.7');
      expect(r.toolVersion, '1.4.2');
      expect(r.hash, isNull);
    });

    test('trims surrounding whitespace', () {
      expect(TvosRelease.parse('  v3.44.7-tvos.1.4.2  ')!.tag, 'v3.44.7-tvos.1.4.2');
    });

    test('returns null for anything that is not a release tag', () {
      expect(TvosRelease.parse('nightly'), isNull);
      expect(TvosRelease.parse('latest'), isNull);
      expect(TvosRelease.parse('v3.44.1'), isNull); // plain Flutter-style tag
      expect(TvosRelease.parse('tvos.1.2.0'), isNull); // no v<flutter> prefix
      expect(TvosRelease.parse('v3.44.1-tvos.1.2'), isNull); // tool needs 3 parts
      expect(TvosRelease.parse('3.44.1-tvos.1.2.0'), isNull); // no leading v
      expect(TvosRelease.parse('v3.44.1-ios.1.2.0'), isNull); // wrong infix
    });

    test('accepts multi-digit version components', () {
      final TvosRelease? r = TvosRelease.parse('v10.0.0-tvos.12.34.56');
      expect(r!.flutterVersion, '10.0.0');
      expect(r.toolVersion, '12.34.56');
    });
  });

  group('TvosRelease.collapseToNewestPerFlutterVersion', () {
    // Newest-first, as `git tag -l --sort=-v:refname` produces. Mirrors the
    // real tag list, which has two tool releases for several Flutter versions.
    List<TvosRelease> parseAll(List<String> tags) =>
        tags.map(TvosRelease.parse).whereType<TvosRelease>().toList();

    test('keeps one entry per Flutter version, at its newest tool release', () {
      final List<TvosRelease> collapsed = TvosRelease.collapseToNewestPerFlutterVersion(
        parseAll(<String>[
          'v3.44.7-tvos.1.4.2',
          'v3.44.5-tvos.1.4.0',
          'v3.44.5-tvos.1.3.3',
          'v3.32.8-tvos.1.0.0',
        ]),
      );

      expect(collapsed.map((TvosRelease r) => r.tag), <String>[
        'v3.44.7-tvos.1.4.2',
        'v3.44.5-tvos.1.4.0',
        'v3.32.8-tvos.1.0.0',
      ]);
    });

    test('preserves input order', () {
      final List<TvosRelease> collapsed = TvosRelease.collapseToNewestPerFlutterVersion(
        parseAll(<String>['v3.44.7-tvos.1.4.2', 'v3.32.8-tvos.1.0.0']),
      );
      expect(collapsed.first.flutterVersion, '3.44.7');
      expect(collapsed.last.flutterVersion, '3.32.8');
    });

    test('returns an empty list for empty input', () {
      expect(TvosRelease.collapseToNewestPerFlutterVersion(<TvosRelease>[]), isEmpty);
    });
  });

  group('TvosRelease.withHash', () {
    test('attaches a commit without altering the other fields', () {
      final TvosRelease r = TvosRelease.parse('v3.32.8-tvos.1.0.0')!.withHash('cafebabe');
      expect(r.hash, 'cafebabe');
      expect(r.tag, 'v3.32.8-tvos.1.0.0');
      expect(r.flutterVersion, '3.32.8');
      expect(r.toolVersion, '1.0.0');
    });
  });

  group('TvosReleases.list', () {
    late FakeProcessManager processManager;
    late TvosReleases releases;

    setUp(() {
      processManager = FakeProcessManager.empty();
      releases = TvosReleases(
        workingDirectory: '/repo',
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      );
    });

    test('fetches then lists, dropping non-release tags', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'nightly\nv3.44.7-tvos.1.4.2\nv3.44.1\nv3.32.8-tvos.1.0.0\n',
        ),
      ]);

      final List<TvosRelease> result = await releases.list();

      expect(result.map((TvosRelease r) => r.tag), <String>[
        'v3.44.7-tvos.1.4.2',
        'v3.32.8-tvos.1.0.0',
      ]);
      expect(processManager, hasNoRemainingExpectations);
    });

    test('skips the fetch when asked not to', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'v3.44.7-tvos.1.4.2\n',
        ),
      ]);

      final List<TvosRelease> result = await releases.list(fetch: false);

      expect(result.single.tag, 'v3.44.7-tvos.1.4.2');
      expect(processManager, hasNoRemainingExpectations);
    });

    testUsingContext('a failed fetch warns and falls back to local tags', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'fetch', '--tags'],
          exitCode: 128,
          stderr: 'fatal: unable to access remote',
        ),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'v3.44.7-tvos.1.4.2\n',
        ),
      ]);

      final List<TvosRelease> result = await releases.list();

      // The whole point: offline discovery still yields what git already has.
      expect(result.single.tag, 'v3.44.7-tvos.1.4.2');
      expect(processManager, hasNoRemainingExpectations);
    });

    test('returns an empty list when the repo has no release tags', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'nightly\n',
        ),
      ]);

      expect(await releases.list(), isEmpty);
    });
  });

  group('TvosReleases.resolve', () {
    late FakeProcessManager processManager;
    late TvosReleases releases;

    setUp(() {
      processManager = FakeProcessManager.empty();
      releases = TvosReleases(
        workingDirectory: '/repo',
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      );
    });

    void stubTagList() {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'v3.44.7-tvos.1.4.2\n'
              'v3.44.5-tvos.1.4.0\n'
              'v3.44.5-tvos.1.3.3\n'
              'v3.32.8-tvos.1.0.0\n',
        ),
      ]);
    }

    test('a bare Flutter version picks its newest tool release', () async {
      stubTagList();
      processManager.addCommand(
        const FakeCommand(
          command: <String>['git', 'rev-parse', 'v3.44.5-tvos.1.4.0^{commit}'],
          stdout: 'cafebabecafebabecafebabecafebabecafebabe\n',
        ),
      );

      final TvosRelease r = await releases.resolve('3.44.5');

      expect(r.tag, 'v3.44.5-tvos.1.4.0');
      expect(r.hash, 'cafebabecafebabecafebabecafebabecafebabe');
    });

    test('an exact tag resolves to itself, not the newest for that version', () async {
      stubTagList();
      processManager.addCommand(
        const FakeCommand(
          command: <String>['git', 'rev-parse', 'v3.44.5-tvos.1.3.3^{commit}'],
          stdout: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n',
        ),
      );

      final TvosRelease r = await releases.resolve('v3.44.5-tvos.1.3.3');

      expect(r.tag, 'v3.44.5-tvos.1.3.3');
      expect(r.hash, 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef');
    });

    test('an unknown version exits with the available versions listed', () async {
      stubTagList();

      await expectToolExitLater(
        releases.resolve('3.99.0'),
        allOf(contains('3.99.0'), contains('3.44.7'), contains('3.32.8')),
      );
    });

    test('a tag-shaped selector that does not exist also lists alternatives', () async {
      stubTagList();

      await expectToolExitLater(
        releases.resolve('v3.44.5-tvos.9.9.9'),
        contains('3.44.5'),
      );
    });
  });

  group('TvosReleases git state', () {
    late FakeProcessManager processManager;
    late TvosReleases releases;

    setUp(() {
      processManager = FakeProcessManager.empty();
      releases = TvosReleases(
        workingDirectory: '/repo',
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      );
    });

    test('current() reports the tag when HEAD is exactly on one', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
          stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
        ),
        const FakeCommand(
          command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
          stdout: 'v3.44.7-tvos.1.4.2\n',
        ),
      ]);

      final TvosVersion v = await releases.current();

      expect(v.tag, 'v3.44.7-tvos.1.4.2');
      expect(v.label, 'v3.44.7-tvos.1.4.2');
    });

    test('current() falls back to the short hash on an untagged commit', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
          stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
        ),
        const FakeCommand(
          command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
          exitCode: 128,
        ),
      ]);

      final TvosVersion v = await releases.current();

      expect(v.tag, isNull);
      expect(v.label, 'aaaabbbbcc');
    });

    test('hasUncommittedChanges is true for a dirty tree', () async {
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ' M lib/foo.dart\n'),
      );
      expect(await releases.hasUncommittedChanges(), isTrue);
    });

    test('hasUncommittedChanges is false for a clean tree', () async {
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ''),
      );
      expect(await releases.hasUncommittedChanges(), isFalse);
    });

    test('hasUncommittedChanges fails closed when git cannot be queried', () async {
      // Never report "clean" for a tree we could not inspect: this is the only
      // guard before `git reset --hard`.
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'status', '-s'], exitCode: 127),
      );
      await expectToolExitLater(
        releases.hasUncommittedChanges(),
        contains('could not verify'),
      );
    });

    test('checkout resets hard to the given commit', () async {
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'reset', '--hard', 'cafebabe']),
      );
      await releases.checkout('cafebabe');
      expect(processManager, hasNoRemainingExpectations);
    });
  });
}
