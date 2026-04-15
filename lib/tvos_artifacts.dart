// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
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
    required FileSystem fileSystem,
    required Cache cache,
    required Platform platform,
    required OperatingSystemUtils operatingSystemUtils,
  }) : _fileSystem = fileSystem,
       super(
         fileSystem: fileSystem,
         cache: cache,
         platform: platform,
         operatingSystemUtils: operatingSystemUtils,
       );

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
      final String engineDir = _resolveEngineDirectory(
        mode ?? BuildMode.debug,
        environmentType,
      );

      if (artifact == Artifact.genSnapshot) {
        return _fileSystem.path.join(engineDir, 'clang_arm64', 'gen_snapshot');
      } else if (artifact == Artifact.flutterFramework) {
        return _fileSystem.path.join(engineDir, 'Flutter.framework');
      } else if (artifact == Artifact.flutterXcframework) {
        return _fileSystem.path.join(engineDir, 'Flutter.xcframework');
      }
    }
    return super.getArtifactPath(
      artifact,
      platform: platform,
      mode: mode,
      environmentType: environmentType,
    );
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
  /// For release/profile builds, gen_snapshot is in the device artifact directory
  /// under `clang_arm64/gen_snapshot`.
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
    final String dirName = mode == BuildMode.debug ? 'host_debug_unopt' : 'host_release';
    return _fileSystem.path.join(_tvosArtifactRoot, dirName);
  }
}
