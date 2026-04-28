// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tvos/tvos_application_package.dart';

import '../src/common.dart';
import '../src/context.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
  });

  group('TvosApp', () {
    testUsingContext(
      'bundlePath returns correct path for debug simulator',
      () {
        final Directory projectDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);
        final app = TvosApp(id: 'com.example.test', projectDirectory: projectDir);

        final String path = app.bundlePath(BuildMode.debug, isSimulator: true);
        expect(path, contains('Debug-appletvsimulator'));
        expect(path, endsWith('Runner.app'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'bundlePath returns correct path for release device',
      () {
        final Directory projectDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);
        final app = TvosApp(id: 'com.example.test', projectDirectory: projectDir);

        final String path = app.bundlePath(BuildMode.release);
        expect(path, contains('Release-appletvos'));
        expect(path, endsWith('Runner.app'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testWithoutContext('name returns directory basename', () {
      final Directory projectDir = fileSystem.directory('/my_app/tvos')
        ..createSync(recursive: true);
      final app = TvosApp(id: 'com.example.test', projectDirectory: projectDir);

      expect(app.name, equals('tvos'));
    });
  });
}
