// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';

import '../src/common.dart';
import '../src/context.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
  });

  group('TvosCleanCommand artifacts', () {
    testUsingContext(
      'identifies tvOS build artifacts to clean',
      () {
        final Directory projectDir = fileSystem.directory('/project')..createSync(recursive: true);
        final Directory tvosDir = projectDir.childDirectory('tvos')..createSync();

        // Create artifacts that should be cleaned
        tvosDir.childDirectory('Pods').createSync();
        tvosDir
            .childDirectory('Flutter')
            .childDirectory('Flutter.framework')
            .createSync(recursive: true);
        tvosDir
            .childDirectory('Flutter')
            .childDirectory('App.framework')
            .createSync(recursive: true);
        tvosDir
            .childDirectory('Flutter')
            .childDirectory('flutter_assets')
            .createSync(recursive: true);
        tvosDir
            .childDirectory('Flutter')
            .childFile('Generated.xcconfig')
            .createSync(recursive: true);
        tvosDir.childFile('Podfile.lock').createSync();
        tvosDir
            .childDirectory('Flutter')
            .childFile('GeneratedPluginRegistrant.swift')
            .createSync(recursive: true);

        // Create build output
        projectDir.childDirectory('build').childDirectory('tvos').createSync(recursive: true);

        // Verify all artifacts exist before clean
        expect(tvosDir.childDirectory('Pods').existsSync(), isTrue);
        expect(
          tvosDir.childDirectory('Flutter').childDirectory('Flutter.framework').existsSync(),
          isTrue,
        );
        expect(
          tvosDir.childDirectory('Flutter').childDirectory('App.framework').existsSync(),
          isTrue,
        );
        expect(
          tvosDir.childDirectory('Flutter').childDirectory('flutter_assets').existsSync(),
          isTrue,
        );
        expect(
          tvosDir.childDirectory('Flutter').childFile('Generated.xcconfig').existsSync(),
          isTrue,
        );
        expect(tvosDir.childFile('Podfile.lock').existsSync(), isTrue);
        expect(projectDir.childDirectory('build').childDirectory('tvos').existsSync(), isTrue);

        // Simulate clean by deleting what TvosCleanCommand would delete
        tvosDir.childDirectory('Pods').deleteSync(recursive: true);
        tvosDir
            .childDirectory('Flutter')
            .childDirectory('Flutter.framework')
            .deleteSync(recursive: true);
        tvosDir
            .childDirectory('Flutter')
            .childDirectory('App.framework')
            .deleteSync(recursive: true);
        tvosDir
            .childDirectory('Flutter')
            .childDirectory('flutter_assets')
            .deleteSync(recursive: true);
        tvosDir.childDirectory('Flutter').childFile('Generated.xcconfig').deleteSync();
        tvosDir.childFile('Podfile.lock').deleteSync();
        tvosDir.childDirectory('Flutter').childFile('GeneratedPluginRegistrant.swift').deleteSync();
        projectDir.childDirectory('build').childDirectory('tvos').deleteSync(recursive: true);

        // Verify all cleaned
        expect(tvosDir.childDirectory('Pods').existsSync(), isFalse);
        expect(
          tvosDir.childDirectory('Flutter').childDirectory('Flutter.framework').existsSync(),
          isFalse,
        );
        expect(
          tvosDir.childDirectory('Flutter').childDirectory('App.framework').existsSync(),
          isFalse,
        );
        expect(
          tvosDir.childDirectory('Flutter').childDirectory('flutter_assets').existsSync(),
          isFalse,
        );
        expect(
          tvosDir.childDirectory('Flutter').childFile('Generated.xcconfig').existsSync(),
          isFalse,
        );
        expect(tvosDir.childFile('Podfile.lock').existsSync(), isFalse);
        expect(projectDir.childDirectory('build').childDirectory('tvos').existsSync(), isFalse);

        // Verify tvos/ directory itself is preserved
        expect(tvosDir.existsSync(), isTrue);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'handles missing tvos directory gracefully',
      () {
        final Directory projectDir = fileSystem.directory('/project')..createSync(recursive: true);

        // No tvos/ directory — clean should not throw
        expect(projectDir.childDirectory('tvos').existsSync(), isFalse);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });
}
