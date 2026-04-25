// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart' show Status;
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/targets/common.dart';
import 'package:flutter_tools/src/build_system/targets/localizations.dart';
import 'package:flutter_tools/src/build_system/targets/native_assets.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';

import '../tvos_artifacts.dart';
import '../tvos_build_info.dart';
import '../tvos_cache.dart';
import '../tvos_plugins.dart';

/// Writes `.dart_tool/flutter_build/dart_plugin_registrant.dart` with tvOS-
/// aware plugin registrations, as a proper build target.
///
/// This replaces Flutter's stock [DartPluginRegistrantTarget] in our build
/// graph (via [TvosKernelSnapshot]) so that the file the frontend-server
/// reads via `--source=dart_plugin_registrant.dart` contains entries for
/// plugins declared under `flutter.plugin.platforms.tvos` — not the iOS
/// entries Flutter would otherwise emit (since `Platform.isIOS` is false
/// under our Dart VM patch, and the `tvos` platform key is unknown to
/// upstream `generateMainDartWithPluginRegistrant`).
class TvosDartPluginRegistrantTarget extends Target {
  const TvosDartPluginRegistrantTarget();

  @override
  String get name => 'gen_tvos_dart_plugin_registrant';

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  List<Source> get inputs => const <Source>[
        Source.pattern('{WORKSPACE_DIR}/.dart_tool/package_config.json'),
      ];

  @override
  List<Source> get outputs => const <Source>[
        // Flutter's KernelCompiler reads this path when
        // checkDartPluginRegistry is true. See
        // `compile.dart:buildDir.parent.childFile('dart_plugin_registrant.dart')`.
        Source.pattern('{BUILD_DIR}/../dart_plugin_registrant.dart'),
      ];

  @override
  Future<void> build(Environment environment) async {
    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    writeTvosDartPluginRegistrant(project);
  }
}

/// A [KernelSnapshot] subclass that swaps in our tvOS-aware registrant target.
///
/// The stock `KernelSnapshot.dependencies` includes upstream
/// `DartPluginRegistrantTarget`, which would overwrite our file with an
/// iOS-plugin-based registrant (via `generateMainDartWithPluginRegistrant`
/// in `flutter_plugins.dart`). That's wrong on tvOS — iOS-only plugins like
/// `shared_preferences_foundation` have no native code in our bundle, so
/// calls through them raise `MissingPluginException` at runtime.
///
/// By replacing the dep with [TvosDartPluginRegistrantTarget] we keep the
/// registrant file correct, AND the `checkDartPluginRegistry` flag still
/// propagates (via `environment.generateDartPluginRegistry: true`) so the
/// frontend-server receives `--source=dart_plugin_registrant.dart` and
/// links `_PluginRegistrant.register()` into the kernel blob.
class TvosKernelSnapshot extends KernelSnapshot {
  const TvosKernelSnapshot();

  @override
  List<Target> get dependencies => const <Target>[
        GenerateLocalizationsTarget(),
        TvosDartPluginRegistrantTarget(),
      ];
}

/// [AotElfRelease] subclass that uses [TvosKernelSnapshot] instead of the
/// stock [KernelSnapshot], so AOT release builds also link the tvOS
/// registrant into the compiled kernel.
class TvosAotElfRelease extends AotElfRelease {
  const TvosAotElfRelease(TargetPlatform targetPlatform) : super(targetPlatform);

  @override
  List<Target> get dependencies => const <Target>[TvosKernelSnapshot()];
}

/// [CopyFlutterBundle] subclass that depends on [TvosKernelSnapshot] instead
/// of the stock [KernelSnapshot].
///
/// This matters because `dependencies` is how the build graph reaches
/// transitively-needed targets. If we left stock [CopyFlutterBundle] in the
/// graph, its `dependencies` list would drag [KernelSnapshot] in — which in
/// turn drags upstream [DartPluginRegistrantTarget] in — and THAT target
/// regenerates `dart_plugin_registrant.dart` from iOS-plugin data,
/// overwriting our tvOS-correct file before frontend-server reads it.
class TvosCopyFlutterBundle extends CopyFlutterBundle {
  const TvosCopyFlutterBundle();

  @override
  List<Target> get dependencies => const <Target>[
        DartBuildForNative(),
        TvosKernelSnapshot(),
        InstallCodeAssets(),
      ];
}

class DebugTvosApplication extends Target {
  DebugTvosApplication(this.buildInfo);

  final TvosBuildInfo buildInfo;

  @override
  String get name => 'debug_tvos_application';

  @override
  List<Target> get dependencies => const <Target>[
        TvosKernelSnapshot(),
        TvosCopyFlutterBundle(),
      ];

  @override
  List<Source> get inputs => const <Source>[];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  Future<void> build(Environment environment) async {
    globals.logger.printTrace('Assembling debug tvOS application...');
  }
}

class ReleaseTvosApplication extends Target {
  ReleaseTvosApplication(this.buildInfo);

  final TvosBuildInfo buildInfo;

  @override
  String get name => 'release_tvos_application';

  @override
  List<Target> get dependencies => const <Target>[
        // We do AOT compilation ourselves in NativeTvosBundle._compileAotSnapshot
        // (gen_snapshot → assembly → clang → App.framework) because upstream
        // AotElfRelease throws "Null check operator used on a null value" when
        // TargetPlatform == ios but no darwinArch is plumbed through. Just
        // depend on the kernel snapshot — the AOT step reads app.dill from the
        // build output dir.
        TvosKernelSnapshot(),
        TvosCopyFlutterBundle(),
      ];

  @override
  List<Source> get inputs => const <Source>[];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  Future<void> build(Environment environment) async {
    globals.logger.printTrace('Assembling release tvOS application...');
  }
}

/// Orchestrates the native tvOS build via xcodebuild.
///
/// Build steps:
/// 1. Copy Flutter.framework from engine artifacts into tvos/Flutter/
/// 2. Copy flutter_assets into tvos/Flutter/flutter_assets/
/// 3. Generate GeneratedPluginRegistrant.h/.m
/// 4. Generate xcconfig files
/// 5. Run pod install if Podfile exists
/// 6. Invoke xcodebuild targeting appletvos or appletvsimulator SDK
class NativeTvosBundle extends Target {
  NativeTvosBundle(this.buildInfo, this.targetFile);

  final TvosBuildInfo buildInfo;
  final String targetFile;

  @override
  String get name => 'tvos_native_bundle';

  @override
  List<Target> get dependencies => <Target>[
        if (buildInfo.buildInfo.isDebug) DebugTvosApplication(buildInfo),
        if (!buildInfo.buildInfo.isDebug) ReleaseTvosApplication(buildInfo),
      ];

  @override
  List<Source> get inputs => const <Source>[];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  Future<void> build(Environment environment) async {
    final FlutterProject project = FlutterProject.current();
    final Directory tvosProjectDir = project.directory.childDirectory('tvos');

    if (!tvosProjectDir.existsSync()) {
      globals.logger.printError('tvOS project not found. Did you run flutter-tvos create?');
      throw Exception('Missing tvOS project directory');
    }

    // 1. Copy Flutter.framework from engine artifacts
    _copyFlutterFramework(tvosProjectDir);

    // 2. Copy tvos_metallibs from CLI templates into the project (binary files
    //    can't be processed by Flutter's template system)
    _copyMetalLibs(tvosProjectDir);

    // 4. Copy flutter_assets into tvos/Flutter/
    _copyFlutterAssets(project, tvosProjectDir);

    // 3. Generate GeneratedPluginRegistrant
    _generatePluginRegistrant(tvosProjectDir);

    // 3b. For release/profile: compile AOT snapshot via gen_snapshot → App.framework
    if (!buildInfo.buildInfo.isDebug) {
      await _compileAotSnapshot(project, tvosProjectDir, environment);
    }

    // 4. Generate xcconfig files
    _generateXcconfigs(project, tvosProjectDir);

    // 5. Generate tvOS plugin dependencies (must run AFTER Flutter's pub get
    //    which overwrites .flutter-plugins-dependencies without tvos key)
    await ensureReadyForTvosTooling(project);

    // 6. Run pod install if Podfile exists
    if (tvosProjectDir.childFile('Podfile').existsSync()) {
      // Use a Status spinner so the user sees timing the same way stock
      // iOS `flutter run` reports it.
      final Status podStatus = globals.logger.startProgress('Running pod install...');
      try {
        final ProcessResult podResult = await globals.processManager.run(
          <String>['pod', 'install'],
          workingDirectory: tvosProjectDir.path,
          environment: <String, String>{
            'LANG': 'en_US.UTF-8',
            'LC_ALL': 'en_US.UTF-8',
          },
        );
        if (podResult.exitCode != 0) {
          throw Exception('pod install failed:\n${podResult.stderr}');
        }
      } finally {
        podStatus.stop();
      }
    }

    // 7. Run xcodebuild — wrap in a Status spinner so the user sees the
    //    same "Running Xcode build... / Xcode build done." cadence stock
    //    `flutter run` for iOS produces.
    globals.logger.printTrace(
      'Executing xcodebuild for tvOS (${buildInfo.sdkName})...',
    );

    final String configuration = buildInfo.buildInfo.isDebug ? 'Debug' : 'Release';
    final String symroot = project.directory
        .childDirectory('build')
        .childDirectory('tvos')
        .path;

    final bool hasWorkspace = tvosProjectDir.childDirectory('Runner.xcworkspace').existsSync();

    // Code signing settings for physical device builds
    final List<String> signingArgs = await _resolveSigningArgs(
      tvosProjectDir,
      buildInfo.simulator,
    );

    final Status xcodeStatus = globals.logger.startProgress('Running Xcode build...');
    ProcessResult result;
    try {
      result = await globals.processManager.run(
        <String>[
          'xcodebuild',
          if (hasWorkspace) ...<String>[
            '-workspace', 'Runner.xcworkspace',
          ] else ...<String>[
            '-project', 'Runner.xcodeproj',
          ],
          '-scheme', 'Runner',
          '-configuration', configuration,
          '-sdk', buildInfo.sdkName,
          'SYMROOT=$symroot',
          'COMPILER_INDEX_STORE_ENABLE=NO',
          'ARCHS=arm64',
          ...signingArgs,
          'build',
        ],
        workingDirectory: tvosProjectDir.path,
      );
    } finally {
      xcodeStatus.stop();
    }

    if (result.exitCode != 0) {
      globals.logger.printError('Xcode build failed:');
      globals.logger.printError(result.stdout as String);
      globals.logger.printError(result.stderr as String);
      throw Exception('Xcode build failed');
    }
    globals.logger.printStatus('Xcode build done.');

    final String platformSuffix = buildInfo.simulator
        ? '$configuration-appletvsimulator'
        : '$configuration-appletvos';

    // For release/profile (AOT) builds, embed App.framework into the .app
    // bundle. The Xcode project template only embeds Flutter.framework, but
    // FlutterDartProject.mm looks for `Frameworks/App.framework/App` to load
    // the AOT VM/isolate snapshots via dlsym. Without this, the engine
    // reports "VM snapshot invalid and could not be inferred from settings"
    // and aborts.
    if (!buildInfo.buildInfo.isDebug) {
      final Directory builtApp = globals.fs
          .directory(symroot)
          .childDirectory(platformSuffix)
          .childDirectory('Runner.app');
      final Directory generatedAppFramework = tvosProjectDir
          .childDirectory('Flutter')
          .childDirectory('App.framework');
      if (builtApp.existsSync() && generatedAppFramework.existsSync()) {
        final Directory destFrameworks = builtApp.childDirectory('Frameworks');
        destFrameworks.createSync(recursive: true);
        final Directory destAppFramework = destFrameworks.childDirectory('App.framework');
        if (destAppFramework.existsSync()) {
          destAppFramework.deleteSync(recursive: true);
        }
        // Use `cp -R` to preserve structure / symlinks.
        final ProcessResult cpResult = await globals.processManager.run(
          <String>['cp', '-R', generatedAppFramework.path, destFrameworks.path],
        );
        if (cpResult.exitCode != 0) {
          throw Exception(
            'Failed to embed App.framework into Runner.app: ${cpResult.stderr}',
          );
        }

        // Codesign App.framework for device builds. The on-device installer
        // verifies every Mach-O inside the bundle, so an unsigned (or
        // ad-hoc-signed) App.framework will fail with
        // "0xe8008014 The executable contains an invalid signature."
        // Reuse the identity that xcodebuild used for Flutter.framework —
        // it's already embedded and signed correctly.
        if (!buildInfo.simulator) {
          final File flutterBinary = builtApp
              .childDirectory('Frameworks')
              .childDirectory('Flutter.framework')
              .childFile('Flutter');
          String? identity;
          if (flutterBinary.existsSync()) {
            final ProcessResult displayResult = await globals.processManager.run(
              <String>['codesign', '-d', '--verbose=2', flutterBinary.path],
            );
            // codesign writes its display info to stderr.
            final String info = '${displayResult.stdout}\n${displayResult.stderr}';
            final Match? authorityMatch =
                RegExp(r'Authority=(.+)').firstMatch(info);
            identity = authorityMatch?.group(1)?.trim();
          }
          identity ??= 'Apple Development';
          final ProcessResult signResult = await globals.processManager.run(
            <String>[
              'codesign',
              '--force',
              '--sign', identity,
              '--timestamp=none',
              '--generate-entitlement-der',
              destAppFramework.path,
            ],
          );
          if (signResult.exitCode != 0) {
            globals.logger.printError(
              'codesign App.framework failed (identity="$identity"): ${signResult.stderr}',
            );
            throw Exception('Failed to codesign App.framework');
          }
        }
      }
    }

    globals.logger.printTrace(
      'tvOS application built: build/tvos/$platformSuffix/Runner.app',
    );
  }

  /// Resolves code signing arguments for xcodebuild.
  ///
  /// For simulator builds, no signing is needed.
  /// For device builds, resolves the development team from:
  /// 1. `DEVELOPMENT_TEAM` environment variable
  /// 2. Xcode project's `project.pbxproj` (if already configured)
  /// 3. First Apple Development identity in the keychain
  ///
  /// Returns xcodebuild arguments like `DEVELOPMENT_TEAM=...` and `CODE_SIGN_STYLE=Automatic`.
  Future<List<String>> _resolveSigningArgs(
    Directory tvosProjectDir,
    bool isSimulator,
  ) async {
    if (isSimulator) {
      return const <String>[];
    }

    // 1. Check DEVELOPMENT_TEAM environment variable
    final String? envTeam = globals.platform.environment['DEVELOPMENT_TEAM'];
    if (envTeam != null && envTeam.isNotEmpty) {
      globals.logger.printTrace('Using DEVELOPMENT_TEAM from environment: $envTeam');
      return <String>[
        'DEVELOPMENT_TEAM=$envTeam',
        'CODE_SIGN_STYLE=Automatic',
      ];
    }

    // 2. Check if the Xcode project already has a development team configured
    final String? pbxprojTeam = _readTeamFromPbxproj(tvosProjectDir);
    if (pbxprojTeam != null) {
      globals.logger.printTrace('Using DEVELOPMENT_TEAM from project.pbxproj: $pbxprojTeam');
      return <String>[
        'DEVELOPMENT_TEAM=$pbxprojTeam',
        'CODE_SIGN_STYLE=Automatic',
      ];
    }

    // 3. Try to discover from keychain
    final String? keychainTeam = await _discoverTeamFromKeychain();
    if (keychainTeam != null) {
      globals.logger.printTrace('Auto-detected development team: $keychainTeam');
      return <String>[
        'DEVELOPMENT_TEAM=$keychainTeam',
        'CODE_SIGN_STYLE=Automatic',
      ];
    }

    // No signing identity found — warn the user
    globals.logger.printError(
      'No code signing identity found for physical device build.\n'
      'To fix this, either:\n'
      '  1. Set DEVELOPMENT_TEAM=<your_team_id> environment variable\n'
      '  2. Open tvos/Runner.xcodeproj in Xcode and configure signing\n'
      '  3. Ensure you have an Apple Development certificate in your keychain',
    );
    return const <String>[];
  }

  /// Reads DEVELOPMENT_TEAM from the Xcode project's build settings.
  String? _readTeamFromPbxproj(Directory tvosProjectDir) {
    final File pbxproj = tvosProjectDir
        .childDirectory('Runner.xcodeproj')
        .childFile('project.pbxproj');
    if (!pbxproj.existsSync()) return null;

    final String content = pbxproj.readAsStringSync();
    final RegExp teamRegex = RegExp(r'DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10});');
    final Match? match = teamRegex.firstMatch(content);
    return match?.group(1);
  }

  /// Discovers the development team ID from the first valid Apple Development
  /// signing identity in the login keychain.
  Future<String?> _discoverTeamFromKeychain() async {
    try {
      final ProcessResult result = await globals.processManager.run(
        <String>[
          'security', 'find-identity', '-v', '-p', 'codesigning',
        ],
      );
      if (result.exitCode != 0) return null;

      final String output = result.stdout as String;
      // Look for: "Apple Development: Name (TEAM_ID)"
      final RegExp identityRegex = RegExp(r'Apple Development:.*\(([A-Z0-9]{10})\)');
      final Match? match = identityRegex.firstMatch(output);
      return match?.group(1);
    } on Exception {
      return null;
    }
  }

  /// Copies the pre-built Flutter.framework from engine_artifacts into the
  /// tvos project's Flutter/ directory.
  void _copyFlutterFramework(Directory tvosProjectDir) {
    final TvosArtifacts tvosArtifacts = globals.artifacts! as TvosArtifacts;
    final EnvironmentType envType = buildInfo.simulator
        ? EnvironmentType.simulator
        : EnvironmentType.physical;
    final String frameworkPath = tvosArtifacts.getArtifactPath(
      Artifact.flutterFramework,
      mode: buildInfo.buildInfo.mode,
      environmentType: envType,
    );

    final Directory sourceFramework = globals.fs.directory(frameworkPath);
    final Directory targetFramework = tvosProjectDir
        .childDirectory('Flutter')
        .childDirectory('Flutter.framework');

    if (sourceFramework.existsSync()) {
      if (targetFramework.existsSync()) {
        targetFramework.deleteSync(recursive: true);
      }
      targetFramework.parent.createSync(recursive: true);

      globals.processManager.runSync(<String>[
        'cp', '-R', sourceFramework.path, targetFramework.path,
      ]);
      globals.logger.printTrace('Copied Flutter.framework to ${targetFramework.path}');
    } else {
      globals.logger.printError(
        'Flutter.framework not found at $frameworkPath',
      );
      throw Exception('Flutter.framework not found. Run flutter-tvos precache first.');
    }
  }

  /// Copies tvos_metallibs/ (pre-compiled tvOS Metal shaders) from the CLI
  /// template directory into Runner/tvos_metallibs/ inside the tvOS project.
  /// These binary files cannot be processed by Flutter's template system.
  void _copyMetalLibs(Directory tvosProjectDir) {
    final Directory runnerDir = tvosProjectDir.childDirectory('Runner');
    final Directory targetDir = runnerDir.childDirectory('tvos_metallibs');

    if (targetDir.existsSync()) {
      return; // Already present
    }

    // tvosToolRootDirectory() = flutter-tvos/; templates are at flutter-tvos/templates/
    final Directory cliRoot = tvosToolRootDirectory(globals.fs);
    final Directory sourceDir = cliRoot
        .childDirectory('templates')
        .childDirectory('app')
        .childDirectory('swift')
        .childDirectory('tvos.tmpl')
        .childDirectory('Runner')
        .childDirectory('tvos_metallibs');

    if (sourceDir.existsSync()) {
      globals.processManager.runSync(<String>[
        'cp', '-R', sourceDir.path, targetDir.path,
      ]);
      globals.logger.printTrace('Copied tvos_metallibs to ${targetDir.path}');
    } else {
      globals.logger.printTrace(
        'tvos_metallibs not found at ${sourceDir.path} — Metal shaders will not be available.',
      );
    }
  }

  /// Assembles flutter_assets from the build output (kernel_blob.bin, fonts,
  /// etc.) into tvos/Flutter/flutter_assets/ so the "Copy flutter_assets"
  /// Xcode build phase can bundle them into the .app.
  void _copyFlutterAssets(FlutterProject project, Directory tvosProjectDir) {
    final Directory buildDir = project.directory.childDirectory('build');

    // CopyFlutterBundle writes to outputDir (build/tvos/).
    // Look for kernel_blob.bin there first, then build/flutter_assets/ as fallback.
    Directory? flutterAssetsSource;
    final Directory tvosOutputDir = buildDir.childDirectory('tvos');
    final Directory defaultDir = buildDir.childDirectory('flutter_assets');

    if (tvosOutputDir.childFile('kernel_blob.bin').existsSync()) {
      flutterAssetsSource = tvosOutputDir;
    } else if (defaultDir.existsSync()) {
      flutterAssetsSource = defaultDir;
    }

    final Directory flutterAssetsTarget = tvosProjectDir
        .childDirectory('Flutter')
        .childDirectory('flutter_assets');

    if (flutterAssetsSource != null) {
      flutterAssetsTarget.createSync(recursive: true);

      // Copy kernel_blob.bin and other flutter assets
      for (final FileSystemEntity entity in flutterAssetsSource.listSync()) {
        final String name = globals.fs.path.basename(entity.path);
        // Skip xcodebuild output directories
        if (entity is Directory && (name.contains('Debug-') || name.contains('Release-'))) {
          continue;
        }
        final String destPath = globals.fs.path.join(flutterAssetsTarget.path, name);
        if (entity is File) {
          entity.copySync(destPath);
        } else if (entity is Directory) {
          globals.processManager.runSync(<String>[
            'cp', '-R', entity.path, destPath,
          ]);
        }
      }
      globals.logger.printTrace('Copied flutter_assets to ${flutterAssetsTarget.path}');
    } else {
      globals.logger.printTrace(
        'flutter_assets not found in build output, skipping.',
      );
    }
  }

  /// Ensures GeneratedPluginRegistrant.h/.m exist so the Xcode project
  /// can compile. The actual plugin registration code is written by
  /// ensureReadyForTvosTooling() which runs right before pod install.
  void _generatePluginRegistrant(Directory tvosProjectDir) {
    final Directory runnerDir = tvosProjectDir.childDirectory('Runner');

    final File headerFile = runnerDir.childFile('GeneratedPluginRegistrant.h');
    if (!headerFile.existsSync()) {
      headerFile.writeAsStringSync(
        '//\n'
        '//  Generated file. Do not edit.\n'
        '//\n'
        '\n'
        '#ifndef GeneratedPluginRegistrant_h\n'
        '#define GeneratedPluginRegistrant_h\n'
        '\n'
        '#import <Flutter/Flutter.h>\n'
        '\n'
        'NS_ASSUME_NONNULL_BEGIN\n'
        '\n'
        '@interface GeneratedPluginRegistrant : NSObject\n'
        '+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry;\n'
        '@end\n'
        '\n'
        'NS_ASSUME_NONNULL_END\n'
        '\n'
        '#endif /* GeneratedPluginRegistrant_h */\n',
      );
    }

    final File implFile = runnerDir.childFile('GeneratedPluginRegistrant.m');
    if (!implFile.existsSync()) {
      implFile.writeAsStringSync(
        '//\n'
        '//  Generated file. Do not edit.\n'
        '//\n'
        '\n'
        '#import "GeneratedPluginRegistrant.h"\n'
        '\n'
        '@implementation GeneratedPluginRegistrant\n'
        '\n'
        '+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {\n'
        '}\n'
        '\n'
        '@end\n',
      );
    }
  }

  /// Compiles an AOT snapshot for release/profile builds using gen_snapshot.
  ///
  /// This produces App.framework containing the AOT-compiled Dart code,
  /// which xcodebuild will link into the final .app bundle.
  Future<void> _compileAotSnapshot(
    FlutterProject project,
    Directory tvosProjectDir,
    Environment environment,
  ) async {
    globals.logger.printTrace('Compiling AOT snapshot for tvOS...');

    final TvosArtifacts tvosArtifacts = globals.artifacts! as TvosArtifacts;
    final String genSnapshotPath = tvosArtifacts.getGenSnapshotPath(buildInfo.buildInfo.mode);

    if (!globals.fs.file(genSnapshotPath).existsSync()) {
      throw Exception(
        'gen_snapshot not found at $genSnapshotPath.\n'
        'Run flutter-tvos precache to download tvOS engine artifacts.',
      );
    }

    // Find the kernel snapshot (app.dill) produced by the Dart compiler.
    // KernelSnapshot writes to environment.buildDir (.dart_tool/flutter_build/<hash>/),
    // not outputDir (build/tvos/).
    File kernelSnapshot = environment.buildDir.childFile('app.dill');
    if (!kernelSnapshot.existsSync()) {
      // Fallback to legacy location.
      kernelSnapshot = environment.outputDir.childFile('app.dill');
    }
    if (!kernelSnapshot.existsSync()) {
      throw Exception(
        'Kernel snapshot (app.dill) not found at ${kernelSnapshot.path}.\n'
        'The Dart compilation step may have failed.',
      );
    }

    // Output directory for AOT artifacts
    final Directory aotDir = environment.outputDir.childDirectory('aot');
    aotDir.createSync(recursive: true);

    final String assemblyPath = globals.fs.path.join(aotDir.path, 'snapshot_assembly.S');

    // Run gen_snapshot to produce assembly
    final ProcessResult genSnapshotResult = await globals.processManager.run(
      <String>[
        genSnapshotPath,
        '--deterministic',
        '--snapshot_kind=app-aot-assembly',
        '--assembly=$assemblyPath',
        kernelSnapshot.path,
      ],
    );

    if (genSnapshotResult.exitCode != 0) {
      globals.logger.printError('gen_snapshot failed:');
      globals.logger.printError(genSnapshotResult.stderr as String);
      throw Exception('gen_snapshot failed');
    }

    // Compile assembly to object file
    final String objectPath = globals.fs.path.join(aotDir.path, 'snapshot_assembly.o');
    final ProcessResult ccResult = await globals.processManager.run(
      <String>[
        'xcrun', 'cc',
        '-arch', 'arm64',
        '-isysroot', await _sdkPath(buildInfo.sdkName),
        '-c', assemblyPath,
        '-o', objectPath,
      ],
    );

    if (ccResult.exitCode != 0) {
      globals.logger.printError('Assembly compilation failed:');
      globals.logger.printError(ccResult.stderr as String);
      throw Exception('Assembly compilation failed');
    }

    // Create App.framework from the object file
    final Directory appFramework = tvosProjectDir
        .childDirectory('Flutter')
        .childDirectory('App.framework');
    appFramework.createSync(recursive: true);

    final String appBinaryPath = globals.fs.path.join(appFramework.path, 'App');
    final ProcessResult linkResult = await globals.processManager.run(
      <String>[
        'xcrun', 'clang',
        '-arch', 'arm64',
        '-isysroot', await _sdkPath(buildInfo.sdkName),
        '-dynamiclib',
        '-Xlinker', '-rpath', '-Xlinker', '@executable_path/Frameworks',
        '-Xlinker', '-rpath', '-Xlinker', '@loader_path/Frameworks',
        '-install_name', '@rpath/App.framework/App',
        '-o', appBinaryPath,
        objectPath,
      ],
    );

    if (linkResult.exitCode != 0) {
      globals.logger.printError('Linking App.framework failed:');
      globals.logger.printError(linkResult.stderr as String);
      throw Exception('Linking App.framework failed');
    }

    // Write Info.plist for App.framework
    appFramework.childFile('Info.plist').writeAsStringSync(
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0">\n'
      '<dict>\n'
      '\t<key>CFBundleDevelopmentRegion</key>\n'
      '\t<string>en</string>\n'
      '\t<key>CFBundleExecutable</key>\n'
      '\t<string>App</string>\n'
      '\t<key>CFBundleIdentifier</key>\n'
      '\t<string>io.flutter.flutter.app</string>\n'
      '\t<key>CFBundleInfoDictionaryVersion</key>\n'
      '\t<string>6.0</string>\n'
      '\t<key>CFBundleName</key>\n'
      '\t<string>App</string>\n'
      '\t<key>CFBundlePackageType</key>\n'
      '\t<string>FMWK</string>\n'
      '\t<key>CFBundleVersion</key>\n'
      '\t<string>1.0</string>\n'
      '\t<key>MinimumOSVersion</key>\n'
      '\t<string>13.0</string>\n'
      '</dict>\n'
      '</plist>\n',
    );

    globals.logger.printTrace('AOT compilation complete: ${appFramework.path}');
  }

  /// Returns the SDK path for the given SDK name.
  Future<String> _sdkPath(String sdkName) async {
    final ProcessResult result = await globals.processManager.run(
      <String>['xcrun', '--sdk', sdkName, '--show-sdk-path'],
    );
    if (result.exitCode != 0) {
      throw Exception(
        'Failed to resolve SDK path for "$sdkName" via xcrun '
        '(exit ${result.exitCode}): ${result.stderr}',
      );
    }
    final String path = (result.stdout as String).trim();
    if (path.isEmpty) {
      throw Exception('xcrun returned empty SDK path for "$sdkName".');
    }
    return path;
  }

  /// Generates Generated.xcconfig, Debug.xcconfig, and Release.xcconfig.
  void _generateXcconfigs(
    FlutterProject project,
    Directory tvosProjectDir,
  ) {
    final Directory flutterDir = tvosProjectDir.childDirectory('Flutter');
    flutterDir.createSync(recursive: true);

    // Generated.xcconfig
    final StringBuffer xcconfig = StringBuffer();
    xcconfig.writeln('FLUTTER_APPLICATION_PATH=${project.directory.path}');
    xcconfig.writeln('FLUTTER_TARGET=$targetFile');
    xcconfig.writeln('FLUTTER_BUILD_DIR=${project.directory.childDirectory('build').path}');
    xcconfig.writeln('FLUTTER_BUILD_NAME=${buildInfo.buildInfo.buildName ?? '1.0.0'}');
    xcconfig.writeln('FLUTTER_BUILD_NUMBER=${buildInfo.buildInfo.buildNumber ?? '1'}');

    flutterDir.childFile('Generated.xcconfig').writeAsStringSync(xcconfig.toString());

    // Debug.xcconfig — always write with Pods include so CocoaPods sandbox check passes.
    flutterDir.childFile('Debug.xcconfig').writeAsStringSync(
      '#include "Generated.xcconfig"\n'
      '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"\n',
    );

    // Release.xcconfig — same.
    flutterDir.childFile('Release.xcconfig').writeAsStringSync(
      '#include "Generated.xcconfig"\n'
      '#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"\n',
    );
  }
}
