// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/commands/versions.dart';
import 'package:flutter_tvos/tvos_releases.dart';

import '../src/context.dart';
import '../src/test_flutter_command_runner.dart';

void main() {
  setUpAll(() {
    Cache.disableLocking();
  });

  late FakeProcessManager processManager;
  late BufferLogger logger;
  late TvosReleases releases;

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    releases = TvosReleases(
      workingDirectory: '/repo',
      processUtils: ProcessUtils(processManager: processManager, logger: logger),
    );
  });

  void stubTagsAndHead({String headTag = 'v3.44.7-tvos.1.4.2'}) {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: 'v3.44.7-tvos.1.4.2\n'
            'v3.44.5-tvos.1.4.0\n'
            'v3.44.5-tvos.1.3.3\n'
            'v3.32.8-tvos.1.0.0\n',
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

  testUsingContext('lists one line per Flutter version at its newest tool release', () async {
    stubTagsAndHead();
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    final String out = logger.statusText;
    expect(out, contains('3.44.7'));
    expect(out, contains('3.44.5'));
    expect(out, contains('3.32.8'));
    // 1.3.3 is the older tool release of 3.44.5 and must be collapsed away.
    expect(out, isNot(contains('1.3.3')));
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('marks exactly one line as current', () async {
    stubTagsAndHead();
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    expect('(current)'.allMatches(logger.statusText).length, 1);
    expect(
      logger.statusText.split('\n').firstWhere((String l) => l.contains('(current)')),
      contains('3.44.7'),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('marks nothing current when HEAD is untagged', () async {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: 'v3.44.7-tvos.1.4.2\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        exitCode: 128,
      ),
    ]);
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    expect(logger.statusText, isNot(contains('(current)')));
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('--all shows every release tag ungrouped', () async {
    stubTagsAndHead();
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions', '--all']);

    expect(logger.statusText, contains('v3.44.5-tvos.1.4.0'));
    expect(logger.statusText, contains('v3.44.5-tvos.1.3.3'));
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('says so when no releases are known', () async {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(command: <String>['git', 'tag', '-l', '--sort=-v:refname']),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        exitCode: 128,
      ),
    ]);
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    expect(logger.statusText, contains('No flutter-tvos releases'));
  }, overrides: <Type, Generator>{Logger: () => logger});
}
