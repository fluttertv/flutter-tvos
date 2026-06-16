// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tvos/tvos_artifacts.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fakes.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;
  late Cache cache;
  late TvosArtifacts artifacts;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
    // tvosArtifactDirectory resolves as `<flutterRoot>/../engine_artifacts`.
    Cache.flutterRoot = '/flutter';
    cache = Cache.test(fileSystem: fileSystem, processManager: processManager);
    artifacts = TvosArtifacts(
      fileSystem: fileSystem,
      cache: cache,
      platform: FakePlatform(operatingSystem: 'macos'),
      operatingSystemUtils: FakeOperatingSystemUtils(),
    );

    // Lay down the patched host SDKs the override points at.
    fileSystem
        .directory('/engine_artifacts/host_release/flutter_patched_sdk')
        .createSync(recursive: true);
    fileSystem
        .directory('/engine_artifacts/host_debug_unopt/flutter_patched_sdk')
        .createSync(recursive: true);
  });

  group('TvosArtifacts patched-SDK override (AOT platform identity)', () {
    test('release flutterPatchedSdkPath resolves to host_release patched SDK', () {
      final String path = artifacts.getArtifactPath(
        Artifact.flutterPatchedSdkPath,
        mode: BuildMode.release,
      );
      expect(path, '/engine_artifacts/host_release/flutter_patched_sdk');
    });

    test('profile platformKernelDill resolves to host_release platform_strong.dill', () {
      final String path = artifacts.getArtifactPath(
        Artifact.platformKernelDill,
        mode: BuildMode.profile,
      );
      expect(
        path,
        '/engine_artifacts/host_release/flutter_patched_sdk/platform_strong.dill',
      );
    });

    test('debug flutterPatchedSdkPath falls through to stock resolution', () {
      // Debug resolves platform identity at runtime via the device engine, so
      // the override is intentionally NOT applied — the path must come from
      // the stock CachedArtifacts logic, not our engine_artifacts host SDK.
      final String path = artifacts.getArtifactPath(
        Artifact.flutterPatchedSdkPath,
        mode: BuildMode.debug,
      );
      expect(path, isNot(contains('engine_artifacts')));
    });

    test('debug platformKernelDill falls through to stock resolution', () {
      final String path = artifacts.getArtifactPath(
        Artifact.platformKernelDill,
        mode: BuildMode.debug,
      );
      expect(path, isNot(contains('engine_artifacts')));
    });

    test('handles the nested directory layout from zip extraction', () {
      fileSystem
          .directory('/engine_artifacts/host_release/host_release/flutter_patched_sdk')
          .createSync(recursive: true);
      final String path = artifacts.getArtifactPath(
        Artifact.flutterPatchedSdkPath,
        mode: BuildMode.release,
      );
      expect(
        path,
        '/engine_artifacts/host_release/host_release/flutter_patched_sdk',
      );
    });
  });
}
