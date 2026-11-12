// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// `TvosEngineArtifacts.update` with no engine pin. Flutter 3.50's stock
// `CachedArtifact.update` returns before `updateInner` when an artifact has no
// version; the tvOS engine is still looked for, as it was up to Flutter 3.47.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/tvos_cache.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_http_client.dart';
import '../src/fake_process_manager.dart';
import '../src/fakes.dart';

void main() {
  late MemoryFileSystem fs;
  late FakeProcessManager processManager;
  late FakePlatform platform;
  late BufferLogger logger;

  setUp(() {
    fs = MemoryFileSystem.test();
    // The CLI checkout is /ws/cli, its SDK /ws/cli/flutter, and the
    // monorepo's local zips /ws/artifacts. No bin/internal/engine.version.
    Cache.flutterRoot = '/ws/cli/flutter';
    fs.directory(Cache.flutterRoot).createSync(recursive: true);
    processManager = FakeProcessManager.empty();
    platform = FakePlatform(operatingSystem: 'macos');
    logger = BufferLogger.test();
  });

  TvosEngineArtifacts makeArtifacts() => TvosEngineArtifacts(
    Cache.test(processManager: processManager, fileSystem: fs, platform: platform, logger: logger),
    logger: logger,
    platform: platform,
    processManager: processManager,
  );

  ArtifactUpdater makeUpdater() => ArtifactUpdater(
    operatingSystemUtils: FakeOperatingSystemUtils(),
    logger: logger,
    fileSystem: fs,
    tempStorage: fs.directory('/tmp')..createSync(recursive: true),
    httpClient: FakeHttpClient.any(),
    platform: platform,
    allowedBaseUrls: const <String>[],
  );

  Map<Type, Generator> overrides() => <Type, Generator>{
    FileSystem: () => fs,
    ProcessManager: () => processManager,
    Platform: () => platform,
  };

  group('with no engine pin', () {
    testUsingContext('update still stops with the hint to run precache', () async {
      await expectLater(
        () => makeArtifacts().update(makeUpdater(), logger, fs, FakeOperatingSystemUtils()),
        throwsToolExit(message: 'Run `flutter-tvos precache`'),
      );
      expect(processManager, hasNoRemainingExpectations);
    }, overrides: overrides());

    testUsingContext('update still extracts the local artifact zips, and warns', () async {
      fs.file('/ws/artifacts/tvos_debug_sim_arm64.zip').createSync(recursive: true);
      processManager.addCommand(
        const FakeCommand(
          command: <String>[
            'unzip',
            '-q',
            '/ws/artifacts/tvos_debug_sim_arm64.zip',
            '-d',
            '/ws/cli/engine_artifacts',
          ],
        ),
      );

      await makeArtifacts().update(makeUpdater(), logger, fs, FakeOperatingSystemUtils());

      expect(processManager, hasNoRemainingExpectations);
      expect(logger.warningText, contains('No known version for the artifact name'));
    }, overrides: overrides());
  });
}
