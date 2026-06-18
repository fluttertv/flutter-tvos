// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/compile.dart';
import 'package:flutter_tvos/build_targets/application.dart';

import '../src/common.dart';
import '../src/fake_process_manager.dart';

const String kBoundaryKey = '4d2d9609-c662-4571-afde-31410f96caa6';

void main() {
  late FakeProcessManager processManager;
  late Environment environment;
  late Artifacts artifacts;
  late FileSystem fileSystem;
  late Logger logger;

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    // Stock test artifacts: this isolates the build() targetOS behaviour from
    // TvosArtifacts' patched-SDK override (tested separately). The sdk-root
    // below therefore resolves to the stock test path.
    artifacts = Artifacts.test();
    fileSystem = MemoryFileSystem.test();
    fileSystem.file('.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"configVersion": 2, "packages":[]}');
  });

  Environment buildEnv(BuildMode mode) {
    final env = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kBuildMode: mode.cliName,
        // tvOS rides the iOS pipeline.
        kTargetPlatform: getNameForTargetPlatform(TargetPlatform.ios),
      },
      inputs: <String, String>{},
      artifacts: artifacts,
      processManager: processManager,
      fileSystem: fileSystem,
      logger: logger,
    );
    env.buildDir.createSync(recursive: true);
    return env;
  }

  group('TvosKernelSnapshot.build (AOT platform identity)', () {
    test('does NOT pass --target-os for a profile (AOT) build', () async {
      environment = buildEnv(BuildMode.profile);
      final String build = environment.buildDir.path;
      final String sdkPath = artifacts.getArtifactPath(
        Artifact.flutterPatchedSdkPath,
        platform: TargetPlatform.ios,
        mode: BuildMode.profile,
      );

      List<String>? captured;
      processManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: <String>[
            artifacts.getArtifactPath(Artifact.engineDartAotRuntime),
            artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
            '--sdk-root',
            '$sdkPath/',
            '--target=flutter',
            '--no-print-incremental-dependencies',
            ...buildModeOptions(BuildMode.profile, <String>[]),
            '--track-widget-creation',
            '--aot',
            '--tfa',
            // NOTE: the upstream KernelSnapshot emits '--target-os', 'ios'
            // right here. Its deliberate absence is the platform-identity fix.
            '--packages',
            '/.dart_tool/package_config.json',
            '--output-dill',
            '$build/app.dill',
            '--depfile',
            '$build/kernel_snapshot_program.d',
            '--verbosity=error',
            'file:///lib/main.dart',
          ],
          onRun: (List<String> command) => captured = command,
          stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n',
        ),
      ]);

      await const TvosKernelSnapshot().build(environment);

      // Primary guard: the recorded frontend-server invocation must not carry
      // a target OS, or gen_snapshot would const-fold Platform.operatingSystem
      // to "ios" and tvOS apps would mis-identify in release.
      expect(captured, isNotNull);
      expect(captured, isNot(contains('--target-os')));
      expect(processManager, hasNoRemainingExpectations);
    });

    test('still produces a valid kernel command for release (AOT)', () async {
      environment = buildEnv(BuildMode.release);
      final String build = environment.buildDir.path;
      final String sdkPath = artifacts.getArtifactPath(
        Artifact.flutterPatchedSdkPath,
        platform: TargetPlatform.ios,
        mode: BuildMode.release,
      );

      processManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: <String>[
            artifacts.getArtifactPath(Artifact.engineDartAotRuntime),
            artifacts.getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk),
            '--sdk-root',
            '$sdkPath/',
            '--target=flutter',
            '--no-print-incremental-dependencies',
            ...buildModeOptions(BuildMode.release, <String>[]),
            // release does not track widget creation
            '--aot',
            '--tfa',
            '--packages',
            '/.dart_tool/package_config.json',
            '--output-dill',
            '$build/app.dill',
            '--depfile',
            '$build/kernel_snapshot_program.d',
            '--verbosity=error',
            'file:///lib/main.dart',
          ],
          stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n',
        ),
      ]);

      await const TvosKernelSnapshot().build(environment);
      expect(processManager, hasNoRemainingExpectations);
    });

    test('throws MissingDefineException when build mode is absent', () async {
      environment = buildEnv(BuildMode.profile);
      environment.defines.remove(kBuildMode);
      await expectLater(
        () => const TvosKernelSnapshot().build(environment),
        throwsException,
      );
    });
  });
}
