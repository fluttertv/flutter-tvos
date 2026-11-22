// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Guards how the code assets of a tvOS hook pass reach the app.
//
// Three things are held down here. The manifest key: the tvOS engine is the
// iOS engine and looks its native assets up under `ios_arm64`, so an asset
// filed under what the hooks were told (`tvos`) would never be found. The
// platform check: a hook cannot tell device from simulator, so a library for
// the other one has to stop the build rather than reach the app. And the
// layout, which is upstream's for iOS: one framework per library, loaded as
// `@rpath/<name>.framework/<name>`.

import 'dart:convert' show json;
import 'dart:io' show Process;

import 'package:code_assets/code_assets.dart';
import 'package:file/local.dart' as local;
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/exceptions.dart';
import 'package:flutter_tools/src/build_system/targets/native_assets.dart' show LinkHooks;
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tools/src/isolated/native_assets/dart_hook_result.dart';
import 'package:flutter_tools/src/isolated/native_assets/native_assets.dart';
import 'package:flutter_tools/src/isolated/native_assets/native_assets_manifest.dart';
import 'package:flutter_tvos/build_targets/application.dart';
import 'package:flutter_tvos/build_targets/tvos_code_assets.dart';
import 'package:flutter_tvos/build_targets/tvos_hooks.dart';
import 'package:flutter_tvos/tvos_embed_phase_migration.dart';
import 'package:process/process.dart';

import '../src/common.dart';
import '../src/context.dart';

FlutterCodeAsset _asset(String name, String file, {LinkMode? linkMode}) => FlutterCodeAsset(
  codeAsset: CodeAsset(
    package: 'foo',
    name: name,
    linkMode: linkMode ?? DynamicLoadingBundled(),
    file: Uri.file(file),
  ),
  // What runTvosHooks records: the OS the hook was told.
  os: OS.fromString(tvOSName),
  architecture: Architecture.arm64,
);

String _vtool(String path, String platform, {String minos = '16.0'}) => <String>[
  '$path:',
  'Load command 9',
  '      cmd LC_BUILD_VERSION',
  '  cmdsize 32',
  ' platform $platform',
  '    minos $minos',
  '      sdk 26.5',
  '   ntools 1',
  '     tool 3',
  '  version 1230.0',
].join('\n');

void main() {
  group('parseVtoolBuildVersions', () {
    testWithoutContext('reads the platform and minimum OS of a thin library', () {
      expect(parseVtoolBuildVersions(_vtool('/a.dylib', 'TVOSSIMULATOR', minos: '15.0')), <
        MachOBuildVersion
      >[const MachOBuildVersion(platform: 'TVOSSIMULATOR', minos: '15.0')]);
    });

    testWithoutContext('reads every slice of a fat library', () {
      final String output = [
        _vtool('/a.dylib (architecture arm64)', 'TVOS'),
        _vtool('/a.dylib (architecture x86_64)', 'MACOS', minos: '11.0'),
      ].join('\n');
      expect(parseVtoolBuildVersions(output), <MachOBuildVersion>[
        const MachOBuildVersion(platform: 'TVOS', minos: '16.0'),
        const MachOBuildVersion(platform: 'MACOS', minos: '11.0'),
      ]);
    });

    testWithoutContext('names a platform vtool prints by number', () {
      expect(
        parseVtoolBuildVersions(_vtool('/a.dylib', '8')).single.platform,
        'TVOSSIMULATOR',
      );
    });

    testWithoutContext('reads a library linked before LC_BUILD_VERSION as tvOS', () {
      const output = '/a.dylib:\n'
          'Load command 8\n'
          '      cmd LC_VERSION_MIN_TVOS\n'
          '  cmdsize 16\n'
          '  version 12.0\n'
          '      sdk 13.0\n';
      expect(parseVtoolBuildVersions(output), <MachOBuildVersion>[
        const MachOBuildVersion(platform: 'TVOS', minos: '12.0'),
      ]);
    });

    testWithoutContext('reads an old iPhone library as IOS, so it is refused', () {
      const output = '/a.dylib:\n'
          '      cmd LC_VERSION_MIN_IPHONEOS\n'
          '  cmdsize 16\n'
          '  version 9.0\n'
          '      sdk 10.0\n';
      final List<MachOBuildVersion> versions = parseVtoolBuildVersions(output);
      expect(versions, <MachOBuildVersion>[const MachOBuildVersion(platform: 'IOS', minos: '9.0')]);
      expect(tvosPlatformMismatch(versions, simulator: false), contains('built for IOS'));
    });

    testWithoutContext('finds nothing in output without a build version', () {
      expect(parseVtoolBuildVersions('/a.dylib:\n'), isEmpty);
    });
  });

  group('tvosPlatformMismatch', () {
    testWithoutContext('accepts the platform of the SDK being built', () {
      expect(
        tvosPlatformMismatch(const <MachOBuildVersion>[
          MachOBuildVersion(platform: 'TVOSSIMULATOR'),
        ], simulator: true),
        isNull,
      );
      expect(
        tvosPlatformMismatch(const <MachOBuildVersion>[MachOBuildVersion(platform: 'TVOS')],
            simulator: false),
        isNull,
      );
    });

    testWithoutContext('refuses the other tvOS SDK, which dyld refuses too', () {
      expect(
        tvosPlatformMismatch(const <MachOBuildVersion>[MachOBuildVersion(platform: 'TVOS')],
            simulator: true),
        'built for TVOS, but this simulator build needs TVOSSIMULATOR',
      );
      expect(
        tvosPlatformMismatch(const <MachOBuildVersion>[
          MachOBuildVersion(platform: 'TVOSSIMULATOR'),
        ], simulator: false),
        'built for TVOSSIMULATOR, but this device build needs TVOS',
      );
    });

    testWithoutContext('refuses an iPhone library, which is what the iOS family builds', () {
      expect(
        tvosPlatformMismatch(const <MachOBuildVersion>[MachOBuildVersion(platform: 'IOS')],
            simulator: false),
        contains('built for IOS'),
      );
    });

    testWithoutContext('says nothing when it could read nothing', () {
      expect(tvosPlatformMismatch(const <MachOBuildVersion>[], simulator: false), isNull);
    });
  });

  group('tvosCodeAssetTargetLocations', () {
    testWithoutContext('files assets under the key the engine reads', () {
      // engine/src/flutter/assets/native_assets.cc keys the manifest by a
      // compile-time target whose OS half is `ios` under FML_OS_IOS, which
      // fml/build_config.h derives from TARGET_OS_IPHONE — true on tvOS.
      // Verified on a simulator: the same app with `tvos_arm64` throws "No
      // asset with id ... found" at its first @Native call.
      final Map<FlutterCodeAsset, FlutterCodeAssetTargetLocation> locations =
          tvosCodeAssetTargetLocations(<FlutterCodeAsset>[
            _asset('src/foo.dart', '/hooks/libfoo.dylib'),
          ]);
      final manifest = NativeAssetsManifest.fromTargetLocations(locations);

      expect(manifest.assets.keys, <String>['ios_arm64']);
      expect(tvosNativeAssetsManifestOS, OS.iOS);
      expect(
        json.decode(manifest.toJsonString()),
        <String, Object>{
          'format-version': <int>[1, 0, 0],
          'native-assets': <String, Object>{
            'ios_arm64': <String, Object>{
              'package:foo/src/foo.dart': <String>['absolute', '@rpath/foo.framework/foo'],
            },
          },
        },
      );
      expect(locations.values.single.bundlePath, Uri(path: 'foo.framework/foo'));
    });

    testWithoutContext('bundles nothing for a library looked up in the process', () {
      final Map<FlutterCodeAsset, FlutterCodeAssetTargetLocation> locations =
          tvosCodeAssetTargetLocations(<FlutterCodeAsset>[
            _asset('src/foo.dart', '/hooks/libfoo.dylib', linkMode: LookupInProcess()),
          ]);
      expect(locations.values.single.bundlePath, isNull);
      expect(locations.values.single.runtimePath, const NativeAssetInProcess());
    });
  });

  group('framework names and Info.plist', () {
    testWithoutContext('a library named like the engine or the app is refused', () {
      for (final file in <String>['/hooks/libFlutter.dylib', '/hooks/App.dylib', '/hooks/libflutter.dylib']) {
        expect(
          () => checkReservedFrameworkNames(
            tvosCodeAssetTargetLocations(<FlutterCodeAsset>[_asset('src/foo.dart', file)]),
          ),
          throwsToolExit(message: 'package:foo/src/foo.dart'),
          reason: "$file would overwrite one of the app's own frameworks",
        );
      }
      checkReservedFrameworkNames(
        tvosCodeAssetTargetLocations(<FlutterCodeAsset>[_asset('src/foo.dart', '/hooks/libfoo.dylib')]),
      );
    });

    testWithoutContext('bundle identifiers stay unique', () {
      final Map<Uri, String> ids = codeAssetBundleIdentifiers(<Uri>[
        Uri(path: 'foo_bar.framework/foo_bar'),
        Uri(path: 'foo-bar.framework/foo-bar'),
        Uri(path: 'baz.framework/baz'),
      ]);
      expect(ids.values, <String>[
        'io.flutter.flutter.native-assets.foo-bar',
        'io.flutter.flutter.native-assets.foo-bar-1',
        'io.flutter.flutter.native-assets.baz',
      ]);
    });

    testWithoutContext('the Info.plist declares tvOS', () {
      final String device = codeAssetInfoPlist(
        name: 'foo',
        bundleIdentifier: 'io.flutter.flutter.native-assets.foo',
        minimumOSVersion: '16.0',
        simulator: false,
      );
      expect(device, contains('<key>CFBundleSupportedPlatforms</key>\n\t<array>\n\t\t<string>AppleTVOS</string>'));
      expect(device, contains('<key>DTPlatformName</key>\n\t<string>appletvos</string>'));
      expect(device, contains('<key>UIDeviceFamily</key>\n\t<array>\n\t\t<integer>3</integer>'));
      expect(device, contains('<key>MinimumOSVersion</key>\n\t<string>16.0</string>'));
      expect(device, contains('<key>CFBundlePackageType</key>\n\t<string>FMWK</string>'));
      final String simulator = codeAssetInfoPlist(
        name: 'foo',
        bundleIdentifier: 'io.flutter.flutter.native-assets.foo',
        minimumOSVersion: '16.0',
        simulator: true,
      );
      expect(simulator, contains('<string>AppleTVSimulator</string>'));
      expect(simulator, contains('<string>appletvsimulator</string>'));
    });

    testWithoutContext('compares versions by component', () {
      expect(isVersionAbove('16.0', '15.0'), isTrue);
      expect(isVersionAbove('15.10', '15.9'), isTrue);
      expect(isVersionAbove('15', '15.0'), isFalse);
      expect(isVersionAbove('14.4', '15.0'), isFalse);
    });

    testWithoutContext('reads the deployment target of the Runner project', () {
      final fs = MemoryFileSystem.test();
      final Directory tvos = fs.directory('/app/tvos');
      expect(readTvosDeploymentTarget(tvos), isNull);
      tvos.childDirectory('Runner.xcodeproj').childFile('project.pbxproj')
        ..createSync(recursive: true)
        ..writeAsStringSync('\t\t\t\tTVOS_DEPLOYMENT_TARGET = 15.0;\n');
      expect(readTvosDeploymentTarget(tvos), '15.0');
    });
  });

  group('installTvosCodeAssets', () {
    late MemoryFileSystem fileSystem;
    late FakeProcessManager processManager;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
      processManager = FakeProcessManager.empty();
    });

    Future<List<File>> install({
      required bool simulator,
      BuildMode mode = BuildMode.debug,
      String? deploymentTarget,
      List<FlutterCodeAsset>? assets,
    }) {
      return installTvosCodeAssets(
        codeAssets: assets ?? <FlutterCodeAsset>[_asset('src/foo.dart', '/hooks/libfoo.dylib')],
        targetDirectory: fileSystem.directory('/build/native_assets'),
        manifestFile: fileSystem.file('/build/native_assets.json'),
        buildMode: mode,
        simulator: simulator,
        fileSystem: fileSystem,
        deploymentTarget: deploymentTarget,
      );
    }

    testUsingContext('refuses a statically linked asset as a tool error', () async {
      await expectLater(
        install(
          simulator: true,
          assets: <FlutterCodeAsset>[
            _asset('src/foo.dart', '/hooks/libfoo.a', linkMode: StaticLinking()),
          ],
        ),
        throwsToolExit(message: 'statically linked code asset'),
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('warns when a library needs a newer tvOS than the app', () async {
      processManager.addCommand(
        FakeCommand(
          command: const <String>['xcrun', 'vtool', '-show-build', '/hooks/libfoo.dylib'],
          stdout: _vtool('/hooks/libfoo.dylib', 'TVOSSIMULATOR', minos: '17.0'),
        ),
      );
      const dylib = '/build/native_assets/foo.framework/foo';
      processManager.addCommands(const <FakeCommand>[
        FakeCommand(
          command: <String>['xcrun', 'lipo', '-create', '-output', dylib, '/hooks/libfoo.dylib'],
        ),
        FakeCommand(
          command: <String>['xcrun', 'otool', '-D', dylib],
          stdout: '$dylib:\n@rpath/libfoo.dylib',
        ),
        FakeCommand(
          command: <String>[
            'xcrun',
            'install_name_tool',
            '-id',
            '@rpath/foo.framework/foo',
            '-change',
            '@rpath/libfoo.dylib',
            '@rpath/foo.framework/foo',
            dylib,
          ],
        ),
        FakeCommand(
          command: <String>[
            'xcrun',
            'codesign',
            '--force',
            '--sign',
            '-',
            '--timestamp=none',
            '/build/native_assets/foo.framework',
          ],
        ),
      ]);

      await install(simulator: true, deploymentTarget: '15.0');

      expect(testLogger.warningText, contains('requires tvOS 17.0'));
      expect(testLogger.warningText, contains('deploys to tvOS 15.0'));
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('installs a framework the way iOS does, and the manifest', () async {
      // A library from an earlier build that is no longer produced.
      fileSystem.directory('/build/native_assets/old.framework').createSync(recursive: true);
      processManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: const <String>['xcrun', 'vtool', '-show-build', '/hooks/libfoo.dylib'],
          stdout: _vtool('/hooks/libfoo.dylib', 'TVOSSIMULATOR'),
        ),
        const FakeCommand(
          command: <String>[
            'xcrun',
            'lipo',
            '-create',
            '-output',
            '/build/native_assets/foo.framework/foo',
            '/hooks/libfoo.dylib',
          ],
        ),
        const FakeCommand(
          command: <String>['xcrun', 'otool', '-D', '/build/native_assets/foo.framework/foo'],
          stdout: '/build/native_assets/foo.framework/foo (architecture arm64):\n'
              '@rpath/libfoo.dylib',
        ),
        const FakeCommand(
          command: <String>[
            'xcrun',
            'install_name_tool',
            '-id',
            '@rpath/foo.framework/foo',
            '-change',
            '@rpath/libfoo.dylib',
            '@rpath/foo.framework/foo',
            '/build/native_assets/foo.framework/foo',
          ],
        ),
        const FakeCommand(
          command: <String>[
            'xcrun',
            'codesign',
            '--force',
            '--sign',
            '-',
            '--timestamp=none',
            '/build/native_assets/foo.framework',
          ],
        ),
      ]);

      final List<File> installed = await install(simulator: true);

      expect(processManager.hasRemainingExpectations, isFalse);
      expect(fileSystem.directory('/build/native_assets/old.framework').existsSync(), isFalse);
      final String plist =
          fileSystem.file('/build/native_assets/foo.framework/Info.plist').readAsStringSync();
      expect(
        plist,
        contains('<key>MinimumOSVersion</key>\n\t<string>16.0</string>'),
        reason: "App Store validation compares this to the library's own minos (ITMS-90208)",
      );
      final manifest =
          json.decode(fileSystem.file('/build/native_assets.json').readAsStringSync())
              as Map<String, Object?>;
      expect((manifest['native-assets']! as Map<String, Object?>).keys, <String>['ios_arm64']);
      expect(
        installed.map((File f) => f.path),
        containsAll(<String>[
          '/build/native_assets.json',
          '/build/native_assets/foo.framework/foo',
          '/build/native_assets/foo.framework/Info.plist',
        ]),
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('strips and keeps a dSYM outside debug', () async {
      processManager.addCommands(<FakeCommand>[
        FakeCommand(
          command: const <String>['xcrun', 'vtool', '-show-build', '/hooks/libfoo.dylib'],
          stdout: _vtool('/hooks/libfoo.dylib', 'TVOS'),
        ),
        const FakeCommand(
          command: <String>[
            'xcrun',
            'lipo',
            '-create',
            '-output',
            '/build/native_assets/foo.framework/foo',
            '/hooks/libfoo.dylib',
          ],
        ),
        FakeCommand(
          command: const <String>[
            'xcrun',
            'dsymutil',
            '/build/native_assets/foo.framework/foo',
            '-o',
            '/build/native_assets/foo.framework.dSYM',
          ],
          onRun: (_) => fileSystem
              .file('/build/native_assets/foo.framework.dSYM/Contents/Info.plist')
              .createSync(recursive: true),
        ),
        const FakeCommand(
          command: <String>['xcrun', 'strip', '-x', '-S', '/build/native_assets/foo.framework/foo'],
        ),
        const FakeCommand(
          command: <String>['xcrun', 'otool', '-D', '/build/native_assets/foo.framework/foo'],
          stdout: '/build/native_assets/foo.framework/foo:\n@rpath/libfoo.dylib',
        ),
        const FakeCommand(
          command: <String>[
            'xcrun',
            'install_name_tool',
            '-id',
            '@rpath/foo.framework/foo',
            '-change',
            '@rpath/libfoo.dylib',
            '@rpath/foo.framework/foo',
            '/build/native_assets/foo.framework/foo',
          ],
        ),
        const FakeCommand(
          command: <String>[
            'xcrun',
            'codesign',
            '--force',
            '--sign',
            '-',
            '/build/native_assets/foo.framework',
          ],
        ),
      ]);

      final List<File> installed = await install(simulator: false, mode: BuildMode.release);

      expect(processManager.hasRemainingExpectations, isFalse);
      expect(
        installed.map((File f) => f.path),
        contains('/build/native_assets/foo.framework.dSYM/Contents/Info.plist'),
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('fails a simulator build on a device library, installing nothing', () async {
      // The hooks cache serves a device build and a simulator build the same
      // library, so this is what switching from one to the other looks like
      // with a package that picked the device SDK. Installing it would give an
      // app that dies at its first @Native call; dyld says only "incompatible
      // platform", long after the build that could have said why.
      processManager.addCommand(
        FakeCommand(
          command: const <String>['xcrun', 'vtool', '-show-build', '/hooks/libfoo.dylib'],
          stdout: _vtool('/hooks/libfoo.dylib', 'TVOS'),
        ),
      );

      await expectLater(
        install(simulator: true),
        throwsToolExit(message: 'built for TVOS, but this simulator build needs TVOSSIMULATOR'),
      );
      expect(processManager.hasRemainingExpectations, isFalse);
      expect(fileSystem.file('/build/native_assets.json').existsSync(), isFalse);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('writes an empty manifest when there is nothing to install', () async {
      await installTvosCodeAssets(
        codeAssets: const <FlutterCodeAsset>[],
        targetDirectory: fileSystem.directory('/build/native_assets'),
        manifestFile: fileSystem.file('/build/native_assets.json'),
        buildMode: BuildMode.debug,
        simulator: true,
        fileSystem: fileSystem,
      );

      expect(
        json.decode(fileSystem.file('/build/native_assets.json').readAsStringSync()),
        <String, Object>{
          'format-version': <int>[1, 0, 0],
          'native-assets': <String, Object>{},
        },
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });
  });

  group('TvosInstallCodeAssets', () {
    late MemoryFileSystem fileSystem;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
    });

    Environment environment(Map<String, String> defines, DartHooksResult result) {
      final env = Environment.test(
        fileSystem.currentDirectory,
        defines: <String, String>{kBuildMode: BuildMode.debug.cliName, ...defines},
        artifacts: Artifacts.test(),
        processManager: FakeProcessManager.empty(),
        fileSystem: fileSystem,
        logger: BufferLogger.test(),
        platform: FakePlatform(),
      );
      env.buildDir.createSync(recursive: true);
      env.buildDir
          .childFile(LinkHooks.resultFilename)
          .writeAsStringSync(json.encode(result.toJson()));
      return env;
    }

    testUsingContext('runs after the tvOS hook pass', () {
      expect(
        const TvosInstallCodeAssets().dependencies.map((Target t) => t.name),
        <String>[const TvosBuildHooks().name],
      );
      expect(
        const TvosCopyFlutterBundle().dependencies.map((Target t) => t.name),
        contains(const TvosInstallCodeAssets().name),
        reason: 'CopyFlutterBundle bundles native_assets.json as NativeAssetsManifest.json',
      );
    });

    testUsingContext('writes the manifest with no code assets and no SDK root', () async {
      final Environment env = environment(const <String, String>{}, DartHooksResult.empty());

      await const TvosInstallCodeAssets().build(env);

      expect(env.buildDir.childFile('native_assets.json').existsSync(), isTrue);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.empty(),
    });

    testUsingContext('needs the SDK root to check a library against', () async {
      final Environment env = environment(
        const <String, String>{},
        DartHooksResult(
          buildStart: DateTime(2026),
          buildEnd: DateTime(2026),
          codeAssets: <FlutterCodeAsset>[_asset('src/foo.dart', '/hooks/libfoo.dylib')],
          dataAssets: const [],
          dependencies: const <Uri>[],
        ),
      );

      await expectLater(
        const TvosInstallCodeAssets().build(env),
        throwsA(isA<MissingDefineException>()),
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.empty(),
    });
  });

  group('staging for Xcode', () {
    late MemoryFileSystem fileSystem;
    late FakeProcessManager processManager;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
      processManager = FakeProcessManager.empty();
    });

    testUsingContext('mirrors the installed frameworks into tvos/Flutter', () async {
      fileSystem.directory('/build/native_assets/foo.framework').createSync(recursive: true);
      fileSystem.directory('/tvos/Flutter/native_assets/stale.framework').createSync(recursive: true);
      processManager.addCommand(
        FakeCommand(
          command: const <String>[
            'rsync',
            '-a',
            '/build/native_assets/',
            '/tvos/Flutter/native_assets/',
          ],
          onRun: (_) => fileSystem
              .directory('/tvos/Flutter/native_assets/foo.framework')
              .createSync(recursive: true),
        ),
      );

      await stageCodeAssetFrameworks(
        source: fileSystem.directory('/build/native_assets'),
        target: fileSystem.directory('/tvos/Flutter/native_assets'),
      );

      expect(processManager.hasRemainingExpectations, isFalse);
      expect(
        stagedCodeAssetFrameworks(fileSystem.directory('/tvos/Flutter/native_assets')),
        <String>['foo.framework'],
        reason: 'a framework from an earlier build must not be embedded',
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('removes the staged directory when nothing was installed', () async {
      fileSystem.directory('/build/native_assets').createSync(recursive: true);
      fileSystem.directory('/tvos/Flutter/native_assets/stale.framework').createSync(recursive: true);

      await stageCodeAssetFrameworks(
        source: fileSystem.directory('/build/native_assets'),
        target: fileSystem.directory('/tvos/Flutter/native_assets'),
      );

      expect(fileSystem.directory('/tvos/Flutter/native_assets').existsSync(), isFalse);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });
  });

  group('TvosEmbedPhaseMigration', () {
    String project(String script, {bool withInput = false}) => '''
		AAF50000000000000000F00D /* Embed Flutter.framework */ = {
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputPaths = (
				"\$(PROJECT_DIR)/Flutter/Flutter.framework",
${withInput ? '\t\t\t\t"\$(PROJECT_DIR)/Flutter/native_assets",\n' : ''}			);
			name = "Embed Flutter.framework";
			shellScript = "$script";
		};
''';

    for (final MapEntry<String, String> generated
        in earlierEmbedFlutterFrameworkScripts.entries) {
      testWithoutContext('updates the phase ${generated.key} generated', () {
        final String? migrated = TvosEmbedPhaseMigration.migrateEmbedPhase(project(generated.value));
        expect(migrated, project(currentEmbedFlutterFrameworkScript, withInput: true));
        expect(pbxprojEmbedsCodeAssets(migrated!), isTrue);
        // And it is then left alone.
        expect(TvosEmbedPhaseMigration.migrateEmbedPhase(migrated), isNull);
      });
    }

    testWithoutContext('leaves an edited phase alone', () {
      final edited =
          '${earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!}echo mine\\n';
      expect(TvosEmbedPhaseMigration.migrateEmbedPhase(project(edited)), isNull);
    });

    testWithoutContext('leaves a project without the phase alone', () {
      expect(TvosEmbedPhaseMigration.migrateEmbedPhase('// !\$*UTF8*\$!\n{}'), isNull);
    });

    // Two native targets, each with its own "Embed Flutter.framework" phase,
    // and the other target's listed first in the file. The build runs Runner.
    String twoTargets({required String runnerScript, required String otherScript}) => '''
		AAF50000000000000000BEEF /* Embed Flutter.framework */ = {
			isa = PBXShellScriptBuildPhase;
			inputPaths = (
				"\$(PROJECT_DIR)/Flutter/Flutter.framework",
			);
			name = "Embed Flutter.framework";
			shellScript = "$otherScript";
		};
		AAF50000000000000000F00D /* Embed Flutter.framework */ = {
			isa = PBXShellScriptBuildPhase;
			inputPaths = (
				"\$(PROJECT_DIR)/Flutter/Flutter.framework",
			);
			name = "Embed Flutter.framework";
			shellScript = "$runnerScript";
		};
		1111111111111111111111AA /* Other */ = {
			isa = PBXNativeTarget;
			buildPhases = (
				AAF50000000000000000BEEF /* Embed Flutter.framework */,
			);
			name = Other;
		};
		97C146ED1CF9000F007C117D /* Runner */ = {
			isa = PBXNativeTarget;
			buildPhases = (
				AAF50000000000000000F00D /* Embed Flutter.framework */,
			);
			name = Runner;
		};
''';

    testWithoutContext('migrates every generated phase, not only the first', () {
      final String old = earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!;
      final String? migrated = TvosEmbedPhaseMigration.migrateEmbedPhase(
        twoTargets(runnerScript: old, otherScript: old),
      );
      expect(
        RegExp(RegExp.escape('shellScript = "$currentEmbedFlutterFrameworkScript";'))
            .allMatches(migrated!),
        hasLength(2),
      );
      expect(RegExp(RegExp.escape('Flutter/native_assets",')).allMatches(migrated), hasLength(2));
    });

    testWithoutContext("judges the Runner target's phase, not the first in the file", () {
      final edited = '${earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!}echo mine\\n';
      // The other target embeds code assets, the Runner target does not: a
      // whole-file search said "embeds", so a signed build shipped without them.
      expect(
        pbxprojEmbedsCodeAssets(
          twoTargets(runnerScript: edited, otherScript: currentEmbedFlutterFrameworkScript),
        ),
        isFalse,
      );
      expect(
        pbxprojEmbedsCodeAssets(
          twoTargets(runnerScript: currentEmbedFlutterFrameworkScript, otherScript: edited),
        ),
        isTrue,
      );
      expect(
        runnerEmbedFlutterFrameworkScripts(
          twoTargets(runnerScript: 'runner', otherScript: 'other'),
        ),
        <String>['runner'],
      );
    });

    testWithoutContext('a phase updated by hand with the printed lines counts', () {
      final String byHand = earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']! +
          pbxprojEscapeScript(kCodeAssetEmbedScript);
      expect(byHand, currentEmbedFlutterFrameworkScript);
      expect(pbxprojEmbedsCodeAssets(project('${byHand}echo mine\\n')), isTrue);
      expect(pbxprojEmbedsCodeAssets(project(earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!)),
          isFalse);
      expect(pbxprojEmbedsCodeAssets('{}'), isFalse, reason: 'no phase embeds nothing');
    });

    testWithoutContext('the embed lines fail the phase when a step fails', () {
      expect(kCodeAssetEmbedScript, contains(r': "${DEST_FRAMEWORKS:?}"'));
      for (final String line in kCodeAssetEmbedScript.split('\n')) {
        if (RegExp(r'^\s*(rsync|codesign|rm) ').hasMatch(line)) {
          expect(line, endsWith('|| exit 1'), reason: line);
        }
      }
    });

    test('reports a project it cannot write and carries on', () async {
      final Directory dir = const local.LocalFileSystem().systemTempDirectory.createTempSync('tvos_ro.');
      addTearDown(() {
        Process.runSync('chmod', <String>['-R', 'u+w', dir.path]);
        dir.deleteSync(recursive: true);
      });
      final File pbxproj = dir.childFile('project.pbxproj')
        ..writeAsStringSync(project(earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!));
      Process.runSync('chmod', <String>['a-w', pbxproj.path]);
      final logger = BufferLogger.test();

      await TvosEmbedPhaseMigration(pbxproj, logger).migrate();

      expect(logger.errorText, contains('Could not update the "Embed Flutter.framework" build phase'));
      expect(pbxproj.readAsStringSync(), isNot(contains('Flutter/native_assets')));
    });

    testUsingContext('writes the project and says so', () async {
      final fs = MemoryFileSystem.test();
      final File pbxproj = fs.file('/tvos/Runner.xcodeproj/project.pbxproj')
        ..createSync(recursive: true)
        ..writeAsStringSync(project(earlierEmbedFlutterFrameworkScripts['1.9.0-1.12.2']!));
      final logger = BufferLogger.test();

      await TvosEmbedPhaseMigration(pbxproj, logger).migrate();

      expect(pbxproj.readAsStringSync(), contains('Flutter/native_assets'));
      expect(logger.statusText, contains('Updated the "Embed Flutter.framework" build phase'));
    });
  });

  group('older projects', () {
    test('removes only code-asset frameworks that are no longer staged', () {
      // Real files and the real plutil: a framework Xcode built — a CocoaPods
      // plugin's under use_frameworks! — has a binary Info.plist, which a text
      // read cannot decode.
      const fs = local.LocalFileSystem();
      final Directory root = fs.systemTempDirectory.createTempSync('tvos_stale.');
      addTearDown(() => root.deleteSync(recursive: true));
      final Directory frameworks = root.childDirectory('Runner.app').childDirectory('Frameworks');
      void framework(String name, String id, {bool binary = false}) {
        final File plist = frameworks.childDirectory(name).childFile('Info.plist')
          ..createSync(recursive: true)
          ..writeAsStringSync(
            codeAssetInfoPlist(name: name, bundleIdentifier: id, minimumOSVersion: '15.0', simulator: true),
          );
        if (binary) {
          expect(Process.runSync('plutil', <String>['-convert', 'binary1', plist.path]).exitCode, 0);
          expect(() => plist.readAsStringSync(), throwsA(isA<FileSystemException>()));
        }
      }
      framework('Flutter.framework', 'io.flutter.flutter');
      framework('App.framework', 'io.flutter.flutter.app');
      framework('SomePod.framework', 'org.cocoapods.SomePod', binary: true);
      framework('kept.framework', '${kCodeAssetBundleIdentifierPrefix}kept');
      framework('gone.framework', '${kCodeAssetBundleIdentifierPrefix}gone', binary: true);
      frameworks.childDirectory('Garbage.framework').childFile('Info.plist')
        ..createSync(recursive: true)
        ..writeAsBytesSync(<int>[0xff, 0xfe, 0x00, 0x01]);
      final parser = PlistParser(
        fileSystem: fs,
        processManager: const LocalProcessManager(),
        logger: BufferLogger.test(),
      );

      expect(
        NativeTvosBundle.removeStaleCodeAssetFrameworks(frameworks, <String>{'kept.framework'}, parser),
        <String>['gone.framework'],
      );
      expect(
        frameworks.listSync().map((FileSystemEntity e) => e.basename).toSet(),
        <String>{
          'Flutter.framework',
          'App.framework',
          'SomePod.framework',
          'kept.framework',
          'Garbage.framework',
        },
      );

      // Nothing staged: what every build passes before Xcode runs. Every code
      // asset goes, a pod's framework stays.
      expect(NativeTvosBundle.removeStaleCodeAssetFrameworks(frameworks, <String>{}, parser),
          <String>['kept.framework']);
      expect(frameworks.childDirectory('SomePod.framework').existsSync(), isTrue);
    });
  });
}
