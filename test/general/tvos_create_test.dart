// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/commands/create.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/test_flutter_command_runner.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;

  setUpAll(() {
    Cache.disableLocking();
  });

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
    Cache.flutterRoot = '/flutter';
    fileSystem.directory('/flutter').createSync(recursive: true);
  });

  group('TvosCreateCommand project name', () {
    testUsingContext(
      'derives the name from the current directory for `create .`',
      () async {
        final Directory projectDir = fileSystem.directory('/home/my_tv_app')
          ..createSync(recursive: true);
        fileSystem.currentDirectory = projectDir;

        await createTestCommandRunner(
          TvosCreateCommand(verboseHelp: false),
        ).run(<String>['create', '--tvos-only', '--no-pub', '.']);

        expect(
          projectDir.childFile('pubspec.yaml').readAsStringSync(),
          contains('name: my_tv_app'),
        );
        expect(
          projectDir.childDirectory('lib').childFile('main.dart').readAsStringSync(),
          contains('MyTvAppApp'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'derives the name from the target directory basename',
      () async {
        await createTestCommandRunner(
          TvosCreateCommand(verboseHelp: false),
        ).run(<String>['create', '--tvos-only', '--no-pub', '/home/other_app']);

        expect(
          fileSystem.file('/home/other_app/pubspec.yaml').readAsStringSync(),
          contains('name: other_app'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      '--project-name still wins over the directory name',
      () async {
        await createTestCommandRunner(TvosCreateCommand(verboseHelp: false)).run(<String>[
          'create',
          '--tvos-only',
          '--no-pub',
          '--project-name=chosen_name',
          '/home/ignored_dir',
        ]);

        expect(
          fileSystem.file('/home/ignored_dir/pubspec.yaml').readAsStringSync(),
          contains('name: chosen_name'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'rejects a directory name that is not a valid Dart package name',
      () async {
        final Directory projectDir = fileSystem.directory('/home/my-tv-app')
          ..createSync(recursive: true);
        fileSystem.currentDirectory = projectDir;

        await expectLater(
          createTestCommandRunner(
            TvosCreateCommand(verboseHelp: false),
          ).run(<String>['create', '--tvos-only', '--no-pub', '.']),
          throwsToolExit(message: 'is not a valid Dart package name'),
        );
        expect(projectDir.childFile('pubspec.yaml').existsSync(), isFalse);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });
}
