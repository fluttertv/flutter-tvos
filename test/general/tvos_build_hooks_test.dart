// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Guards what a package's build hook is told when it runs for tvOS.
//
// Two things are being held down. First, that a hook is told `tvos` — the
// platform it is actually building for — and not `ios`, which is what going
// through flutter_tools' own target translation would say, because its set of
// target platforms has no tvOS in it.
//
// Second, that it is told anything at all. The hooks protocol carries the
// target OS inside the *code* asset config, so a pass asking for data assets
// alone leaves a hook with no way to know. A package that picks a graphics
// backend from that — a 3D engine compiling shader bundles, say — then guesses,
// and guesses wrong: it compiles GLES for a Metal engine. Nothing throws. The
// app draws a black frame, which is why this is a test and not a comment.

import 'dart:convert' show json;
import 'dart:io' as io;

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/asset.dart' show FlutterHookResult;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart' hide BuildResult;
import 'package:flutter_tools/src/build_system/targets/native_assets.dart' show LinkHooks;
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/isolated/native_assets/native_assets.dart';
import 'package:flutter_tools/src/isolated/native_assets/targets.dart';
import 'package:flutter_tools/src/macos/xcode.dart' show Xcode;
import 'package:flutter_tvos/build_targets/tvos_hooks.dart';
import 'package:hooks/hooks.dart';
import 'package:hooks_runner/hooks_runner.dart';
import 'package:test/fake.dart';

import '../../flutter/packages/flutter_tools/test/general.shard/isolated/fake_native_assets_build_runner.dart'
    show FakeFlutterNativeAssetsBuilderResult;
import '../../flutter/packages/flutter_tools/test/src/fakes.dart' show TestFeatureFlags;
import '../../flutter/packages/flutter_tools/test/src/package_config.dart';
import '../src/common.dart';
import '../src/context.dart';

/// A build runner that records what the hooks would have been told.
///
/// Upstream's fake is not usable here: it reaches for `Directory.systemTemp`,
/// which the test harness's filesystem guard refuses. This one builds the same
/// input the real runner would, from fixed paths, and never touches disk.
class _RecordingBuildRunner implements FlutterNativeAssetsBuildRunner {
  _RecordingBuildRunner({
    this.failuresBeforeSuccess = 0,
    this.alwaysFails = false,
    this.assets = const <EncodedAsset>[],
    this.dependencies = const <Uri>[],
  });

  /// What the hooks "produced". Empty in tests that only care about the input.
  final List<EncodedAsset> assets;
  final List<Uri> dependencies;

  /// How many attempts refuse to build before one succeeds. One stands for a
  /// hook that cannot cope with being told `tvos` but can build for the iOS
  /// family, which is the case the retry exists for.
  final int failuresBeforeSuccess;

  /// A hook that cannot build under either name.
  final bool alwaysFails;

  /// Every input a hook was handed, in order.
  final inputs = <BuildInput>[];

  BuildInput? get lastInput => inputs.isEmpty ? null : inputs.last;

  @override
  Future<List<String>> packagesWithNativeAssets() async => const <String>['some_package'];

  @override
  Future<BuildResult?> build({
    required List<ProtocolExtension> extensions,
    required bool linkingEnabled,
  }) async {
    // `package:hooks` resolves these against dart:io, not the injected file
    // system, and creates the output directory as a side effect. The harness's
    // filesystem guard only tolerates that inside the system temp directory.
    final base = '${io.Directory.systemTemp.resolveSymbolicLinksSync()}/tvos_build_hooks_test';
    final input = BuildInputBuilder()
      ..setupShared(
        packageRoot: Uri.directory('$base/some_package'),
        packageName: 'some_package',
        outputDirectoryShared: Uri.directory('$base/shared'),
        outputFile: Uri.file('$base/some_package/output.json'),
      )
      ..setupBuildInput()
      ..config.setupBuild(linkingEnabled: linkingEnabled);
    for (final extension in extensions) {
      extension.setupBuildInput(input);
    }
    inputs.add(BuildInput(input.json));
    if (alwaysFails || inputs.length <= failuresBeforeSuccess) {
      return null;
    }
    return FakeFlutterNativeAssetsBuilderResult(
      encodedAssets: assets,
      dependencies: dependencies,
    );
  }

  @override
  Future<LinkResult?> link({
    required List<ProtocolExtension> extensions,
    required BuildResult buildResult,
    required File? recordedUsesFile,
  }) async => throw StateError('the data pass has no link phase');

  @override
  Future<void> setCCompilerConfig(CodeAssetTarget target) async {
    // The real runner discovers a host compiler here. Nothing is compiled in
    // this test, but the field is `late` and read while building extensions.
    target.cCompilerConfigSync = null;
  }
}

/// Stands in for the real Xcode when the fallback has to derive an SDK root
/// because the environment carries none.
class _FakeXcode extends Fake implements Xcode {
  @override
  Future<String> sdkLocation(EnvironmentType environmentType) async =>
      '/sdk/iPhoneOS.sdk';
}

void main() {
  late FileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    fileSystem.file('pubspec.yaml')
      ..createSync()
      ..writeAsStringSync('name: example\n');
    writePackageConfigFiles(
      directory: fileSystem.currentDirectory,
      mainLibName: 'example',
    );
  });

  /// [sdkRoot] null stands for the environment a resident session assembles,
  /// which carries `kTargetFile` and `kBuildMode` and nothing else.
  Environment buildEnv({Logger? logger, String? sdkRoot = '/sdk/iPhoneSimulator.sdk'}) {
    final env = Environment.test(
      fileSystem.currentDirectory,
      defines: <String, String>{
        kBuildMode: BuildMode.debug.cliName,
        // tvOS rides the iOS pipeline for everything downstream of here —
        // the AOT snapshot, the Xcode invocation. The hooks are the one place
        // it does not, which is what this file is about.
        kTargetPlatform: TargetPlatform.ios.getName(),
        // Only the fallback reads this, to build a faithful iOS input.
        kSdkRoot: ?sdkRoot,
      },
      inputs: <String, String>{},
      artifacts: Artifacts.test(),
      processManager: FakeProcessManager.any(),
      fileSystem: fileSystem,
      logger: logger ?? BufferLogger.test(),
      platform: FakePlatform(),
    );
    env.buildDir.createSync(recursive: true);
    return env;
  }

  group('TvosBuildHooks', () {
    testUsingContext('tells the hook what it is building for', () async {
      final runner = _RecordingBuildRunner();

      await TvosBuildHooks(buildRunner: runner).build(buildEnv());

      final BuildInput? recorded = runner.lastInput;
      expect(recorded, isNotNull, reason: 'no hook was invoked at all');
      final BuildInput seen = recorded!;
      expect(
        seen.config.buildCodeAssets,
        isTrue,
        reason: 'without code assets the input carries no target OS, and a '
            'package that reads one falls back to its OS-less default',
      );
      // Read off the wire rather than through `config.code`: the wire is what
      // a hook sees, whichever code_assets it resolved. One on 1.x throws on
      // the name when it parses it; one on 2.x reads it as an `OS`.
      final code = (seen.config.json['extensions']! as Map<String, Object?>)['code_assets']!
          as Map<String, Object?>;
      expect(
        code['target_os'],
        'tvos',
        reason: 'tvOS is its own platform, and a hook told `ios` cannot '
            'tell the difference or ask',
      );
      expect(code['target_architecture'], Architecture.arm64.name);
      // And through the typed accessor, as a hook on code_assets 2.x reads it.
      expect(seen.config.code.targetOS, OS.fromString('tvos'));
      expect(
        code.containsKey('ios'),
        isFalse,
        reason: 'an iPhone SDK and deployment target describe a platform this '
            'is not',
      );
      expect(seen.config.buildDataAssets, isTrue);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
    });

    testUsingContext('falls back to the iOS family when the name is refused', () async {
      // A hook that dies on an unfamiliar target OS is the common case today:
      // code_assets parsed `target_os` eagerly until 2.0.0. The build has to
      // keep working, so the pass is retried under the name such a hook can
      // read — which is what tvOS builds asked for before this.
      final runner = _RecordingBuildRunner(failuresBeforeSuccess: 1);
      final logger = BufferLogger.test();

      await TvosBuildHooks(buildRunner: runner).build(buildEnv(logger: logger));

      expect(runner.inputs, hasLength(2), reason: 'the pass was not retried');
      // The hooks have just printed a stack trace; an unexplained second
      // attempt after one reads as a broken build.
      expect(logger.statusText, contains('Retrying as the iOS family'));
      expect(
        logger.statusText,
        contains('That is a guess'),
        reason: 'every failure kind arrives here as a null, so the retry must '
            'not claim to know which one it was',
      );
      Map<String, Object?> code(BuildInput input) =>
          (input.config.json['extensions']! as Map<String, Object?>)['code_assets']!
              as Map<String, Object?>;
      expect(code(runner.inputs.first)['target_os'], 'tvos');
      expect(code(runner.inputs.last)['target_os'], 'ios');
      expect(
        code(runner.inputs.last).containsKey('ios'),
        isTrue,
        reason: 'a hook told `ios` goes on to read the iOS config, so the '
            'fallback has to be a faithful iOS input and not just an iOS name',
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
    });

    testUsingContext('keeps the data assets and drops the code assets', () async {
      // Every other test here drives a runner that produces nothing, so none of
      // them can see what this pass does with what a hook returns. Without an
      // asset in flight, inverting the `isDataAsset` filter — which is the
      // original bug, an app shipping no generated assets — leaves the suite
      // green.
      final EncodedAsset dataAsset = DataAsset(
        package: 'some_package',
        name: 'shaders/bundle.bin',
        file: Uri.file('/tmp/bundle.bin'),
      ).encode();
      final EncodedAsset codeAsset = CodeAsset(
        package: 'some_package',
        name: 'native.dylib',
        linkMode: DynamicLoadingBundled(),
        file: Uri.file('/tmp/native.dylib'),
      ).encode();
      final runner = _RecordingBuildRunner(
        assets: <EncodedAsset>[dataAsset, codeAsset],
        dependencies: <Uri>[Uri.file('/tmp/shader.glsl')],
      );
      final Environment env = buildEnv();

      await TvosBuildHooks(buildRunner: runner).build(env);

      final written =
          json.decode(env.buildDir.childFile(LinkHooks.resultFilename).readAsStringSync())
              as Map<String, Object?>;
      expect(
        written['data_assets'],
        hasLength(1),
        reason: 'the data asset a hook produced has to reach CopyFlutterBundle',
      );
      expect(
        written['code_assets'],
        isEmpty,
        reason: 'nothing a code-asset hook produces is installed into a tvOS app',
      );
      expect(written['dependencies'], hasLength(1));
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
    });

    testUsingContext('does not run the hooks when data assets are off', () async {
      // The product of this pass is data assets; with them off there is nothing
      // to collect, and running every hook to collect it costs time and can
      // fail the build outright. The feature is off by default, so this is the
      // path most installs take.
      final runner = _RecordingBuildRunner();
      final logger = BufferLogger.test();

      await TvosBuildHooks(buildRunner: runner).build(buildEnv(logger: logger));

      expect(runner.inputs, isEmpty, reason: 'no hook should have been invoked');
      expect(logger.warningText, contains('some_package'));
      expect(
        logger.warningText,
        contains('flutter config --enable-dart-data-assets'),
        reason: 'the warning has to name the one command that fixes it',
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true),
    });

    testUsingContext('the fallback keeps device and simulator apart', () async {
      // The primary path cannot: `target_os` is `tvos` and the architecture is
      // arm64 for both, and the protocol has no tvOS sub-config to carry the
      // difference, so a device build and a simulator build hand a hook
      // byte-identical input. The fallback is the one path where it survives,
      // through the SDK root, and that is worth holding down — it is a live
      // property that could regress without anything else noticing.
      Future<Object?> sdkFor(String root) async {
        final runner = _RecordingBuildRunner(failuresBeforeSuccess: 1);
        await TvosBuildHooks(buildRunner: runner).build(buildEnv(sdkRoot: root));
        final code =
            (runner.inputs.last.config.json['extensions']! as Map)['code_assets']! as Map;
        return (code['ios']! as Map)['target_sdk'];
      }

      expect(await sdkFor('/sdk/AppleTVOS.sdk'), 'iphoneos');
      expect(await sdkFor('/sdk/iPhoneSimulator.sdk'), 'iphonesimulator');
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
      Xcode: () => _FakeXcode(),
    });

    testUsingContext('writes the result where CopyFlutterBundle reads it', () async {
      final runner = _RecordingBuildRunner();
      final Environment env = buildEnv();

      await TvosBuildHooks(buildRunner: runner).build(env);

      expect(env.buildDir.childFile(LinkHooks.resultFilename).existsSync(), isTrue);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
    });

    testUsingContext('falls back without an SDK root on the environment', () async {
      // A resident session's Environment carries `kTargetFile` and `kBuildMode`
      // and nothing else, so requiring `kSdkRoot` meant `run` threw
      // `MissingDefineException` the moment the fallback fired — not a
      // `ToolExit`, uncaught, and worded as a missing define rather than as a
      // package that could not be told an OS name. The fallback has to be able
      // to derive one.
      final runner = _RecordingBuildRunner(failuresBeforeSuccess: 1);

      await TvosBuildHooks(buildRunner: runner).build(buildEnv(sdkRoot: null));

      expect(runner.inputs, hasLength(2), reason: 'the pass was not retried');
      final code = (runner.inputs.last.config.json['extensions']! as Map)['code_assets']! as Map;
      expect(code['target_os'], 'ios');
      expect(
        code['ios'],
        isNotNull,
        reason: 'the derived config still has to be a faithful iOS input',
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
      Xcode: () => _FakeXcode(),
    });

    testUsingContext('the resident runner drives the same pass', () async {
      // TvosHookRunner had no test at all, which is how the crash above reached
      // review: nothing exercised the one path that differs from a build.
      final runner = _RecordingBuildRunner(failuresBeforeSuccess: 1);

      final FlutterHookResult result = await TvosHookRunner(buildRunner: runner).runHooks(
        targetPlatform: TargetPlatform.ios,
        environment: buildEnv(sdkRoot: null),
      );

      expect(runner.inputs, hasLength(2));
      final first = (runner.inputs.first.config.json['extensions']! as Map)['code_assets']! as Map;
      expect(first['target_os'], 'tvos', reason: 'a reload must name what a build names');
      expect(result.dataAssets, isEmpty);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
      Xcode: () => _FakeXcode(),
    });

    testUsingContext('explains itself when a hook cannot build', () async {
      final runner = _RecordingBuildRunner(alwaysFails: true);

      await expectLater(
        TvosBuildHooks(buildRunner: runner).build(buildEnv()),
        throwsToolExit(
          message: 'both as tvOS and as the iOS family',
        ),
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
      FeatureFlags: () => TestFeatureFlags(isNativeAssetsEnabled: true, isDartDataAssetsEnabled: true),
    });
  });
}
