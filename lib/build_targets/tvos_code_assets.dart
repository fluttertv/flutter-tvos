// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:code_assets/code_assets.dart';
import 'package:flutter_tools/src/base/common.dart' show throwToolExit;
import 'package:flutter_tools/src/base/error_handling_io.dart' show ErrorHandlingFileSystem;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/depfile.dart';
import 'package:flutter_tools/src/build_system/exceptions.dart' show MissingDefineException;
import 'package:flutter_tools/src/build_system/targets/native_assets.dart' show LinkHooks;
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/native_assets/dart_hook_result.dart';
import 'package:flutter_tools/src/isolated/native_assets/macos/native_assets_host.dart';
import 'package:flutter_tools/src/isolated/native_assets/native_assets.dart'
    show FlutterCodeAsset;
import 'package:flutter_tools/src/isolated/native_assets/native_assets_manifest.dart';
import 'package:meta/meta.dart' show immutable, visibleForTesting;

import 'tvos_hooks.dart';

/// The OS the tvOS engine looks its native assets up under.
///
/// The engine keys `NativeAssetsManifest.json` by a target string it fixes at
/// compile time (`engine/src/flutter/assets/native_assets.cc`): the OS half is
/// `ios` whenever `FML_OS_IOS` is defined, and `fml/build_config.h` defines
/// that from `TARGET_OS_IPHONE`, which Apple's headers set for tvOS too. The
/// tvOS engine is the iOS engine built for tvOS and its patch set leaves that
/// file alone, so an Apple TV reads the `ios_arm64` entry, whatever
/// `Platform.operatingSystem` says. An asset filed under `tvos_arm64` would
/// never be found, and every `@Native` call into it would throw.
///
/// The hooks are still told `tvos`; this is only the manifest's key.
const OS tvosNativeAssetsManifestOS = OS.iOS;

/// The minimum tvOS version stamped into a code-asset framework's Info.plist
/// when its library does not say.
///
/// Matches the template's `TVOS_DEPLOYMENT_TARGET` and the engine's own floor.
const String kTvosCodeAssetFallbackMinimumOSVersion = '15.0';

/// The Mach-O platform a library has to carry to load on the SDK being built.
///
/// `LC_BUILD_VERSION` names it, as `vtool -show-build` prints it.
@visibleForTesting
String tvosMachOPlatform({required bool simulator}) => simulator ? 'TVOSSIMULATOR' : 'TVOS';

/// One `LC_BUILD_VERSION` (or legacy version-min command) of a Mach-O file.
@immutable
class MachOBuildVersion {
  const MachOBuildVersion({required this.platform, this.minos});

  /// The platform name as `vtool` prints it, such as `TVOS`.
  final String platform;

  /// The minimum OS version, if the command carries one.
  final String? minos;

  @override
  bool operator ==(Object other) =>
      other is MachOBuildVersion && other.platform == platform && other.minos == minos;

  @override
  int get hashCode => Object.hash(platform, minos);

  @override
  String toString() => 'MachOBuildVersion($platform, $minos)';
}

/// Platforms `vtool` prints by number when it has no name for them, from
/// `mach-o/loader.h`. Only the ones that can plausibly reach a tvOS build.
const Map<String, String> _machOPlatformNumbers = <String, String>{
  '1': 'MACOS',
  '2': 'IOS',
  '3': 'TVOS',
  '7': 'IOSSIMULATOR',
  '8': 'TVOSSIMULATOR',
};

/// Parses the output of `xcrun vtool -show-build <file>`.
///
/// A thin library has one build-version command, a fat one one per slice.
/// Libraries linked before `LC_BUILD_VERSION` existed carry
/// `LC_VERSION_MIN_TVOS` instead, which names no simulator; it is reported as
/// `TVOS`, which is what it is on Apple's side as well.
@visibleForTesting
List<MachOBuildVersion> parseVtoolBuildVersions(String output) {
  final versions = <MachOBuildVersion>[];
  String? platform;
  String? minos;
  void flush() {
    if (platform != null) {
      versions.add(MachOBuildVersion(platform: platform!, minos: minos));
    }
    platform = null;
    minos = null;
  }

  for (final String rawLine in output.split('\n')) {
    final String line = rawLine.trim();
    final List<String> fields = line.split(RegExp(r'\s+'));
    if (fields.length < 2) {
      continue;
    }
    switch (fields.first) {
      case 'cmd':
        flush();
        if (fields[1] == 'LC_VERSION_MIN_TVOS') {
          platform = 'TVOS';
        }
      case 'platform':
        platform = _machOPlatformNumbers[fields[1]] ?? fields[1];
      case 'minos':
      case 'version' when platform == 'TVOS' && minos == null:
        minos = fields[1];
    }
  }
  flush();
  return versions;
}

/// Why [versions] cannot load on the SDK being built, or null if they can.
///
/// Null too when nothing could be read, which only a malformed or exotic
/// library produces; the caller says so rather than guessing.
@visibleForTesting
String? tvosPlatformMismatch(List<MachOBuildVersion> versions, {required bool simulator}) {
  final String expected = tvosMachOPlatform(simulator: simulator);
  final found = <String>{for (final MachOBuildVersion v in versions) v.platform};
  if (found.isEmpty || found.every((String p) => p == expected)) {
    return null;
  }
  return 'built for ${found.join(', ')}, but this ${simulator ? 'simulator' : 'device'} '
      'build needs $expected';
}

/// The code assets of [codeAssets] mapped to where they go in the app and how
/// the engine finds them, filed under the key the engine reads.
///
/// The bundling half is upstream's for iOS, unchanged: one framework per
/// dynamic library, named after the library, loaded as
/// `@rpath/<name>.framework/<name>`. Only the manifest key differs, see
/// [tvosNativeAssetsManifestOS].
@visibleForTesting
Map<FlutterCodeAsset, FlutterCodeAssetTargetLocation> tvosCodeAssetTargetLocations(
  List<FlutterCodeAsset> codeAssets,
) {
  return assetTargetLocationsApple(<FlutterCodeAsset>[
    for (final FlutterCodeAsset asset in codeAssets)
      FlutterCodeAsset(
        codeAsset: asset.codeAsset,
        os: tvosNativeAssetsManifestOS,
        architecture: asset.architecture,
      ),
  ]);
}

/// Reads the build versions of [library] with `vtool`.
Future<List<MachOBuildVersion>> _readBuildVersions(File library) async {
  final RunResult result = await globals.processUtils.run(<String>[
    'xcrun',
    'vtool',
    '-show-build',
    library.path,
  ]);
  if (result.exitCode != 0) {
    throwToolExit('Failed to read the platform of ${library.path}:\n${result.stderr}');
  }
  return parseVtoolBuildVersions(result.stdout);
}

/// Installs the code assets of a tvOS hook pass and writes the manifest the
/// engine reads them from.
///
/// Mirrors upstream's `installCodeAssets` for iOS: each bundled dynamic
/// library becomes `<name>.framework/<name>` under [targetDirectory], gets the
/// install name it is loaded by, an `Info.plist`, a dSYM and a strip outside
/// debug, and an ad-hoc signature (the Xcode embed phase re-signs it with the
/// app's identity, as it does the engine). The manifest goes to
/// [manifestFile], and from there into `flutter_assets` as
/// `NativeAssetsManifest.json`.
///
/// Two things differ from iOS, both because this is tvOS:
///
///  * Every library is checked against the SDK being built before it is
///    installed. A hook is told `tvos` and nothing about device or simulator
///    (see [tvOSName]), so it may hand a simulator build a device library or
///    the reverse — and the hooks cache hands both builds the same one. dyld
///    refuses a library for the other platform at the first `@Native` call;
///    failing here instead names it while the build can still say why.
///  * `MinimumOSVersion` comes from the library's own `minos`, which App Store
///    validation compares it to (ITMS-90208). iOS can hard-code it because it
///    tells its hooks the deployment target; a tvOS hook is told none.
Future<List<File>> installTvosCodeAssets({
  required List<FlutterCodeAsset> codeAssets,
  required Directory targetDirectory,
  required File manifestFile,
  required BuildMode buildMode,
  required bool simulator,
  required FileSystem fileSystem,
}) async {
  final Map<FlutterCodeAsset, FlutterCodeAssetTargetLocation> locations =
      tvosCodeAssetTargetLocations(codeAssets);

  // As upstream: a library loaded from the process, the executable or the
  // system has nothing to bundle and only a manifest entry.
  final Map<Uri, List<FlutterCodeAsset>> frameworks = fatAssetTargetLocations(
    <FlutterCodeAsset, FlutterCodeAssetTargetLocation>{
      for (final MapEntry<FlutterCodeAsset, FlutterCodeAssetTargetLocation> entry
          in locations.entries)
        if (entry.key.codeAsset.linkMode is DynamicLoadingBundled) entry.key: entry.value,
    },
  );

  if (!targetDirectory.existsSync()) {
    targetDirectory.createSync(recursive: true);
  }
  for (final FileSystemEntity entity in targetDirectory.listSync()) {
    ErrorHandlingFileSystem.deleteIfExists(entity, recursive: true);
  }

  final installedFiles = <File>[];
  if (frameworks.isNotEmpty) {
    installedFiles.addAll(
      await _copyFrameworks(frameworks, targetDirectory, buildMode, simulator, fileSystem),
    );
  }

  final manifest = NativeAssetsManifest.fromTargetLocations(locations);
  if (!manifestFile.parent.existsSync()) {
    manifestFile.parent.createSync(recursive: true);
  }
  manifestFile.writeAsStringSync(manifest.toJsonString());
  return <File>[manifestFile, ...installedFiles];
}

Future<List<File>> _copyFrameworks(
  Map<Uri, List<FlutterCodeAsset>> frameworks,
  Directory targetDirectory,
  BuildMode buildMode,
  bool simulator,
  FileSystem fileSystem,
) async {
  // Check everything before installing anything, and report every library
  // that is wrong rather than the first: a package that picks the wrong SDK
  // usually picks it for all of its libraries.
  final mismatches = <String>[];
  final minimumVersions = <Uri, String>{};
  for (final MapEntry<Uri, List<FlutterCodeAsset>> entry in frameworks.entries) {
    for (final FlutterCodeAsset asset in entry.value) {
      final File library = fileSystem.file(asset.codeAsset.file);
      final List<MachOBuildVersion> versions = await _readBuildVersions(library);
      final String? mismatch = tvosPlatformMismatch(versions, simulator: simulator);
      if (mismatch != null) {
        mismatches.add('  ${asset.codeAsset.id} (${library.path}): $mismatch');
      }
      if (versions.isEmpty) {
        globals.logger.printWarning(
          'Could not read the platform of ${library.path} (${asset.codeAsset.id}); '
          'installing it unchecked.',
        );
      }
      final String? minos = versions.map((MachOBuildVersion v) => v.minos).nonNulls.firstOrNull;
      if (minos != null) {
        minimumVersions[entry.key] = minos;
      }
    }
  }
  if (mismatches.isNotEmpty) {
    throwToolExit(
      'A Dart build hook produced a native library that cannot load on this '
      '${simulator ? 'tvOS simulator' : 'Apple TV device'} build:\n'
      '${mismatches.join('\n')}\n'
      '\n'
      'A hook building for tvOS is told `tvos` and arm64, and nothing about '
      'device or simulator: the hooks protocol carries that in a per-OS '
      'sub-config, and there is none for tvOS. So a device build and a '
      'simulator build give a hook the same input, and the hooks cache serves '
      'both whichever library the hook built first.\n'
      'A package that builds for tvOS has to choose the SDK by some means of its '
      "own, for example a user-define in the app's pubspec.yaml "
      '(`hooks: user_defines:`); changing the define rebuilds it. Installing '
      'this library anyway would give an app that fails at its first `@Native` '
      'call.',
    );
  }

  final installedFiles = <File>[];
  final oldToNewInstallNames = <String, String>{};
  final dylibs = <(File, String, Directory)>[];
  for (final MapEntry<Uri, List<FlutterCodeAsset>> entry in frameworks.entries) {
    final Uri target = entry.key;
    final File dylibFile = fileSystem.file(targetDirectory.uri.resolveUri(target));
    final Directory frameworkDir = dylibFile.parent;
    frameworkDir.createSync(recursive: true);
    await lipoDylibs(dylibFile, <File>[
      for (final FlutterCodeAsset asset in entry.value) fileSystem.file(asset.codeAsset.file),
    ]);
    installedFiles.add(dylibFile);

    if (buildMode != BuildMode.debug) {
      final dsymPath = '${frameworkDir.path}.dSYM';
      await dsymutilDylib(dylibFile, dsymPath);
      await stripDylib(dylibFile);
      installedFiles.addAll(
        fileSystem.directory(dsymPath).listSync(recursive: true).whereType<File>(),
      );
    }

    final String newInstallName = frameworkInstallName(target);
    for (final String oldInstallName in await getInstallNamesDylib(dylibFile)) {
      oldToNewInstallNames[oldInstallName] = newInstallName;
    }
    dylibs.add((dylibFile, newInstallName, frameworkDir));

    await createInfoPlist(
      target.pathSegments.last,
      frameworkDir,
      minimumIOSVersion: minimumVersions[target] ?? kTvosCodeAssetFallbackMinimumOSVersion,
    );
    installedFiles.add(frameworkDir.childFile('Info.plist'));
  }

  for (final (File dylibFile, String newInstallName, Directory frameworkDir) in dylibs) {
    await setInstallNamesDylib(dylibFile, newInstallName, oldToNewInstallNames);
    // Ad hoc. A simulator needs no more, and a device build re-signs every
    // framework with the app's identity in the Xcode embed phase, which is the
    // only place that identity is known.
    await codesignDylib(null, buildMode, frameworkDir);
  }
  return installedFiles;
}

/// Installs the code assets the tvOS hook pass kept, and writes
/// `native_assets.json` — tvOS's counterpart of upstream `InstallCodeAssets`.
///
/// The frameworks go under `{BUILD_DIR}/native_assets/`, not upstream's
/// `{OUTPUT_DIR}/native_assets/`: on tvOS the output directory is also where
/// `flutter_assets` is mirrored from, and a framework there would ship inside
/// the asset bundle. `NativeTvosBundle` stages them into the Xcode project from
/// here; the build directory is keyed on the defines, so a device build and a
/// simulator build do not share it.
class TvosInstallCodeAssets extends Target {
  const TvosInstallCodeAssets();

  @override
  String get name => 'tvos_install_code_assets';

  @override
  List<Target> get dependencies => const <Target>[TvosBuildHooks()];

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{BUILD_DIR}/${LinkHooks.resultFilename}'),
    Source.pattern('{WORKSPACE_DIR}/.dart_tool/package_config.json'),
  ];

  @override
  List<Source> get outputs => const <Source>[Source.pattern('{BUILD_DIR}/$nativeAssetsFilename')];

  @override
  List<String> get depfiles => const <String>[depFilename];

  static const nativeAssetsFilename = 'native_assets.json';
  static const depFilename = 'tvos_install_code_assets.d';

  /// Where the frameworks are installed, relative to the build directory.
  static const directoryName = 'native_assets';

  @override
  Future<void> build(Environment environment) async {
    final String? buildModeName = environment.defines[kBuildMode];
    if (buildModeName == null) {
      throw MissingDefineException(kBuildMode, name);
    }
    final DartHooksResult result = await LinkHooks.loadHookResult(environment);

    final bool simulator;
    final String? sdkRoot = environment.defines[kSdkRoot];
    if (sdkRoot != null) {
      simulator =
          tvosEnvironmentTypeOf(sdkRoot, environment.fileSystem) == EnvironmentType.simulator;
    } else if (result.codeAssets.isEmpty) {
      simulator = false; // Nothing is checked or installed.
    } else {
      throw MissingDefineException(kSdkRoot, name);
    }

    final List<File> installed = await installTvosCodeAssets(
      codeAssets: result.codeAssets,
      targetDirectory: environment.buildDir.childDirectory(directoryName),
      manifestFile: environment.buildDir.childFile(nativeAssetsFilename),
      buildMode: BuildMode.fromCliName(buildModeName),
      simulator: simulator,
      fileSystem: environment.fileSystem,
    );

    final depfile = Depfile(<File>[
      for (final Uri file in result.filesToBeBundled) environment.fileSystem.file(file),
    ], installed);
    environment.depFileService.writeToFile(depfile, environment.buildDir.childFile(depFilename));
  }
}
