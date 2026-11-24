// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show json;

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:flutter_tools/src/asset.dart' show FlutterHookResult;
import 'package:flutter_tools/src/base/common.dart' show throwToolExit;
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart' show Logger;
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart' hide BuildResult;
import 'package:flutter_tools/src/build_system/depfile.dart';
import 'package:flutter_tools/src/build_system/exceptions.dart' show MissingDefineException;
import 'package:flutter_tools/src/build_system/targets/native_assets.dart'
    show LinkHooks, createFlutterNativeAssetsBuildRunner;
import 'package:flutter_tools/src/features.dart' show featureFlags;
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/hook_runner.dart' show FlutterHookRunner;
import 'package:flutter_tools/src/isolated/native_assets/dart_hook_result.dart';
import 'package:flutter_tools/src/isolated/native_assets/ios/native_assets.dart'
    show getIOSSdk, targetIOSVersion;
import 'package:flutter_tools/src/isolated/native_assets/macos/native_assets_host.dart'
    show cCompilerConfigMacOS;
import 'package:flutter_tools/src/isolated/native_assets/native_assets.dart'
    show FlutterCodeAsset, FlutterNativeAssetsBuildRunner;
import 'package:hooks/hooks.dart'
    show
        BuildInput,
        BuildInputBuilder,
        BuildOutput,
        EncodedAsset,
        LinkInput,
        LinkInputBuilder,
        LinkOutput,
        ProtocolExtension,
        ValidationErrors;
import 'package:hooks_runner/hooks_runner.dart' show BuildResult;
import 'package:logging/logging.dart' as logging;
import 'package:meta/meta.dart' show visibleForTesting;

/// tvOS's name in the Dart hooks protocol.
///
/// The protocol's built-in operating systems are the ones `dart:ffi` can name,
/// and tvOS is not among them. Up to Flutter 3.47 the `package:code_assets`
/// the tool pinned (1.x) could not name any other: `OS.fromString('tvos')`
/// threw, so the name was written onto the input JSON by hand. From 3.50 the
/// tool pins 2.x, which supports custom target operating systems, and
/// `OS.fromString('tvos')` is an ordinary [OS].
///
/// On the wire nothing changed: `target_os` is a plain string on both sides of
/// the protocol. A hook resolving code_assets 2.x reads it back as an [OS]; one
/// resolving 1.x — which an app is free to do, its dependencies being resolved
/// separately from the tool's — throws on it when it reads it through
/// `config.code`, which is what [runTvosHooks]' iOS-family retry is for.
///
/// That distinction is the point. tvOS is an Apple platform and a close
/// relative of iOS, but it is not iOS: different engine, different screen,
/// different SDK, a different set of things a package can do. A hook told
/// `ios` cannot tell the difference and has no way to ask; a hook told
/// `tvos` can.
///
/// What a hook still cannot be told is device versus simulator. The typed side
/// of the protocol carries that in a per-OS sub-config — `IOSCodeConfig` has
/// `targetSdk`, and there is an `AndroidCodeConfig` and a `MacOSCodeConfig` —
/// and there is no tvOS one to carry it in. Naming the simulator as a separate
/// OS would invent vocabulary no hook reads, and the architecture is arm64
/// either way, so the two are indistinguishable here.
///
/// A hook that ships *source* is unaffected; one that precompiles per-platform
/// binaries is not. A Metal library built against `appletvos` and one built
/// against `appletvsimulator` carry different target triples, and Metal
/// validates that when a pipeline is created rather than degrading, so whichever
/// such a hook produced first would serve both. The iOS-family fallback keeps
/// the distinction — `targetSdk` comes from the SDK root — which leaves the
/// degraded path better off in this one respect than the accurate one.
///
/// For a code asset the boundary is sharper. A native library is linked for
/// one platform — `TVOS` or `TVOSSIMULATOR` in its `LC_BUILD_VERSION` — and
/// dyld refuses the other, so even a hook that compiles from source has to
/// pick, and a device build and a simulator build share whichever library the
/// hooks cache produced first. That is not papered over: the install step
/// reads the platform out of every library and fails the build on a mismatch,
/// naming the library, rather than shipping one that cannot load. See
/// `installTvosCodeAssets`.
const String tvOSName = 'tvos';

/// The architecture tvOS builds target.
///
/// Apple TV is arm64, and so is the simulator on every Mac this toolchain
/// supports, so there is one value here rather than a list.
///
/// Which also means the architecture cannot separate the two, and neither can
/// anything else on this path: a device build and a simulator build produce
/// byte-identical hook inputs, and therefore one `hooks_runner` cache entry
/// serving both. See [tvOSName] for why there is nowhere to put the
/// distinction.
const Architecture tvOSArchitecture = Architecture.arm64;

/// The code-asset half of a tvOS hook input.
///
/// This wraps `CodeAssetExtension` rather than being one. The config is built
/// by the real thing — which owns the layout, the C compiler block, and
/// everything else — with [tvOSName] as its target OS; the wrapper exists to
/// leave its validation out.
///
/// The `iOS` sub-config is deliberately not supplied. It describes an iPhone
/// SDK and a deployment target that no tvOS hook should be reading, and
/// leaving it out keeps the input from claiming something untrue alongside a
/// target OS that is true.
///
/// Everything else is forwarded too: input and output validation, the
/// application-wide checks (one asset id or library file name per app), and
/// [outputFiles], which hooks_runner hashes to tell whether a hook has to run
/// again. The one thing the protocol's checks cannot judge is a tvOS library
/// itself: its Mach-O validator recognizes only `ios` and `macos`, and nothing
/// in the input says device or simulator, which decides whether a library
/// loads. For every tvOS library it therefore warns that it could not
/// validate it, and that warning is dropped here (see [setupLogger]); the
/// libraries are checked where the SDK is known instead, when they are
/// installed — see `installTvosCodeAssets`.
///
/// The iOS-family retry is the exception: its code assets are discarded, so it
/// does not forward the output checks. See [TvosRetryCodeAssetExtension].
final class TvosCodeAssetExtension extends ProtocolExtension {
  TvosCodeAssetExtension({required CCompilerConfig? cCompiler})
    : _codeAssets = CodeAssetExtension(
        targetArchitecture: tvOSArchitecture,
        targetOS: OS.fromString(tvOSName),
        linkModePreference: LinkModePreference.dynamic,
        // Best effort: a hook that knows about tvOS can use the host
        // toolchain, and one that does not will not get as far as reading it.
        cCompiler: cCompiler,
      );

  final CodeAssetExtension _codeAssets;

  /// The wrapped extension, for tests.
  @visibleForTesting
  CodeAssetExtension get codeAssets => _codeAssets;

  /// Forwarded, because the runner only calls this on the wrapper: the
  /// protocol promises an extension its logger before any other call, and
  /// the wrapped one is called through here.
  ///
  /// Through a filter: code_assets' library check cannot recognize a tvOS
  /// library and says so for every one, as a warning that reads like a defect
  /// in the package. It is not one, and the install step checks the library
  /// properly, so that warning goes to the runner's logger at fine level and
  /// everything else is passed on as it is.
  @override
  void setupLogger(logging.Logger logger) {
    super.setupLogger(logger);
    _codeAssets.setupLogger(filteringUnrecognizedLibraryWarnings(logger));
  }

  @override
  void setupBuildInput(BuildInputBuilder input) => _codeAssets.setupBuildInput(input);

  @override
  void setupLinkInput(LinkInputBuilder input) => _codeAssets.setupLinkInput(input);

  @override
  Future<ValidationErrors> validateBuildInput(BuildInput input) =>
      _codeAssets.validateBuildInput(input);

  @override
  Future<ValidationErrors> validateLinkInput(LinkInput input) =>
      _codeAssets.validateLinkInput(input);

  @override
  Future<ValidationErrors> validateBuildOutput(BuildInput input, BuildOutput output) =>
      _codeAssets.validateBuildOutput(input, output);

  @override
  Future<ValidationErrors> validateLinkOutput(LinkInput input, LinkOutput output) =>
      _codeAssets.validateLinkOutput(input, output);

  @override
  Future<ValidationErrors> validateApplicationAssets(List<EncodedAsset> assets) =>
      _codeAssets.validateApplicationAssets(assets);

  @override
  Iterable<Uri> outputFiles(List<EncodedAsset> assets) => _codeAssets.outputFiles(assets);
}

/// The text code_assets' library check warns with when no validator
/// recognizes a library for its target, which is every tvOS library.
const String _unrecognizedLibraryWarning = 'No registered validator recognized the file and target.';

/// A logger that passes every record on to [target], except code_assets'
/// "could not validate" warning for a library no validator recognizes, which
/// it passes on at [logging.Level.FINE].
@visibleForTesting
logging.Logger filteringUnrecognizedLibraryWarnings(logging.Logger target) {
  final logger = logging.Logger.detached('${target.name}.tvos_code_assets')
    ..level = logging.Level.ALL;
  logger.onRecord.listen((logging.LogRecord record) {
    final bool unrecognized =
        record.level == logging.Level.WARNING &&
        record.message.contains(_unrecognizedLibraryWarning);
    target.log(
      unrecognized ? logging.Level.FINE : record.level,
      record.message,
      record.error,
      record.stackTrace,
    );
  });
  return logger;
}

/// The iOS-family code config the fallback needs.
///
/// A hook told `ios` goes on to read this — `objective_c` reaches for
/// `code.iOS.targetSdk` — so the fallback has to be a faithful iOS input, not
/// just an iOS name.
///
/// [kSdkRoot] is only on the environment the one-shot build assembles; a
/// resident session's carries `kTargetFile` and `kBuildMode` and nothing else.
/// Requiring the define meant `run` threw `MissingDefineException` the moment
/// the fallback fired, which is not a `ToolExit` and reads as a broken build
/// rather than as a package that could not be told an OS name. So it is derived
/// when absent, from the same call the builder makes.
///
/// Which SDK that resolves to barely matters: nothing produced under this
/// config is installed, and only a hook reading `code.iOS.targetSdk` sees it at
/// all. A resident session cannot tell device from simulator, so it says
/// device; the alternative is refusing to build.
Future<IOSCodeConfig> _iosFamilyConfig(Environment environment) async {
  final String sdkRoot =
      environment.defines[kSdkRoot] ??
      await globals.xcode!.sdkLocation(EnvironmentType.physical);
  return IOSCodeConfig(
    targetVersion: targetIOSVersion,
    targetSdk: getIOSSdk(tvosEnvironmentTypeOf(sdkRoot, environment.fileSystem)),
  );
}

/// Device or simulator, read from an SDK path.
///
/// Upstream's `environmentTypeFromSdkroot` cannot be used here: it `assert`s
/// rather than returning null when the basename does not name an *iPhone* SDK,
/// so an `AppleTVOS.sdk` — the natural thing for someone to point [kSdkRoot] at
/// — crashes the tool on an assertion inside a retry, which reads as the retry
/// being broken rather than as an SDK it did not expect. Asking only about the
/// suffix answers the same question for every Apple SDK, this platform's
/// included.
EnvironmentType tvosEnvironmentTypeOf(String sdkRoot, FileSystem fileSystem) {
  final String name = fileSystem.path.basename(sdkRoot).toLowerCase();
  return name.contains('simulator') ? EnvironmentType.simulator : EnvironmentType.physical;
}

/// Runs every package's Dart build hook for a tvOS app, and returns the
/// data assets they produced, and the code assets of a pass that named tvOS.
///
/// This is tvOS driving the hooks protocol on its own behalf, rather than
/// borrowing the iOS pipeline's driver. flutter_tools translates its own
/// `TargetPlatform`s into protocol targets through a closed set that has no
/// tvOS in it, so going through that path means being announced as `ios`.
/// Assembling the protocol extensions here instead means a hook is told
/// [tvOSName], which is the truth and is what a package needs in order to
/// pick the right output for this platform.
///
/// Code assets are requested for two reasons. The protocol keeps the target OS
/// *inside* the code-asset config, so a hook that is not asked for code assets
/// is not told what it is building for at all; and a package that ships a
/// `dart:ffi` library through its hook needs that library in the app, which
/// `TvosInstallCodeAssets` does with what this returns.
///
/// Only a pass that told the hooks `tvos` contributes code assets — see
/// [keepsCodeAssets]. Whether the name lands is a property of the app's
/// packages, so it is tried and not predicted; the fallback is inline below.
Future<DartHooksResult> runTvosHooks({
  required FlutterNativeAssetsBuildRunner buildRunner,
  required Environment environment,
}) async {
  final buildStart = DateTime.now();

  final List<String> packagesWithHooks = await buildRunner.packagesWithNativeAssets();
  if (packagesWithHooks.isEmpty) {
    environment.logger.printTrace('No packages with Dart build hooks. Skipping.');
    return DartHooksResult.empty();
  }

  // The pass stays behind the data-assets flag even though it now also
  // installs code assets. Stock Flutter runs code-asset hooks whenever native
  // assets are on, which they are by default; doing the same here would start
  // running every hook in every tvOS app on upgrade — `objective_c`'s among
  // them, which most plugin graphs inherit — and a hook can fail a build that
  // passed before. Opting in stays a deliberate step, as it has been since the
  // pass was introduced.
  //
  // The feature is off by default. `dartDataAssets` declares no
  // `enabledByDefault` on any channel, while `nativeAssets` declares it on all
  // of them, so a guard reading both with `&&` can never fire and this used to
  // run the hooks and silently collect nothing. Say what is off, name the
  // packages it affects and the one command that turns it on.
  if (!featureFlags.isDartDataAssetsEnabled) {
    environment.logger.printWarning(
      'Dart data assets are disabled, so the build hooks in '
      '${packagesWithHooks.join(', ')} were not run.\n'
      'A package that generates assets for the platform it is built for — '
      'shader bundles and the like — will ship whatever its generated '
      'directory already held, which may be output from a build for another '
      'platform, or nothing; and a native library a package builds for '
      '`dart:ffi` is not built or installed, so calls into it fail.\n'
      'Turn them on with `flutter config --enable-dart-data-assets`.',
    );
    return DartHooksResult.empty();
  }

  final CCompilerConfig? cCompiler = await cCompilerConfigMacOS(throwIfNotFound: false);
  final dataAssets = DataAssetsExtension();

  // Ask as tvOS first. Whether that works is a property of the app's
  // packages, not something this build can look up: the name is read on the
  // *hook's* side, by the `package:code_assets` the app resolved, and before
  // 2.0 that library's set of operating systems was closed — `config.code`
  // parses `target_os` eagerly and throws on a name it does not know. A hook as
  // ordinary as `objective_c`'s dies on its first line, not with "tvOS is
  // unsupported", which it would handle, but before it can look.
  //
  // A package can be fine on an old code_assets by reading the name off the
  // config JSON, which is a plain string on both sides — flutter_scene does
  // exactly that — so the resolved version does not answer the question either.
  // Asking and seeing is the only thing that does.
  BuildResult? result = await buildRunner.build(
    extensions: <ProtocolExtension>[
      TvosCodeAssetExtension(cCompiler: cCompiler),
      dataAssets,
    ],
    // No link phase: a hook puts its code assets straight into the app. Stock
    // runs link hooks for AOT builds; the tvOS pass has never run them, so an
    // asset a build hook routes to a link hook instead of the app is not
    // installed.
    linkingEnabled: false,
  );

  final fromIOSFamilyRetry = result == null;
  if (result == null) {
    // Fall back to what builds for this platform said before it could name
    // itself. The hooks just printed why they stopped, so say what happens now:
    // an unexplained retry after a stack trace reads as a broken build.
    //
    // What is deliberately *not* said is why it failed. `build` collapses every
    // failure — a missing toolchain, a compile error, a fetch that timed out, a
    // hook that deliberately reports tvOS as unsupported, and one that choked on
    // the name — into a null, so naming the last of those would be a diagnosis
    // nothing here established. The hooks' own error is on screen directly
    // above; this must not talk over it.
    environment.logger.printStatus(
      'A build hook failed while building for tvOS by name. The reason is above.\n'
      'Retrying as the iOS family, which is what tvOS builds asked for before '
      'this platform could introduce itself. That is a guess, and it helps only '
      'if the hook stopped on the target OS rather than on something else: '
      '`package:code_assets` throws on an OS it does not know until 2.0.0, so a '
      'hook reading one through its typed accessor cannot see `tvos` at all.',
    );
    result = await buildRunner.build(
      extensions: <ProtocolExtension>[
        TvosRetryCodeAssetExtension(
          CodeAssetExtension(
            targetArchitecture: tvOSArchitecture,
            targetOS: OS.iOS,
            linkModePreference: LinkModePreference.dynamic,
            cCompiler: cCompiler,
            iOS: await _iosFamilyConfig(environment),
          ),
        ),
        dataAssets,
      ],
      linkingEnabled: false,
    );
  }
  if (result == null) {
    _throwHookFailed(packagesWithHooks);
  }

  final encodedCodeAssets = <EncodedAsset>[
    for (final EncodedAsset asset in result.encodedAssets)
      if (asset.isCodeAsset) asset,
  ];
  final bool keep = keepsCodeAssets(
    fromIOSFamilyRetry: fromIOSFamilyRetry,
    nativeAssetsEnabled: featureFlags.isNativeAssetsEnabled,
  );
  if (encodedCodeAssets.isNotEmpty && !keep) {
    // A warning, not a trace: these are libraries the app's Dart code may call,
    // and a call into one that is not installed fails at runtime. Otherwise
    // "no code assets existed" and "code assets existed and were discarded"
    // also look identical from the outside, including in a bug report.
    final String ids = <String>[
      for (final EncodedAsset asset in encodedCodeAssets) CodeAsset.fromEncoded(asset).id,
    ].join(', ');
    environment.logger.printWarning(
      fromIOSFamilyRetry
          ? 'Discarding ${encodedCodeAssets.length} code asset(s) from the '
                'iOS-family retry, which built them for iOS: $ids. The build '
                'for tvOS by name failed, so this app has no native library '
                'from these packages, and calls into one fail at runtime.'
          : 'Discarding ${encodedCodeAssets.length} code asset(s) because '
                'native assets are disabled: $ids. Turn them on with '
                '`flutter config --enable-native-assets`.',
    );
  }

  return DartHooksResult(
    buildStart: buildStart,
    buildEnd: DateTime.now(),
    codeAssets: <FlutterCodeAsset>[
      if (keep)
        for (final EncodedAsset asset in encodedCodeAssets)
          FlutterCodeAsset(
            codeAsset: CodeAsset.fromEncoded(asset),
            // What the hook was told, not what the engine looks the asset up
            // under; the manifest translates. See `tvosNativeAssetsManifestOS`.
            os: OS.fromString(tvOSName),
            architecture: tvOSArchitecture,
          ),
    ],
    dataAssets: <DataAsset>[
      for (final EncodedAsset asset in result.encodedAssets)
        if (asset.isDataAsset) DataAsset.fromEncoded(asset),
    ],
    dependencies: result.dependencies,
  );
}

/// The `buildKey` of the tvOS hook targets: a schema plus the feature flags
/// their output depends on. A stamp from a build with another key, or with
/// none (an earlier CLI), makes the build system run the target again.
String tvosHooksBuildKey({
  required String schema,
  required bool dartDataAssets,
  required bool nativeAssets,
}) => '$schema;dart-data-assets=$dartDataAssets;native-assets=$nativeAssets';

/// Whether the code assets of a hook pass are installed into the app.
///
/// Only those of the pass that told the hooks `tvos`. The iOS-family retry
/// tells them `ios` with an iPhone SDK, and a library built for that is an
/// iPhone library: it does not load on tvOS, and a hook that could not read
/// `tvos` has given no sign that it can build for it. That pass exists to keep
/// data assets flowing, so its code assets stay discarded, as they were before
/// tvOS installed any.
///
/// And only with native assets on, which is stock's own condition for asking
/// hooks for code assets at all (`--no-enable-native-assets` turns it off).
@visibleForTesting
bool keepsCodeAssets({required bool fromIOSFamilyRetry, required bool nativeAssetsEnabled}) =>
    !fromIOSFamilyRetry && nativeAssetsEnabled;

/// Explains a hook failure in terms of what was actually asked for.
///
/// The generic message reads as though the app requested a native build it
/// never requested, which sends people looking in the wrong place. Say why the
/// hooks ran, and what the ways out are, because the answer is a judgement
/// about a dependency rather than something to fix in this build.
Never _throwHookFailed(List<String> packagesWithHooks) {
  throwToolExit(
    'A Dart build hook failed while building for tvOS, both as tvOS and '
    'as the iOS family.\n'
    '\n'
    'Packages with build hooks in this app: ${packagesWithHooks.join(', ')}.\n'
    '\n'
    'The hooks run because Dart data assets are enabled: they generate\n'
    'per-platform data — shader bundles and the like — and build the native\n'
    'libraries a package ships for `dart:ffi`. They were first told they are\n'
    'building for tvOS, then, as a fallback, for the iOS family.\n'
    '\n'
    'The second attempt built exactly what an iOS build of this app builds, so\n'
    'an iOS build is the quickest way to tell a missing toolchain (a Rust hook\n'
    'wants cargo, a C hook wants its compiler) from something specific to this\n'
    'platform. Either install the toolchain the hook wants, or drop the\n'
    'dependency if its hook cannot build for tvOS.',
  );
}

/// Runs the Dart build hooks as part of the tvOS build graph.
///
/// The tvOS pipeline skips upstream's native-asset targets: they translate the
/// build's target platform into the hooks protocol through a closed set with
/// no tvOS in it, so they would announce the build as `ios`. This target runs
/// the hooks through [runTvosHooks] instead, and `TvosInstallCodeAssets` takes
/// the place of upstream's `InstallCodeAssets`.
///
/// Data assets were the first reason: produced on the host by ordinary Dart,
/// which is how a package compiles its GPU shader bundles for the platform it
/// is going to run on. Skipping them wholesale meant such a package silently
/// shipped whatever its generated directory happened to contain — assets left
/// behind by a macOS or simulator build of the same tree, or nothing at all.
class TvosBuildHooks extends Target {
  const TvosBuildHooks({@visibleForTesting FlutterNativeAssetsBuildRunner? buildRunner})
    : _buildRunner = buildRunner;

  /// Injected by tests, which have no hooks to run and want to drive the
  /// result. Mirrors upstream `BuildHooks`' seam.
  final FlutterNativeAssetsBuildRunner? _buildRunner;

  @override
  String get name => 'tvos_build_hooks';

  /// What the result depends on besides its input files: the two feature
  /// flags, which decide whether hooks run and whether code assets are kept,
  /// and a schema that changes when this target's output does for the same
  /// inputs. Without it, turning a flag on or off — or upgrading from a CLI
  /// that wrote no code assets — left the last result in place until `clean`.
  @override
  String get buildKey => tvosHooksBuildKey(
    schema: _schema,
    dartDataAssets: featureFlags.isDartDataAssetsEnabled,
    nativeAssets: featureFlags.isNativeAssetsEnabled,
  );

  /// Bumped when what this target writes changes for the same hooks. `2`: code
  /// assets of the tvOS pass are kept (1.12.2 and earlier wrote none).
  static const _schema = 'tvos-build-hooks-2';

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  List<Source> get inputs => const <Source>[
    Source.pattern('{WORKSPACE_DIR}/.dart_tool/package_config.json'),
  ];

  /// Written where [LinkHooks] would have written it, because that is where
  /// `CopyFlutterBundle` and `TvosInstallCodeAssets` look for the hooks'
  /// result. There is no link phase here (see [runTvosHooks]), so the build
  /// result is the whole result.
  @override
  List<Source> get outputs => const <Source>[
    Source.pattern('{BUILD_DIR}/${LinkHooks.resultFilename}'),
  ];

  @override
  List<String> get depfiles => const <String>[depFilename];

  static const depFilename = 'tvos_hooks.d';

  @override
  Future<void> build(Environment environment) async {
    final FileSystem fileSystem = environment.fileSystem;

    if (environment.defines[kBuildMode] == null) {
      throw MissingDefineException(kBuildMode, name);
    }

    final FlutterNativeAssetsBuildRunner buildRunner =
        _buildRunner ?? await createFlutterNativeAssetsBuildRunner(environment);

    final DartHooksResult buildResult = await runTvosHooks(
      buildRunner: buildRunner,
      environment: environment,
    );

    final File resultFile = environment.buildDir.childFile(LinkHooks.resultFilename);
    if (!resultFile.parent.existsSync()) {
      resultFile.parent.createSync(recursive: true);
    }
    resultFile.writeAsStringSync(json.encode(buildResult.toJson()));

    final Set<Uri> buildDependencies = buildResult.dependencies.toSet();
    final depfile = Depfile(
      <File>[for (final Uri dependency in buildResult.dependencies) fileSystem.file(dependency)],
      <File>[
        resultFile,
        for (final Uri uri in buildResult.filesToBeBundled)
          if (!buildDependencies.contains(uri)) fileSystem.file(uri),
      ],
    );
    final File outputDepfile = environment.buildDir.childFile(depFilename);
    if (!outputDepfile.parent.existsSync()) {
      outputDepfile.parent.createSync(recursive: true);
    }
    environment.depFileService.writeToFile(depfile, outputDepfile, filterOutputs: true);
  }
}

/// Runs the same hooks during a resident session, so hot reload rebuilds
/// generated assets the way a full build does.
///
/// Upstream's runner exists and `RunCommand` already threads it through to the
/// resident runner, which calls it whenever the asset bundle needs rebuilding —
/// but it reads the implementation out of the context, so a CLI that does not
/// register one skips the call for the whole session, and a package that
/// generates its assets from a hook keeps serving whatever the last full build
/// left behind.
///
/// This registers one that goes through [runTvosHooks], so a reload names
/// the same target OS a build does. Upstream's own implementation would name a
/// different one — it asks for data assets alone, which carries no target OS at
/// all — and a package choosing an output from it would swap in a different
/// one every time the two paths took turns.
class TvosHookRunner implements FlutterHookRunner {
  TvosHookRunner({@visibleForTesting FlutterNativeAssetsBuildRunner? buildRunner})
    : _buildRunner = buildRunner;

  /// Injected by tests. The same seam [TvosBuildHooks] has, and for the same
  /// reason: without it nothing could exercise this path, which is how a crash
  /// on the resident environment's missing [kSdkRoot] reached review.
  final FlutterNativeAssetsBuildRunner? _buildRunner;

  FlutterHookResult? _lastResult;

  @override
  Future<FlutterHookResult> runHooks({
    required TargetPlatform targetPlatform,
    required Environment environment,
    Logger? logger,
  }) async {
    final FlutterHookResult? cached = _lastResult;
    if (cached != null && !cached.hasAnyModifiedFiles(environment.fileSystem)) {
      logger?.printTrace('runTvosHooks() - up-to-date already');
      return cached;
    }
    logger?.printTrace('runTvosHooks() - will perform dart build');

    final DartHooksResult result = await runTvosHooks(
      buildRunner: _buildRunner ?? await createFlutterNativeAssetsBuildRunner(environment),
      environment: environment,
    );
    return _lastResult = result.asFlutterResult;
  }
}

/// The code-asset half of the iOS-family retry in [runTvosHooks].
///
/// The retry tells hooks `ios`, with a faithful iPhone config, so that a
/// package whose hook cannot read `tvos` still produces its data assets. The
/// code assets it gets back are iPhone libraries and are discarded, so they
/// must not be able to fail the build.
///
/// A bare `CodeAssetExtension` lets them. Since code_assets 2.0 its output
/// check reads each bundled library's Mach-O header when the target OS is
/// `ios`, and rejects a universal library (arm64 and x86_64 together, which
/// cargokit-style hooks ship), an arm64e one, or one built for another
/// architecture than [tvOSArchitecture]. hooks_runner turns any such error into
/// a failed hook, so a package whose data assets built on 1.11.5 failed the
/// build from 1.12.0 to 1.12.2, over a library nothing was going to install.
///
/// Forwarded, because they shape what the hooks see or when they run:
///
///  * the logger and the input setup, so the hooks get exactly the input a
///    bare extension gives them;
///  * the input checks, which judge the config this tool writes and not
///    anything a hook produced;
///  * [outputFiles], which hooks_runner hashes to decide whether a hook has to
///    run again. A library rebuilt in place still invalidates the hook's cached
///    output, data assets included.
///
/// Not forwarded: the output checks (file present, link mode, asset id, the
/// library's architecture) and the application-wide ones (one id and one
/// library file name per app), all of which judge assets this pass throws
/// away. In their place is one check, that every code asset can be read at
/// all: [outputFiles] and the discard report in [runTvosHooks] parse every
/// one, and an asset that does not parse is a hook breaking the protocol,
/// which should fail that hook by name rather than crash the runner. Data
/// assets are checked by `DataAssetsExtension`, which this does not touch.
final class TvosRetryCodeAssetExtension extends ProtocolExtension {
  TvosRetryCodeAssetExtension(this._codeAssets);

  final CodeAssetExtension _codeAssets;

  /// The wrapped extension, for tests.
  @visibleForTesting
  CodeAssetExtension get codeAssets => _codeAssets;

  @override
  void setupLogger(logging.Logger logger) {
    super.setupLogger(logger);
    _codeAssets.setupLogger(logger);
  }

  @override
  void setupBuildInput(BuildInputBuilder input) => _codeAssets.setupBuildInput(input);

  @override
  void setupLinkInput(LinkInputBuilder input) => _codeAssets.setupLinkInput(input);

  @override
  Future<ValidationErrors> validateBuildInput(BuildInput input) =>
      _codeAssets.validateBuildInput(input);

  @override
  Future<ValidationErrors> validateLinkInput(LinkInput input) =>
      _codeAssets.validateLinkInput(input);

  @override
  Future<ValidationErrors> validateBuildOutput(BuildInput input, BuildOutput output) async =>
      _unreadableCodeAssets(<EncodedAsset>[
        ...output.assets.encodedAssets,
        ...output.assets.encodedAssetsForBuild,
        for (final List<EncodedAsset> assets in output.assets.encodedAssetsForLinking.values)
          ...assets,
      ]);

  @override
  Future<ValidationErrors> validateLinkOutput(LinkInput input, LinkOutput output) async =>
      _unreadableCodeAssets(<EncodedAsset>[
        ...output.assets.encodedAssets,
        for (final List<EncodedAsset> assets in output.assets.encodedAssetsForLink.values)
          ...assets,
      ]);

  @override
  Iterable<Uri> outputFiles(List<EncodedAsset> assets) => _codeAssets.outputFiles(assets);

  static ValidationErrors _unreadableCodeAssets(List<EncodedAsset> assets) => <String>[
    for (final EncodedAsset asset in assets)
      if (asset.isCodeAsset)
        if (_readError(asset) case final String error) error,
  ];

  static String? _readError(EncodedAsset asset) {
    try {
      CodeAsset.fromEncoded(asset);
      return null;
    } on FormatException catch (error) {
      return 'A code asset cannot be read: ${error.message} ($asset)';
    }
  }
}
