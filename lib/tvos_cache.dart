// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart' show OperatingSystemUtils;
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/flutter_cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:process/process.dart';

const String kTvosEngineStampName = 'tvos-sdk';

/// The default GitHub Releases base URL for engine artifact zips.
/// Tag and filename are appended: {base}/{tag}/{name}.zip
const String kDefaultEngineBaseUrl =
    'https://github.com/fluttertv/engine-artifacts/releases/download';

Directory tvosToolRootDirectory(FileSystem fileSystem) {
  return fileSystem.directory(Cache.flutterRoot).parent;
}

Directory tvosArtifactDirectory(FileSystem fileSystem) {
  return tvosToolRootDirectory(fileSystem).childDirectory('engine_artifacts');
}

/// Local override: if zips are present here they are used instead of downloading.
/// Used in development within the monorepo. Not relevant for public users.
Directory _localArtifactArchiveDirectory(FileSystem fileSystem) {
  return tvosToolRootDirectory(fileSystem).parent.childDirectory('artifacts');
}

mixin TvosRequiredArtifacts on FlutterCommand {
  @override
  Future<Set<DevelopmentArtifact>> get requiredArtifacts async => <DevelopmentArtifact>{
    ...await super.requiredArtifacts,
    TvosDevelopmentArtifact.tvos,
  };
}

/// See: [DevelopmentArtifact] in `cache.dart`
class TvosDevelopmentArtifact implements DevelopmentArtifact {
  const TvosDevelopmentArtifact._(this.name);

  @override
  final String name;

  // [DevelopmentArtifact] declares `feature` so we must override it. tvOS isn't
  // gated behind a Flutter feature flag, so this is intentionally null and a
  // getter (rather than a field initializer) keeps the class const-friendly.
  @override
  Feature? get feature => null;

  static const DevelopmentArtifact tvos = TvosDevelopmentArtifact._('tvos');
}

/// Extends [FlutterCache] to register [TvosEngineArtifacts].
class TvosFlutterCache extends FlutterCache {
  TvosFlutterCache({
    required Logger logger,
    required super.fileSystem,
    required Platform platform,
    required super.osUtils,
    required super.projectFactory,
    required ProcessManager processManager,
  }) : super(logger: logger, platform: platform) {
    registerArtifact(
      TvosEngineArtifacts(this, logger: logger, platform: platform, processManager: processManager),
    );
  }
}

/// Downloads and caches tvOS engine artifacts.
///
/// Artifact sources (in priority order):
/// 1. Local zip files in `../artifacts/` — dev override for monorepo use
/// 2. GitHub Releases — default for all public users
///
/// The GitHub Releases base URL can be overridden with the
/// `TVOS_ENGINE_BASE_URL` environment variable. The release tag comes from
/// `bin/internal/engine.version` (e.g. `v1.0.0-flutter3.41.4`).
class TvosEngineArtifacts extends EngineCachedArtifact {
  TvosEngineArtifacts(
    Cache cache, {
    required Logger logger,
    required Platform platform,
    required ProcessManager processManager,
  }) : _logger = logger,
       _platform = platform,
       _processUtils = ProcessUtils(processManager: processManager, logger: logger),
       super(kTvosEngineStampName, cache, TvosDevelopmentArtifact.tvos);

  final Logger _logger;
  final Platform _platform;
  final ProcessUtils _processUtils;

  static const List<String> _artifactZipNames = <String>[
    'tvos_debug_sim_arm64.zip',
    'tvos_debug_arm64.zip',
    'tvos_profile_arm64.zip',
    'tvos_release_arm64.zip',
    'host_debug_unopt.zip',
    'host_release.zip',
  ];

  @override
  Directory get location => tvosArtifactDirectory(globals.fs);

  @override
  String? get version {
    final File versionFile = globals.fs
        .directory(Cache.flutterRoot)
        .parent
        .childDirectory('bin')
        .childDirectory('internal')
        .childFile('engine.version');
    return versionFile.existsSync() ? versionFile.readAsStringSync().trim() : null;
  }

  /// The release tag, e.g. `v1.0.0-flutter3.41.4`.
  String get releaseTag {
    if (version == null || version!.isEmpty) {
      throwToolExit(
        'Could not read engine version from bin/internal/engine.version.\n'
        'Run `flutter-tvos precache` to download the required artifacts.',
      );
    }
    return version!;
  }

  /// Base URL for GitHub Releases downloads.
  /// Override with TVOS_ENGINE_BASE_URL for custom artifact hosting.
  String get engineBaseUrl {
    return _platform.environment['TVOS_ENGINE_BASE_URL'] ?? kDefaultEngineBaseUrl;
  }

  /// Full download URL for a given zip file.
  String artifactDownloadUrl(String zipName) {
    return '$engineBaseUrl/$releaseTag/$zipName';
  }

  @override
  List<List<String>> getBinaryDirs() => <List<String>>[
    <String>['tvos_debug_arm64', ''],
    <String>['tvos_debug_sim_arm64', ''],
    <String>['tvos_profile_arm64', ''],
    <String>['tvos_release_arm64', ''],
    <String>['host_debug_unopt', ''],
    <String>['host_release', ''],
  ];

  @override
  List<String> getLicenseDirs() => const <String>[];

  @override
  List<String> getPackageDirs() => const <String>[];

  @override
  Future<void> updateInner(
    ArtifactUpdater artifactUpdater,
    FileSystem fileSystem,
    OperatingSystemUtils operatingSystemUtils,
  ) async {
    // --- Strategy 1: local zips (dev/monorepo override) ---
    final Directory localArchiveDir = _localArtifactArchiveDirectory(fileSystem);
    final List<File> localZips = _artifactZipNames
        .map((String name) => localArchiveDir.childFile(name))
        .where((File f) => f.existsSync())
        .toList();

    if (localZips.isNotEmpty) {
      _logger.printStatus('Using local tvOS engine artifacts from ${localArchiveDir.path}...');
      await _extractZips(localZips, fileSystem, operatingSystemUtils);
      return;
    }

    // --- Strategy 2: download from GitHub Releases ---
    final String tag = releaseTag;
    _logger.printStatus('Downloading tvOS engine artifacts ($tag) from GitHub Releases...');

    if (location.existsSync()) {
      location.deleteSync(recursive: true);
    }
    location.createSync(recursive: true);

    final Directory tempDir = fileSystem.systemTempDirectory.createTempSync(
      'flutter_tvos_artifacts.',
    );

    try {
      for (final String zipName in _artifactZipNames) {
        final String url = artifactDownloadUrl(zipName);
        final File tempZip = tempDir.childFile(zipName);

        _logger.printStatus('  Downloading $zipName...');

        final RunResult curlResult = await _processUtils.run(<String>[
          'curl',
          '--location', // follow redirects
          '--fail', // fail on HTTP errors (4xx, 5xx)
          '--silent',
          '--show-error',
          '--output', tempZip.path,
          url,
        ]);

        if (curlResult.exitCode != 0) {
          throwToolExit(
            'Failed to download $zipName from $url.\n\n${curlResult.stderr}\n\n'
            'Check that the release tag "$tag" exists at:\n'
            '  https://github.com/fluttertv/engine-artifacts/releases\n\n'
            'You can also override the download URL with the '
            'TVOS_ENGINE_BASE_URL environment variable.',
          );
        }

        _logger.printStatus('  Extracting $zipName...');
        final RunResult unzipResult = await _processUtils.run(<String>[
          'unzip',
          '-q',
          tempZip.path,
          '-d',
          location.path,
        ]);

        if (unzipResult.exitCode != 0) {
          throwToolExit('Failed to extract $zipName.\n\n${unzipResult.stderr}');
        }
      }
    } finally {
      tempDir.deleteSync(recursive: true);
    }

    // Remove macOS metadata directories if present.
    final Directory macOsMetaDir = location.childDirectory('__MACOSX');
    if (macOsMetaDir.existsSync()) {
      macOsMetaDir.deleteSync(recursive: true);
    }

    _logger.printStatus('tvOS engine artifacts downloaded successfully!');
    _makeFilesExecutable(location, operatingSystemUtils);
  }

  Future<void> _extractZips(
    List<File> zips,
    FileSystem fileSystem,
    OperatingSystemUtils operatingSystemUtils,
  ) async {
    if (location.existsSync()) {
      location.deleteSync(recursive: true);
    }
    location.createSync(recursive: true);

    for (final zip in zips) {
      final RunResult result = await _processUtils.run(<String>[
        'unzip',
        '-q',
        zip.path,
        '-d',
        location.path,
      ]);
      if (result.exitCode != 0) {
        throwToolExit('Failed to extract ${zip.basename}.\n\n${result.stderr}');
      }
    }

    final Directory macOsMetaDir = location.childDirectory('__MACOSX');
    if (macOsMetaDir.existsSync()) {
      macOsMetaDir.deleteSync(recursive: true);
    }

    _logger.printStatus('tvOS engine artifacts extracted successfully!');
    _makeFilesExecutable(location, operatingSystemUtils);
  }

  void _makeFilesExecutable(Directory dir, OperatingSystemUtils operatingSystemUtils) {
    operatingSystemUtils.chmod(dir, 'a+r,a+x');
    for (final File file in dir.listSync(recursive: true).whereType<File>()) {
      if (file.basename == 'gen_snapshot' ||
          file.basename == 'impellerc' ||
          file.basename == 'frontend_server_aot.dart.snapshot') {
        operatingSystemUtils.chmod(file, 'a+r,a+x');
      }
    }
  }
}
