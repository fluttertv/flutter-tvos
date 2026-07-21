// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

import 'tvos_cache.dart';

/// Overrides [CachedArtifacts] to provide tvOS-specific engine artifacts.
///
/// Directory naming convention:
///   - `tvos_debug_arm64`          — Debug device (arm64)
///   - `tvos_debug_sim_arm64`      — Debug simulator (arm64)
///   - `tvos_profile_arm64`        — Profile device (arm64)
///   - `tvos_release_arm64`        — Release device (arm64)
class TvosArtifacts extends CachedArtifacts {
  TvosArtifacts({
    required super.fileSystem,
    required super.cache,
    required super.platform,
    required super.operatingSystemUtils,
  }) : _fileSystem = fileSystem;

  final FileSystem _fileSystem;

  @override
  LocalEngineInfo? get localEngineInfo => null;

  @override
  String getArtifactPath(
    Artifact artifact, {
    TargetPlatform? platform,
    BuildMode? mode,
    EnvironmentType? environmentType,
  }) {
    if (artifact == Artifact.flutterXcframework ||
        artifact == Artifact.flutterFramework ||
        artifact == Artifact.genSnapshot) {
      final String engineDir = _resolveEngineDirectory(mode ?? BuildMode.debug, environmentType);

      if (artifact == Artifact.genSnapshot) {
        return _fileSystem.path.join(engineDir, 'clang_arm64', 'gen_snapshot');
      } else if (artifact == Artifact.flutterFramework) {
        return _fileSystem.path.join(engineDir, 'Flutter.framework');
      } else if (artifact == Artifact.flutterXcframework) {
        return _fileSystem.path.join(engineDir, 'Flutter.xcframework');
      }
    }

    // Compile the app kernel against OUR patched `flutter_patched_sdk`
    // (shipped inside the host engine artifact) rather than the stock Flutter
    // checkout's. The patched dart:io `platform.dart` defines
    // `isIOS = operatingSystem == "ios" || == "tvos"` and adds the `isTvOS`
    // getter, so the un-folded platform-const getters evaluate correctly at
    // runtime on tvOS. This is the companion to `TvosKernelSnapshot.build()`,
    // which passes `targetOS: null` so those getters are not const-folded to
    // "ios" at compile time.
    //
    // This applies to debug as well, not just AOT. Platform identity *values*
    // do resolve at runtime in JIT — dart:io comes from the device engine's
    // own patched core libraries — so for `operatingSystem` and `isIOS` the
    // compile SDK genuinely is irrelevant there. But `isTvOS` is a member the
    // stock SDK does not declare at all, and the frontend server type-checks
    // against the compile SDK before anything runs: an app touching
    // `Platform.isTvOS` failed to build in debug with
    // `Member not found: 'isTvOS'` while compiling fine in profile/release.
    // Pointing debug at the same patched SDK (which `host_debug_unopt` already
    // ships) makes the getter exist in every mode.
    if (artifact == Artifact.flutterPatchedSdkPath ||
        artifact == Artifact.platformKernelDill) {
      final String patchedSdkDir = _hostPatchedSdkDirectory(mode ?? BuildMode.debug);
      if (artifact == Artifact.platformKernelDill) {
        return _fileSystem.path.join(patchedSdkDir, 'platform_strong.dill');
      }
      return patchedSdkDir;
    }

    return super.getArtifactPath(
      artifact,
      platform: platform,
      mode: mode,
      environmentType: environmentType,
    );
  }

  /// Path to the patched `flutter_patched_sdk` inside the host engine
  /// artifact for [mode].
  ///
  /// Release uses the **product** SDK (`host_release`); profile uses the
  /// **non-product** SDK (`host_debug_unopt`). This mirrors stock Flutter's
  /// `flutter_patched_sdk` (debug/profile) vs `flutter_patched_sdk_product`
  /// (release) split: the non-product SDK marks entry-point classes that the
  /// profile/JIT engine looks up natively — e.g. `dart:io`'s
  /// `_NetworkProfiling` — so gen_snapshot keeps them through AOT
  /// tree-shaking. Compiling a profile build against the product SDK drops
  /// those classes and the engine aborts at startup with
  /// `Type '_NetworkProfiling' not found in library 'dart.io'`.
  String _hostPatchedSdkDirectory(BuildMode mode) {
    final dirName = mode == BuildMode.release ? 'host_release' : 'host_debug_unopt';
    // Handle the nested directory that zip extraction can produce
    // (`<root>/<dir>/<dir>/flutter_patched_sdk`).
    final Directory nested = _fileSystem.directory(
      _fileSystem.path.join(_tvosArtifactRoot, dirName, dirName, 'flutter_patched_sdk'),
    );
    if (nested.existsSync()) {
      return nested.path;
    }
    return _fileSystem.path.join(_tvosArtifactRoot, dirName, 'flutter_patched_sdk');
  }

  String get _tvosArtifactRoot {
    return tvosArtifactDirectory(globals.fs).path;
  }

  /// Resolves the engine directory for the given build configuration.
  String _resolveEngineDirectory(BuildMode mode, EnvironmentType? environmentType) {
    final String dirName = _getDirectoryName(mode, environmentType);

    // Handle nested directory (from zip extraction where dir is inside dir)
    final Directory nestedDir = _fileSystem.directory(
      _fileSystem.path.join(_tvosArtifactRoot, dirName, dirName),
    );
    if (nestedDir.existsSync()) {
      return nestedDir.path;
    }
    return _fileSystem.path.join(_tvosArtifactRoot, dirName);
  }

  /// Canonical tvOS directory name for build configuration.
  String _getDirectoryName(BuildMode mode, EnvironmentType? environmentType) {
    if (environmentType == EnvironmentType.simulator) {
      return 'tvos_debug_sim_arm64';
    }
    return switch (mode) {
      BuildMode.debug => 'tvos_debug_arm64',
      BuildMode.profile => 'tvos_profile_arm64',
      BuildMode.release => 'tvos_release_arm64',
      _ => 'tvos_debug_arm64',
    };
  }

  /// Returns the path to gen_snapshot for the target build mode.
  ///
  /// gen_snapshot is shipped inside each tvOS device artifact at
  /// `clang_arm64/gen_snapshot`. Built with `target_os=ios` + `--tvos`
  /// + `--runtime-mode=<mode>`, so it cross-compiles AOT snapshots that
  /// target tvOS arm64 (not the host). Using `host_release/gen_snapshot`
  /// here would emit a macOS-arm64 snapshot and the engine fails to load
  /// it at runtime ("VM snapshot invalid").
  String getGenSnapshotPath(BuildMode mode) {
    return getArtifactPath(
      Artifact.genSnapshot,
      mode: mode,
      environmentType: EnvironmentType.physical,
    );
  }

  /// Returns the host tools directory path.
  ///
  /// Host tools (frontend_server, dart) are in the Flutter SDK, not in engine_artifacts.
  String getHostToolsPath(BuildMode mode) {
    final dirName = mode == BuildMode.debug ? 'host_debug_unopt' : 'host_release';
    return _fileSystem.path.join(_tvosArtifactRoot, dirName);
  }
}
