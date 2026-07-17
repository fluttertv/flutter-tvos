// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression test for issue #34: custom fragment shaders must render on tvOS.
//
// tvOS rides the iOS engine (Impeller/Metal). TvosCopyFlutterBundle.build is a
// hand-mirror of upstream CopyFlutterBundle.build whose ONLY intended change is
// passing `targetPlatform: TargetPlatform.ios` to copyAssets (upstream
// hard-codes TargetPlatform.android). That argument is what drives impellerc's
// runtime-stage flags: android yields SkSL/GLES/Vulkan, ios yields Metal. If a
// Flutter upgrade re-mirrors the target and drops the `.ios`, shaders bundle
// without the Metal stage and every `.frag` fails at runtime with "does not
// contain appropriate runtime stage data for current backend (Metal)".
//
// The argv-level statics elsewhere are unit-tested; this test guards the actual
// production call site, driving the real target so a wrong constant can't stay
// green.

import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tvos/build_targets/application.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';
import '../src/package_config.dart';

void main() {
  late MemoryFileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
  });

  testUsingContext(
    'TvosCopyFlutterBundle compiles shaders with the Metal runtime stage (#34)',
    () async {
      final artifacts = Artifacts.test();
      final environment = Environment.test(
        fileSystem.currentDirectory,
        processManager: globals.processManager,
        artifacts: artifacts,
        fileSystem: fileSystem,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
        defines: <String, String>{kBuildMode: BuildMode.debug.cliName},
      );
      environment.buildDir.createSync(recursive: true);

      // Debug bundle copies the prebuilt runtimes + kernel blob first.
      fileSystem
          .file(artifacts.getArtifactPath(Artifact.vmSnapshotData, mode: BuildMode.debug))
          .createSync(recursive: true);
      fileSystem
          .file(artifacts.getArtifactPath(Artifact.isolateSnapshotData, mode: BuildMode.debug))
          .createSync(recursive: true);
      environment.buildDir.childFile('app.dill').createSync(recursive: true);

      final String impellercPath = artifacts.getHostArtifact(HostArtifact.impellerc).path;
      fileSystem.file(impellercPath).createSync(recursive: true);

      fileSystem.file('pubspec.yaml')
        ..createSync()
        ..writeAsStringSync('''
name: example
flutter:
  shaders:
    - shaders/ripple.frag
''');
      writePackageConfigFiles(directory: fileSystem.currentDirectory, mainLibName: 'example');
      fileSystem.file('shaders/ripple.frag')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');

      await const TvosCopyFlutterBundle().build(environment);

      expect(
        fileSystem.file('${environment.outputDir.path}/shaders/ripple.frag'),
        exists,
      );
      expect(globals.processManager, hasNoRemainingExpectations);
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      Platform: () => FakePlatform(),
      ProcessManager: () => FakeProcessManager.list(<FakeCommand>[
            FakeCommand(
              // 9 args: impellerc + [--runtime-stage-metal] + 7 fixed flags.
              command: <Pattern>[
                RegExp(r'.*impellerc.*'),
                ...List<Pattern>.filled(8, RegExp(r'.*')),
              ],
              onRun: (List<String> args) {
                // The whole point: iOS/Metal shader target, never the
                // android SkSL/GLES/Vulkan stages.
                expect(args, contains('--runtime-stage-metal'));
                expect(args, isNot(contains('--runtime-stage-gles')));
                expect(args, isNot(contains('--runtime-stage-gles3')));
                expect(args, isNot(contains('--runtime-stage-vulkan')));
                expect(args, isNot(contains('--sksl')));
                // Materialize the compiler outputs so the bundle can include
                // the shader (FakeProcessManager won't create them).
                for (final String arg in args) {
                  if (arg.startsWith('--sl=')) {
                    fileSystem.file(arg.substring('--sl='.length)).createSync(recursive: true);
                  } else if (arg.startsWith('--spirv=')) {
                    fileSystem.file(arg.substring('--spirv='.length)).createSync(recursive: true);
                  }
                }
              },
            ),
          ]),
    },
  );
}
