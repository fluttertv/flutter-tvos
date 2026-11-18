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

import 'package:code_assets/code_assets.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/exceptions.dart';
import 'package:flutter_tools/src/build_system/targets/native_assets.dart' show LinkHooks;
import 'package:flutter_tools/src/isolated/native_assets/dart_hook_result.dart';
import 'package:flutter_tools/src/isolated/native_assets/native_assets.dart';
import 'package:flutter_tools/src/isolated/native_assets/native_assets_manifest.dart';
import 'package:flutter_tvos/build_targets/application.dart';
import 'package:flutter_tvos/build_targets/tvos_code_assets.dart';
import 'package:flutter_tvos/build_targets/tvos_hooks.dart';

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

  group('installTvosCodeAssets', () {
    late MemoryFileSystem fileSystem;
    late FakeProcessManager processManager;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
      processManager = FakeProcessManager.empty();
    });

    Future<List<File>> install({required bool simulator, BuildMode mode = BuildMode.debug}) {
      return installTvosCodeAssets(
        codeAssets: <FlutterCodeAsset>[_asset('src/foo.dart', '/hooks/libfoo.dylib')],
        targetDirectory: fileSystem.directory('/build/native_assets'),
        manifestFile: fileSystem.file('/build/native_assets.json'),
        buildMode: mode,
        simulator: simulator,
        fileSystem: fileSystem,
      );
    }

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

    testWithoutContext('tells a current embed phase from one that predates code assets', () {
      expect(
        NativeTvosBundle.pbxprojEmbedsCodeAssets(
          r'NATIVE_ASSETS_SRC=\"${PROJECT_DIR}/Flutter/native_assets\"',
        ),
        isTrue,
      );
      expect(
        NativeTvosBundle.pbxprojEmbedsCodeAssets(
          r'FRAMEWORK_SRC=\"${PROJECT_DIR}/Flutter/Flutter.framework\"',
        ),
        isFalse,
      );
    });
  });
}
