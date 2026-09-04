// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Guards the production call site of engine signing, not the signer itself
// (TvosEngineSigner has its own unit tests).
//
// Three properties matter here, and none of them is visible from the signer's
// own tests: that signing runs at all, that it runs BEFORE the staging copy,
// and that it is skipped for the simulator. Driving `signAndStageEngine`
// against a strict FakeProcessManager pins all three — the fake enforces
// command order, so signing moved after the copy fails as loudly as signing
// deleted outright.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tvos/build_targets/application.dart';
import 'package:flutter_tvos/tvos_artifacts.dart';
import 'package:flutter_tvos/tvos_build_info.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';
import '../src/fakes.dart';

/// One Apple Distribution certificate, so `resolveIdentity` has something to
/// pick -- the certificate every developer who can upload to TestFlight holds.
const String _identities = '''
  1) CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC "Apple Distribution: Someone (TEAM123456)"
     1 valid identity found
''';

const List<String> _findIdentity = <String>[
  'security',
  'find-identity',
  '-v',
  '-p',
  'codesigning',
];

void main() {
  late MemoryFileSystem fileSystem;
  late Cache cache;
  late TvosArtifacts artifacts;

  /// Lays down BOTH engine variants in the cache, plus the project directory.
  ///
  /// Both matter even when only one is staged: the signer resolves the
  /// *physical* variant unconditionally and returns early if that directory is
  /// absent. Seeding only the simulator variant would let a dropped
  /// `!buildInfo.simulator` guard pass this suite, because signing would bail
  /// on the missing path instead of running.
  String cachePathFor({required bool simulator}) => artifacts.getArtifactPath(
        Artifact.flutterFramework,
        mode: BuildMode.debug,
        environmentType: simulator ? EnvironmentType.simulator : EnvironmentType.physical,
      );

  String seedCache(bool simulator) {
    for (final sim in <bool>[false, true]) {
      fileSystem.directory(cachePathFor(simulator: sim)).createSync(recursive: true);
    }
    fileSystem.directory('/project/tvos').createSync(recursive: true);
    return cachePathFor(simulator: simulator);
  }

  NativeTvosBundle bundle({required bool simulator}) => NativeTvosBundle(
        TvosBuildInfo(
          const BuildInfo(BuildMode.debug, null, treeShakeIcons: false, packageConfigPath: '.dart_tool/package_config.json'),
          targetArch: 'arm64',
          simulator: simulator,
        ),
        'lib/main.dart',
      );

  setUp(() {
    fileSystem = MemoryFileSystem.test();
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
    'a device build signs the engine cache BEFORE staging it',
    () async {
      final String cachePath = seedCache(false);
      bundle(simulator: false).signAndStageEngine(fileSystem.directory('/project/tvos'));

      // FakeProcessManager.list is order-sensitive: the copy is only reached
      // after both signing calls, so a signing step moved after the staging
      // copy — or removed — leaves expectations unmet.
      expect(globals.processManager, hasNoRemainingExpectations);
      expect(cachePath, isNotEmpty);
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      Artifacts: () => artifacts,
      Platform: () => FakePlatform(operatingSystem: 'macos', environment: <String, String>{}),
      ProcessManager: () => FakeProcessManager.list(<FakeCommand>[
            const FakeCommand(command: _findIdentity, stdout: _identities),
            FakeCommand(
              command: <Pattern>[
                'codesign',
                '--force',
                '--timestamp',
                '--options',
                'runtime',
                '--sign',
                'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
                RegExp(r'.*Flutter\.framework$'),
              ],
            ),
            FakeCommand(
              command: <Pattern>['cp', '-R', RegExp(r'.*'), '/project/tvos/Flutter/Flutter.framework'],
            ),
          ]),
    },
  );

  testUsingContext(
    'a simulator build stages without signing',
    () async {
      seedCache(true);
      bundle(simulator: true).signAndStageEngine(fileSystem.directory('/project/tvos'));

      // No `security find-identity` is expected: requiring a Developer ID for
      // simulator work would block developers who do not have one.
      expect(globals.processManager, hasNoRemainingExpectations);
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      Artifacts: () => artifacts,
      Platform: () => FakePlatform(operatingSystem: 'macos', environment: <String, String>{}),
      ProcessManager: () => FakeProcessManager.list(<FakeCommand>[
            FakeCommand(
              command: <Pattern>['cp', '-R', RegExp(r'.*'), '/project/tvos/Flutter/Flutter.framework'],
            ),
          ]),
    },
  );
}
