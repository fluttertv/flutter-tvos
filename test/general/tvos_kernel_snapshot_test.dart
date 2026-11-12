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
import '../src/context.dart';
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

  /// What the frontend server does with `--recorded-uses` in an AOT build.
  void writeRecordedUses(String buildDir) {
    fileSystem.file('$buildDir/recorded_uses.json').writeAsStringSync('{}');
  }

  Environment buildEnv(BuildMode mode) {
    final env = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kBuildMode: mode.cliName,
        // tvOS rides the iOS pipeline.
        kTargetPlatform: TargetPlatform.ios.getName(),
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
    testUsingContext('does NOT pass --target-os for a profile (AOT) build', () async {
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
            // Flutter 3.50 renamed the frontend server's --track-widget-creation.
            '--track-creation-locations',
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
            // Every AOT build since Flutter 3.50 (see the record-use group).
            '--recorded-uses=$build/recorded_uses.json',
            'file:///lib/main.dart',
          ],
          onRun: (List<String> command) {
            captured = command;
            writeRecordedUses(build);
          },
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

    testUsingContext('still produces a valid kernel command for release (AOT)', () async {
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
            '--recorded-uses=$build/recorded_uses.json',
            'file:///lib/main.dart',
          ],
          onRun: (_) => writeRecordedUses(build),
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

  // KernelSnapshot.outputs — which TvosKernelSnapshot inherits — declares
  // recorded_uses.json. Up to Flutter 3.47 only while the record-use feature
  // was on; since 3.50 always, because the icon tree shaker reads it in every
  // AOT build too. A declared output that nothing writes fails the build, so
  // build() has to produce it in both compilation modes, and an AOT build whose
  // compiler wrote none fails as stock's does.
  group('TvosKernelSnapshot.build (record-use output)', () {
    testUsingContext('asks the frontend server for recorded uses in AOT', () async {
      environment = buildEnv(BuildMode.profile);
      final String build = environment.buildDir.path;
      final String sdkPath = artifacts.getArtifactPath(
        Artifact.flutterPatchedSdkPath,
        platform: TargetPlatform.ios,
        mode: BuildMode.profile,
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
            ...buildModeOptions(BuildMode.profile, <String>[]),
            // Flutter 3.50 renamed the frontend server's --track-widget-creation.
            '--track-creation-locations',
            '--aot',
            '--tfa',
            '--packages',
            '/.dart_tool/package_config.json',
            '--output-dill',
            '$build/app.dill',
            '--depfile',
            '$build/kernel_snapshot_program.d',
            '--verbosity=error',
            // Carried in as an extra front-end option, so it lands after
            // --verbosity=error and before the main URI.
            '--recorded-uses=$build/recorded_uses.json',
            'file:///lib/main.dart',
          ],
          onRun: (_) => writeRecordedUses(build),
          stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n',
        ),
      ]);

      await const TvosKernelSnapshot().build(environment);
      expect(processManager, hasNoRemainingExpectations);
    });

    testUsingContext('fails an AOT build whose compiler wrote no recorded uses', () async {
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
            '--aot',
            '--tfa',
            '--packages',
            '/.dart_tool/package_config.json',
            '--output-dill',
            '$build/app.dill',
            '--depfile',
            '$build/kernel_snapshot_program.d',
            '--verbosity=error',
            '--recorded-uses=$build/recorded_uses.json',
            'file:///lib/main.dart',
          ],
          stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n',
        ),
      ]);

      await expectLater(
        () => const TvosKernelSnapshot().build(environment),
        throwsA(
          isException.having(
            (Exception e) => e.toString(),
            'message',
            contains('recorded_uses.json was not generated by the compiler.'),
          ),
        ),
      );
      expect(processManager, hasNoRemainingExpectations);
    });

    testUsingContext('writes an empty recorded-uses file in JIT', () async {
      environment = buildEnv(BuildMode.debug);
      final String build = environment.buildDir.path;
      final String sdkPath = artifacts.getArtifactPath(
        Artifact.flutterPatchedSdkPath,
        platform: TargetPlatform.ios,
        mode: BuildMode.debug,
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
            ...buildModeOptions(BuildMode.debug, <String>[]),
            // Flutter 3.50 renamed the frontend server's --track-widget-creation.
            '--track-creation-locations',
            '--no-link-platform',
            '--packages',
            '/.dart_tool/package_config.json',
            '--output-dill',
            '$build/app.dill',
            '--depfile',
            '$build/kernel_snapshot_program.d',
            '--incremental',
            '--initialize-from-dill',
            '$build/app.dill',
            '--verbosity=error',
            'file:///lib/main.dart',
          ],
          stdout: 'result $kBoundaryKey\n$kBoundaryKey\n$kBoundaryKey $build/app.dill 0\n',
        ),
      ]);

      // A stale file from an earlier AOT build must not survive into JIT.
      environment.buildDir.childFile('recorded_uses.json').writeAsStringSync('{"stale": true}');

      await const TvosKernelSnapshot().build(environment);

      // JIT gets no --recorded-uses flag; the file is written directly so the
      // declared output exists.
      expect(
        environment.buildDir.childFile('recorded_uses.json').readAsStringSync(),
        '{}',
      );
      expect(processManager, hasNoRemainingExpectations);
    });
  });
}
