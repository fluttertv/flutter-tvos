// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression test: the AOT compile pipeline must thread the tvOS
// deployment-target flag into BOTH clang steps (assemble + link).
//
// Without it, clang stamps LC_BUILD_VERSION `minos` with the SDK version
// instead of the deployment target, and App Store validation rejects the
// archive with ITMS-90208. The flag value (`tvosVersionMinFlag`) and the argv
// builders (`aotAssembleArgs` / `aotLinkArgs`) are unit-tested in isolation;
// this drives the real `compileAotSnapshot` so the *production call sites*
// can't silently pass an empty flag and stay green.

import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/build_targets/application.dart';
import 'package:flutter_tvos/tvos_artifacts.dart';
import 'package:flutter_tvos/tvos_build_info.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';
import '../src/fakes.dart';

void main() {
  const String kVersionMinFlag = '-mtvos-version-min=13.0';
  const String kSdkPath = '/sdks/AppleTVOS.sdk';

  late MemoryFileSystem fileSystem;
  late Cache cache;
  late TvosArtifacts artifacts;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    // TvosArtifacts resolves its engine dir as <flutterRoot>/../engine_artifacts.
    Cache.flutterRoot = '/flutter';
    cache = Cache.test(fileSystem: fileSystem, processManager: FakeProcessManager.any());
    artifacts = TvosArtifacts(
      fileSystem: fileSystem,
      cache: cache,
      platform: FakePlatform(operatingSystem: 'macos'),
      operatingSystemUtils: FakeOperatingSystemUtils(),
    );
  });

  testUsingContext(
    'compileAotSnapshot passes the tvOS version-min flag to both clang steps '
    '(ITMS-90208)',
    () async {
      // gen_snapshot must exist on disk (the method checks before running it).
      final String genSnapshotPath =
          artifacts.getGenSnapshotPath(BuildMode.release);
      fileSystem.file(genSnapshotPath).createSync(recursive: true);

      final tvosProjectDir = fileSystem.directory('/app/tvos')..createSync(recursive: true);
      fileSystem.file('/app/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: app\nversion: 1.0.0+1\n');
      final FlutterProject project = FlutterProject.fromDirectory(fileSystem.directory('/app'));

      final environment = Environment.test(
        fileSystem.directory('/app')..createSync(recursive: true),
        artifacts: artifacts,
        fileSystem: fileSystem,
        logger: BufferLogger.test(),
        processManager: globals.processManager,
        defines: <String, String>{},
      );
      environment.buildDir.createSync(recursive: true);
      // The kernel snapshot the AOT step consumes.
      environment.buildDir.childFile('app.dill').createSync(recursive: true);

      const buildInfo = TvosBuildInfo(BuildInfo.release, targetArch: 'arm64');
      final bundle = NativeTvosBundle(buildInfo, 'lib/main.dart');

      await bundle.compileAotSnapshot(project, tvosProjectDir, environment);

      expect(globals.processManager, hasNoRemainingExpectations);
      // The App.framework the link step produced.
      expect(tvosProjectDir.childDirectory('Flutter').childDirectory('App.framework'), exists);
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      Artifacts: () => artifacts,
      ProcessManager: () {
        return FakeProcessManager.list(<FakeCommand>[
          // 1. gen_snapshot → assembly (5 args for the empty-defines case).
          //    Not under test; match loosely.
          FakeCommand(
            command: <Pattern>[
              artifacts.getGenSnapshotPath(BuildMode.release),
              ...List<Pattern>.filled(4, RegExp(r'.*')),
            ],
          ),
          // 2. xcrun resolves the SDK path for the assemble step.
          const FakeCommand(
            command: <String>['xcrun', '--sdk', 'appletvos', '--show-sdk-path'],
            stdout: '$kSdkPath\n',
          ),
          // 3. cc assembles the object — MUST carry the version-min flag.
          FakeCommand(
            command: <Pattern>['xcrun', 'cc', ...List<Pattern>.filled(9, RegExp(r'.*'))],
            onRun: (List<String> args) {
              expect(args, contains(kVersionMinFlag));
              expect(args, contains('-isysroot'));
              expect(args, contains(kSdkPath));
            },
          ),
          // 4. xcrun resolves the SDK path again for the link step.
          const FakeCommand(
            command: <String>['xcrun', '--sdk', 'appletvos', '--show-sdk-path'],
            stdout: '$kSdkPath\n',
          ),
          // 5. clang links App.framework/App — MUST carry the version-min flag.
          FakeCommand(
            command: <Pattern>['xcrun', 'clang', ...List<Pattern>.filled(19, RegExp(r'.*'))],
            onRun: (List<String> args) {
              expect(args, contains(kVersionMinFlag));
              expect(args, contains('-dynamiclib'));
              expect(args, contains(kSdkPath));
            },
          ),
        ]);
      },
    },
  );
}
