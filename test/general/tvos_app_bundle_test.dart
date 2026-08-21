// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression tests for the TestFlight/App-Store packaging issues reported in
// https://github.com/fluttertv/flutter-tvos/issues/18:
//   1. App.framework was not embedded in archive builds (crash on launch).
//   2. App.framework's Info.plist was missing keys App Store validation needs.
//   3. flutter_assets were duplicated one level deep on rebuilds
//      (flutter_assets/assets/assets/...).

import 'dart:io' show Process, ProcessResult;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:flutter_tvos/build_targets/application.dart';

import '../src/common.dart';

void main() {
  // --- Issue #3: flutter_assets duplication -------------------------------
  // The guard reads FLUTTER_STAGED_BUILD_MODE from the environment Xcode builds
  // out of the target configuration's base xcconfig. runGuard injects that
  // variable directly, so every guard test above stays green even if the chain
  // that delivers it in a real build is broken. These assert the chain itself:
  //
  //   Generated.xcconfig
  //     -> #include'd by Flutter/Debug.xcconfig and Flutter/Release.xcconfig
  //       -> baseConfigurationReference on each configuration of the Runner target
  //
  // Drop the include, or add a configuration with no base reference, and the
  // phase sees an unset marker: a hard failure for release, a warning for debug.
  group('xcconfig chain', () {
    test('each mode xcconfig includes Generated.xcconfig', () {
      for (final String mode in <String>['debug', 'release']) {
        expect(NativeTvosBundle.buildModeXcconfig(mode),
            contains('#include "Generated.xcconfig"'),
            reason: '$mode xcconfig must pull in the staged-mode marker');
      }
    });

    for (final String relativePath in <String>[
      'templates/app/swift/tvos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl',
      'packages/flutter_tvos/example/tvos/Runner.xcodeproj/project.pbxproj',
    ]) {
      test('$relativePath wires every Runner configuration to an xcconfig', () {
        final String pbxproj =
            const LocalFileSystem().file(relativePath).readAsStringSync();

        // The Runner *target*'s configuration list, not the project's: only the
        // target's configurations carry a base xcconfig.
        final Match? listMatch = RegExp(
          r'Build configuration list for PBXNativeTarget "Runner" \*/ = \{'
          r'.*?buildConfigurations = \((.*?)\);',
          dotAll: true,
        ).firstMatch(pbxproj);
        expect(listMatch, isNotNull,
            reason: 'expected a configuration list for the Runner target');

        final List<String> configIds = RegExp(r'([0-9A-F]{24})')
            .allMatches(listMatch!.group(1)!)
            .map((Match m) => m.group(1)!)
            .toList();
        expect(configIds, hasLength(greaterThanOrEqualTo(3)),
            reason: 'expected Debug, Release and Profile');

        for (final String id in configIds) {
          final Match? config = RegExp(
            '$id /\\* (\\w+) \\*/ = \\{(.*?)\\n\t\t\\};',
            dotAll: true,
          ).firstMatch(pbxproj);
          expect(config, isNotNull, reason: 'no XCBuildConfiguration for $id');
          final String name = config!.group(1)!;
          final String body = config.group(2)!;

          final Match? base =
              RegExp(r'baseConfigurationReference = ([0-9A-F]{24})').firstMatch(body);
          expect(base, isNotNull,
              reason: 'the $name configuration has no baseConfigurationReference, '
                  'so Generated.xcconfig never reaches the build-mode guard');

          // ...and it must resolve to one of our xcconfigs, not any file.
          final Match? fileRef = RegExp(
            '${base!.group(1)} /\\* [^*]*\\*/ = \\{isa = PBXFileReference;[^\n]*?path = ([^;]+);',
          ).firstMatch(pbxproj);
          expect(fileRef, isNotNull,
              reason: 'the $name base reference resolves to no file');
          expect(fileRef!.group(1), anyOf('Flutter/Debug.xcconfig', 'Flutter/Release.xcconfig'),
              reason: 'the $name configuration must inherit from a Flutter xcconfig');
        }
      });
    }
  });

  group('stripJitPayload', () {
    late FileSystem fs;
    setUp(() => fs = MemoryFileSystem.test());

    // build/tvos/ is shared across modes and nothing there removes the kernel
    // blob, so an AOT build run after any debug build mirrored a 40+ MB debug
    // kernel into the staged assets and shipped it inside the release app.
    test('removes a kernel blob left by an earlier debug build', () {
      final Directory staged = fs.directory('/app/tvos/Flutter/flutter_assets')
        ..createSync(recursive: true);
      staged.childFile('kernel_blob.bin').writeAsStringSync('jit');
      staged.childFile('AssetManifest.bin').writeAsStringSync('assets');

      expect(NativeTvosBundle.stripJitPayload(stagedAssets: staged), isTrue);
      expect(staged.childFile('kernel_blob.bin').existsSync(), isFalse);
      expect(staged.childFile('AssetManifest.bin').existsSync(), isTrue,
          reason: 'only the JIT payload is removed');
    });

    test('reports nothing removed when no kernel blob is staged', () {
      final Directory staged = fs.directory('/app/tvos/Flutter/flutter_assets')
        ..createSync(recursive: true);
      expect(NativeTvosBundle.stripJitPayload(stagedAssets: staged), isFalse);
    });
  });

  group('copyFlutterAssetsTree', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem.test();
    });

    void seedSource() {
      fs.file('/build/tvos/kernel_blob.bin').createSync(recursive: true);
      fs.file('/build/tvos/AssetManifest.json').createSync(recursive: true);
      fs.file('/build/tvos/assets/logo.png')
        ..createSync(recursive: true)
        ..writeAsStringSync('logo');
      fs.file('/build/tvos/assets/nested/data.bin')
        ..createSync(recursive: true)
        ..writeAsStringSync('data');
    }

    test('mirrors the source tree without nesting on the first copy', () {
      seedSource();
      NativeTvosBundle.copyFlutterAssetsTree(
        source: fs.directory('/build/tvos'),
        target: fs.directory('/tvos/Flutter/flutter_assets'),
      );

      expect(fs.file('/tvos/Flutter/flutter_assets/kernel_blob.bin').existsSync(), isTrue);
      expect(fs.file('/tvos/Flutter/flutter_assets/assets/logo.png').existsSync(), isTrue);
      expect(fs.file('/tvos/Flutter/flutter_assets/assets/nested/data.bin').existsSync(), isTrue);
    });

    test('does NOT nest assets one level deep on a second copy (issue #18)', () {
      seedSource();
      final Directory source = fs.directory('/build/tvos');
      final Directory target = fs.directory('/tvos/Flutter/flutter_assets');

      NativeTvosBundle.copyFlutterAssetsTree(source: source, target: target);
      // A second build used to produce flutter_assets/assets/assets/... because
      // `cp -R src/assets target/assets` nested into the existing directory.
      NativeTvosBundle.copyFlutterAssetsTree(source: source, target: target);

      expect(
        fs.directory('/tvos/Flutter/flutter_assets/assets/assets').existsSync(),
        isFalse,
        reason: 'assets must not be nested inside themselves on rebuild',
      );
      expect(fs.file('/tvos/Flutter/flutter_assets/assets/logo.png').existsSync(), isTrue);
    });

    test('wipes stale files so the target exactly mirrors the source', () {
      seedSource();
      final Directory source = fs.directory('/build/tvos');
      final Directory target = fs.directory('/tvos/Flutter/flutter_assets');
      NativeTvosBundle.copyFlutterAssetsTree(source: source, target: target);

      // Simulate an asset removed from the project between builds.
      fs.file('/build/tvos/assets/logo.png').deleteSync();
      NativeTvosBundle.copyFlutterAssetsTree(source: source, target: target);

      expect(
        fs.file('/tvos/Flutter/flutter_assets/assets/logo.png').existsSync(),
        isFalse,
        reason: 'a clean target should not retain assets deleted from the source',
      );
      expect(fs.file('/tvos/Flutter/flutter_assets/assets/nested/data.bin').existsSync(), isTrue);
    });

    test('skips xcodebuild output dirs sitting alongside the assets', () {
      seedSource();
      fs.file('/build/tvos/Release-appletvos/Runner.app/Runner').createSync(recursive: true);
      fs.file('/build/tvos/Debug-appletvsimulator/Runner.app/Runner').createSync(recursive: true);
      fs.file('/build/tvos/Profile-appletvos/Runner.app/Runner').createSync(recursive: true);

      NativeTvosBundle.copyFlutterAssetsTree(
        source: fs.directory('/build/tvos'),
        target: fs.directory('/tvos/Flutter/flutter_assets'),
      );

      expect(
        fs.directory('/tvos/Flutter/flutter_assets/Release-appletvos').existsSync(),
        isFalse,
      );
      expect(
        fs.directory('/tvos/Flutter/flutter_assets/Debug-appletvsimulator').existsSync(),
        isFalse,
      );
      expect(
        fs.directory('/tvos/Flutter/flutter_assets/Profile-appletvos').existsSync(),
        isFalse,
      );
    });

    test('does NOT ship AOT intermediates inside flutter_assets', () {
      // A stale build/tvos/aot/ from an older CLI (or any regression that
      // writes intermediates into outputDir) must never reach the bundle:
      // stray .S/.o files fail App Store validation.
      seedSource();
      fs.file('/build/tvos/aot/snapshot_assembly.S').createSync(recursive: true);
      fs.file('/build/tvos/aot/snapshot_assembly.o').createSync(recursive: true);

      NativeTvosBundle.copyFlutterAssetsTree(
        source: fs.directory('/build/tvos'),
        target: fs.directory('/tvos/Flutter/flutter_assets'),
      );

      expect(
        fs.directory('/tvos/Flutter/flutter_assets/aot').existsSync(),
        isFalse,
        reason: 'AOT intermediates must not ship inside flutter_assets',
      );
    });
  });

  // --- ITMS-90208: App.framework minos must match MinimumOSVersion ---------
  group('tvosVersionMinFlag', () {
    test('device SDK pins the tvOS deployment target', () {
      expect(
        NativeTvosBundle.tvosVersionMinFlag('appletvos'),
        '-mtvos-version-min=15.0',
      );
    });

    test('simulator SDK uses the simulator flag', () {
      expect(
        NativeTvosBundle.tvosVersionMinFlag('appletvsimulator'),
        '-mtvos-simulator-version-min=15.0',
      );
    });
  });

  // Both AOT clang steps must carry the min-version flag, else App.framework's
  // LC_BUILD_VERSION minos is stamped with the SDK version (ITMS-90208). The
  // flag's value is covered above; here we assert it actually reaches the argv.
  group('AOT clang argv carry the min-version flag', () {
    const String flag = '-mtvos-version-min=15.0';

    test('aotAssembleArgs (cc) includes the flag and inputs', () {
      final List<String> args = NativeTvosBundle.aotAssembleArgs(
        versionMinFlag: flag,
        sdkPath: '/sdk',
        assemblyPath: '/a/snapshot_assembly.S',
        objectPath: '/a/snapshot_assembly.o',
      );
      expect(args, containsAllInOrder(<String>['xcrun', 'cc']));
      expect(args, contains(flag));
      expect(args, containsAllInOrder(<String>['-c', '/a/snapshot_assembly.S']));
      expect(args, containsAllInOrder(<String>['-o', '/a/snapshot_assembly.o']));
    });

    test('aotLinkArgs (clang) includes the flag and outputs a dylib', () {
      final List<String> args = NativeTvosBundle.aotLinkArgs(
        versionMinFlag: flag,
        sdkPath: '/sdk',
        objectPath: '/a/snapshot_assembly.o',
        appBinaryPath: '/f/App.framework/App',
      );
      expect(args, containsAllInOrder(<String>['xcrun', 'clang']));
      expect(args, contains(flag));
      expect(args, contains('-dynamiclib'));
      expect(args, containsAllInOrder(<String>['-o', '/f/App.framework/App']));
    });
  });

  // --- Issue #2: App.framework Info.plist completeness --------------------
  group('buildAppFrameworkInfoPlist', () {
    test('includes the keys App Store / TestFlight validation requires', () {
      final String plist = NativeTvosBundle.buildAppFrameworkInfoPlist(
        shortVersion: '2.3.4',
        bundleVersion: '17',
      );

      // CFBundleShortVersionString is mandatory; the old plist omitted it.
      expect(plist, contains('<key>CFBundleShortVersionString</key>'));
      expect(plist, contains('<string>2.3.4</string>'));
      expect(plist, contains('<key>CFBundleVersion</key>'));
      expect(plist, contains('<string>17</string>'));

      // tvOS platform identity — must be AppleTVOS, not iPhoneOS.
      expect(plist, contains('<key>CFBundleSupportedPlatforms</key>'));
      expect(plist, contains('<string>AppleTVOS</string>'));
      expect(plist, contains('<key>DTPlatformName</key>'));
      expect(plist, contains('<string>appletvos</string>'));

      // Required on every embedded framework in the archive.
      expect(plist, contains('<key>MinimumOSVersion</key>'));

      // Apple TV device family.
      expect(plist, contains('<key>UIDeviceFamily</key>'));
      expect(plist, contains('<integer>3</integer>'));

      // Framework identity stays intact.
      expect(plist, contains('<key>CFBundlePackageType</key>'));
      expect(plist, contains('<string>FMWK</string>'));
      expect(plist, contains('<string>io.flutter.flutter.app</string>'));
    });

    test('is well-formed plist xml', () {
      final String plist = NativeTvosBundle.buildAppFrameworkInfoPlist(
        shortVersion: '1.0.0',
        bundleVersion: '1',
      );
      expect(plist.trimLeft(), startsWith('<?xml version="1.0"'));
      expect(plist.trimRight(), endsWith('</plist>'));
      // Balanced dict.
      expect('<dict>'.allMatches(plist).length, '</dict>'.allMatches(plist).length);
    });
  });

  // --- Issue #1: App.framework embedded via Xcode build phase -------------
  group('Xcode project embeds App.framework as a build phase', () {
    const fs = LocalFileSystem();

    for (final relativePath in <String>[
      'templates/app/swift/tvos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl',
      'packages/flutter_tvos/example/tvos/Runner.xcodeproj/project.pbxproj',
    ]) {
      test('$relativePath has an "Embed App.framework" run-script phase', () {
        final File file = fs.file(relativePath);
        expect(file.existsSync(), isTrue, reason: 'expected to find $relativePath from package root');
        final String pbxproj = file.readAsStringSync();

        // The phase is declared...
        expect(pbxproj, contains('/* Embed App.framework */'));
        expect(pbxproj, contains('isa = PBXShellScriptBuildPhase;'));
        // ...wired into the target's build phases (appears at least twice:
        // once in buildPhases list, once in the phase definition)...
        expect('/* Embed App.framework */'.allMatches(pbxproj).length, greaterThanOrEqualTo(2));
        // ...and the script actually copies + signs App.framework.
        expect(pbxproj, contains(r'Flutter/App.framework'));
        expect(pbxproj, contains(r'EXPANDED_CODE_SIGN_IDENTITY'));
      });
    }
  });

  // --- Embedded Flutter.framework is re-signed with the app identity ------
  //
  // The Flutter engine is pulled into the app bundle transitively through the
  // static FlutterGeneratedPluginSwiftPackage umbrella (a .binaryTarget on the
  // dynamic Flutter.xcframework). Xcode embeds it but does NOT code-sign it,
  // so without this phase a device build embeds the framework exactly as
  // shipped — origin-signed by the flutter-tvos maintainer's team — and
  // nested code signed by a foreign team can fail device installs. A dedicated
  // build phase re-signs it with the app's own identity (like CocoaPods'
  // embed script used to).
  //
  // NOTE: this phase is NOT the ITMS-91065 ("Missing signature") fix. Apple's
  // commonly-used-SDK check requires the SDK's ORIGIN signature on the
  // artifact as vended to the build; an app-identity re-sign does not satisfy
  // it (proven by real App Store submissions rejected with ITMS-91065 both
  // with and without this phase). ITMS-91065 is fixed by signing the engine
  // artifact at packaging time (engine/build.sh --signing-identity).
  group('Xcode project signs the embedded Flutter.framework', () {
    const fs = LocalFileSystem();

    for (final relativePath in <String>[
      'templates/app/swift/tvos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl',
      'packages/flutter_tvos/example/tvos/Runner.xcodeproj/project.pbxproj',
    ]) {
      test('$relativePath has a "Sign Flutter.framework" run-script phase', () {
        final File file = fs.file(relativePath);
        expect(file.existsSync(), isTrue, reason: 'expected to find $relativePath from package root');
        final String pbxproj = file.readAsStringSync();

        // The phase is declared and wired into the target's build phases
        // (appears at least twice: buildPhases list + phase definition).
        expect(pbxproj, contains('/* Sign Flutter.framework */'));
        expect('/* Sign Flutter.framework */'.allMatches(pbxproj).length, greaterThanOrEqualTo(2));

        // It must run AFTER Xcode embeds the SPM framework, so it is the last
        // build phase (after "Copy flutter_assets") in the buildPhases list.
        final int copyAssets = pbxproj.indexOf('9740EEB31CF901A200538489 /* Copy flutter_assets */,');
        final int signFlutter = pbxproj.indexOf('AAF50000000000000000F00D /* Sign Flutter.framework */,');
        expect(copyAssets, greaterThanOrEqualTo(0));
        expect(signFlutter, greaterThan(copyAssets),
            reason: 'Sign Flutter.framework must be listed after Copy flutter_assets');

        // The script codesigns Flutter.framework with the app's own identity.
        expect(pbxproj, contains(r'Frameworks/Flutter.framework'));
        expect(pbxproj, contains(r'codesign --force --sign'));
        expect(pbxproj, contains(r'EXPANDED_CODE_SIGN_IDENTITY'));
      });
    }
  });

  // --- App Store validation: the template asset catalog is complete --------
  //
  // Apple rejects tvOS archives whose brand assets miss @2x layer images or
  // the Top Shelf Image Wide asset. Every app created from the template must
  // therefore start with a complete catalog (proven complete by a real App
  // Store submission that passed asset validation).
  group('tvOS template asset catalog', () {
    const fs = LocalFileSystem();
    const brand =
        'templates/app/swift/tvos.tmpl/Runner/Assets.xcassets/AppIcon.brandassets';
    const suffix = '.copy.tmpl';

    test('every icon layer ships 1x + 2x images declared in Contents.json', () {
      for (final stack in <String>['Small', 'Large']) {
        final prefix = stack.toLowerCase();
        for (final layer in <String>['Back', 'Middle', 'Front']) {
          final dir =
              '$brand/App Icon - $stack.imagestack/$layer.imagestacklayer/Content.imageset';
          final base = '${prefix}_${layer.toLowerCase()}';
          expect(fs.file('$dir/$base.png$suffix').existsSync(), isTrue,
              reason: 'missing $base.png');
          expect(fs.file('$dir/$base@2x.png$suffix').existsSync(), isTrue,
              reason: 'missing $base@2x.png (App Store rejects 1x-only layers)');
          final json = fs.file('$dir/Contents.json$suffix').readAsStringSync();
          expect(json, contains('"$base.png"'));
          expect(json, contains('"$base@2x.png"'));
        }
      }
    });

    test('top shelf ships standard + wide, each with @2x', () {
      expect(fs.file('$brand/Top Shelf Image.imageset/top_shelf.png$suffix').existsSync(), isTrue);
      expect(fs.file('$brand/Top Shelf Image.imageset/top_shelf@2x.png$suffix').existsSync(), isTrue);
      expect(
        fs.file('$brand/Top Shelf Image Wide.imageset/top_shelf_wide.png$suffix').existsSync(),
        isTrue,
        reason: 'Top Shelf Image Wide is required by App Store validation',
      );
      expect(
        fs.file('$brand/Top Shelf Image Wide.imageset/top_shelf_wide@2x.png$suffix').existsSync(),
        isTrue,
      );
    });

    test('brand-assets index declares the wide top shelf role', () {
      final json = fs.file('$brand/Contents.json$suffix').readAsStringSync();
      expect(json, contains('"top-shelf-image-wide"'));
      expect(json, contains('"Top Shelf Image Wide.imageset"'));
      expect(json, contains('"2320x720"'));
    });
  });

  // --- Migration guard: an OLD project keeps its incomplete catalog ---------
  //
  // The asset catalog is copied into a project once (at `create`) and never
  // regenerated on build, so a project created before the catalog fix keeps an
  // incomplete catalog and still fails App Store validation even with a new
  // CLI. missingAppIconAssets lists exactly what's absent so the build can warn
  // — structurally, so a half-migrated catalog (wide role pasted in but the
  // @2x layers never produced) is still flagged.
  group('missingAppIconAssets', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem.test();
    });

    const String brandRoot =
        '/tvos/Runner/Assets.xcassets/AppIcon.brandassets';

    File indexFile() => fs.file('$brandRoot/Contents.json');

    // Creates the six @2x icon-layer PNGs the completed template ships.
    void createAll2xLayers() {
      for (final String stack in <String>['Small', 'Large']) {
        for (final String layer in <String>['Back', 'Middle', 'Front']) {
          fs
              .file('$brandRoot/App Icon - $stack.imagestack/'
                  '$layer.imagestacklayer/Content.imageset/'
                  '${stack.toLowerCase()}_${layer.toLowerCase()}@2x.png')
              .createSync(recursive: true);
        }
      }
    }

    // An old (pre-fix) index lists only the standard top shelf, no wide role.
    const String oldIndex =
        '{"assets":[{"filename":"App Icon - Large.imagestack","idiom":"tv","role":"primary-app-icon","size":"1280x768"},{"filename":"Top Shelf Image.imageset","idiom":"tv","role":"top-shelf-image","size":"1920x720"}],"info":{"version":1}}';
    const String completedIndex =
        '{"assets":[{"filename":"Top Shelf Image Wide.imageset","idiom":"tv","role":"top-shelf-image-wide","size":"2320x720"}],"info":{"version":1}}';

    test('flags the wide role and every @2x layer for an old catalog', () {
      indexFile()
        ..createSync(recursive: true)
        ..writeAsStringSync(oldIndex);
      final List<String> missing =
          NativeTvosBundle.missingAppIconAssets(fs.directory('/tvos'));
      expect(missing, isNotEmpty);
      expect(missing.first, contains('top-shelf-image-wide'));
      // The wide role plus all six @2x layer images are absent.
      expect(missing.length, 7);
    });

    // The regression the structural check exists for: a user pastes the wide
    // role into the index but never produces the @2x PNGs. The string-only
    // check would have gone quiet here.
    test('flags the @2x layers even when the wide role is already present', () {
      indexFile()
        ..createSync(recursive: true)
        ..writeAsStringSync(completedIndex);
      final List<String> missing =
          NativeTvosBundle.missingAppIconAssets(fs.directory('/tvos'));
      expect(missing, isNotEmpty);
      expect(missing.any((String m) => m.contains('top-shelf-image-wide')),
          isFalse);
      expect(missing.every((String m) => m.endsWith('@2x.png')), isTrue);
      expect(missing.length, 6);
    });

    test('empty for a fully complete catalog (wide role + all @2x layers)', () {
      indexFile()
        ..createSync(recursive: true)
        ..writeAsStringSync(completedIndex);
      createAll2xLayers();
      expect(NativeTvosBundle.missingAppIconAssets(fs.directory('/tvos')),
          isEmpty);
    });

    test('empty when no brand-assets catalog exists (nothing stock to check)',
        () {
      expect(NativeTvosBundle.missingAppIconAssets(fs.directory('/tvos')),
          isEmpty);
    });
  });

  // --- Migration guard: a pre-1.4.0 project.pbxproj resolves the bundle via
  // ${PRODUCT_NAME}.app in its build phases. That file is copied at `create`
  // and never rewritten on build, so an old project keeps the stale phases.
  // It only misresolves under a custom PRODUCT_NAME, so the check stays quiet
  // for default-named projects.
  group('pbxprojUsesStaleBundlePath', () {
    // Old phase: bundle resolved as ${PRODUCT_NAME}.app/... (trailing slash).
    String pbxproj({required String productName, required bool stalePath}) {
      final String bundlePath = stalePath
          ? r'${PRODUCT_NAME}.app/Frameworks'
          : r'${WRAPPER_NAME}/Frameworks';
      return '''
/* pbxproj */
  shellScript = "DEST=\\"\${BUILT_PRODUCTS_DIR}/$bundlePath\\"";
  PRODUCT_NAME = "$productName";
''';
    }

    test('true for a stale path under a custom product name', () {
      expect(
        NativeTvosBundle.pbxprojUsesStaleBundlePath(
            pbxproj(productName: 'MyTvApp', stalePath: true)),
        isTrue,
      );
    });

    test('false for a stale path under the default \$(TARGET_NAME)', () {
      expect(
        NativeTvosBundle.pbxprojUsesStaleBundlePath(
            pbxproj(productName: r'$(TARGET_NAME)', stalePath: true)),
        isFalse,
      );
    });

    test('false for a stale path under the default Runner', () {
      expect(
        NativeTvosBundle.pbxprojUsesStaleBundlePath(
            pbxproj(productName: 'Runner', stalePath: true)),
        isFalse,
      );
    });

    test('false for the current WRAPPER_NAME phases even with a custom name', () {
      expect(
        NativeTvosBundle.pbxprojUsesStaleBundlePath(
            pbxproj(productName: 'MyTvApp', stalePath: false)),
        isFalse,
      );
    });

    test('false when the token appears only in a comment (no trailing slash)',
        () {
      const String currentWithComment =
          '# Use CODESIGNING_FOLDER_PATH, not \${PRODUCT_NAME}.app, which is wrong\n'
          '  PRODUCT_NAME = "MyTvApp";\n';
      expect(NativeTvosBundle.pbxprojUsesStaleBundlePath(currentWithComment),
          isFalse);
    });
  });

  // --- #33: pod script phases need FLUTTER_ROOT + export environment -------
  //
  // Native-build tooling (e.g. cargokit for Rust FFI plugins) runs inside
  // CocoaPods script phases and sources tvos/Flutter/flutter_export_environment.sh
  // (or reads Generated.xcconfig) to locate the Dart SDK via FLUTTER_ROOT. The
  // tvOS build wrote neither before 1.3.4, so those phases failed with
  // "dart: command not found".
  group('Generated.xcconfig / flutter_export_environment content', () {
    test('Generated.xcconfig exports FLUTTER_ROOT and the build variables', () {
      final String xcconfig = NativeTvosBundle.buildGeneratedXcconfig(
        flutterRoot: '/opt/flutter-tvos/flutter',
        applicationPath: '/app',
        targetFile: 'lib/main.dart',
        buildDir: '/app/build',
        buildName: '2.3.4',
        buildNumber: '17',
        buildMode: 'release',
        stagedSdk: 'appletvos',
      );
      expect(xcconfig, contains('FLUTTER_ROOT=/opt/flutter-tvos/flutter'));
      expect(xcconfig, contains('FLUTTER_APPLICATION_PATH=/app'));
      expect(xcconfig, contains('FLUTTER_TARGET=lib/main.dart'));
      expect(xcconfig, contains('FLUTTER_BUILD_DIR=/app/build'));
      expect(xcconfig, contains('FLUTTER_BUILD_NAME=2.3.4'));
      expect(xcconfig, contains('FLUTTER_BUILD_NUMBER=17'));
      // COCOAPODS_PARALLEL_CODE_SIGN is an Xcode build setting consumed by the
      // `[CP] Embed Pods Frameworks` phase, so it only has an effect from the
      // xcconfig — never the .sh (that phase never sources it).
      expect(xcconfig, contains('COCOAPODS_PARALLEL_CODE_SIGN=true'));
    });

    test('flutter_export_environment.sh is a shell script exporting the vars',
        () {
      final String sh = NativeTvosBundle.buildFlutterExportEnvironment(
        flutterRoot: '/opt/flutter-tvos/flutter',
        applicationPath: '/app',
        targetFile: 'lib/main.dart',
        buildDir: '/app/build',
        buildName: '2.3.4',
        buildNumber: '17',
      );
      expect(sh, startsWith('#!/bin/sh'));
      // cargokit sources this and reads $FLUTTER_ROOT to find the Dart SDK.
      expect(sh, contains('export "FLUTTER_ROOT=/opt/flutter-tvos/flutter"'));
      expect(sh, contains('export "FLUTTER_APPLICATION_PATH=/app"'));
      expect(sh, contains('export "FLUTTER_TARGET=lib/main.dart"'));
      expect(sh, contains('export "FLUTTER_BUILD_DIR=/app/build"'));
      expect(sh, contains('export "FLUTTER_BUILD_NAME=2.3.4"'));
      expect(sh, contains('export "FLUTTER_BUILD_NUMBER=17"'));
      // COCOAPODS_PARALLEL_CODE_SIGN must NOT live here — the .sh is not sourced
      // by the CocoaPods embed phase, so it would be dead weight (it belongs in
      // the xcconfig, asserted above).
      expect(sh, isNot(contains('COCOAPODS_PARALLEL_CODE_SIGN')));
    });

    // Upstream invariant: the .sh is a strict subset of the xcconfig — every
    // unconditional `export "K=V"` in the script must appear as `K=V` in the
    // xcconfig. This catches settings that drift into the (ineffective) .sh
    // without a matching xcconfig entry.
    test('every export in the .sh has a matching Generated.xcconfig entry', () {
      const String flutterRoot = '/opt/flutter-tvos/flutter';
      const String applicationPath = '/app';
      const String targetFile = 'lib/main.dart';
      const String buildDir = '/app/build';
      const String buildName = '2.3.4';
      const String buildNumber = '17';
      final String sh = NativeTvosBundle.buildFlutterExportEnvironment(
        flutterRoot: flutterRoot,
        applicationPath: applicationPath,
        targetFile: targetFile,
        buildDir: buildDir,
        buildName: buildName,
        buildNumber: buildNumber,
      );
      final String xcconfig = NativeTvosBundle.buildGeneratedXcconfig(
        flutterRoot: flutterRoot,
        applicationPath: applicationPath,
        targetFile: targetFile,
        buildDir: buildDir,
        buildName: buildName,
        buildNumber: buildNumber,
        buildMode: 'release',
        stagedSdk: 'appletvos',
      );
      final RegExp exportLine = RegExp(r'^export "([^"]+)"$', multiLine: true);
      for (final Match m in exportLine.allMatches(sh)) {
        expect(xcconfig, contains(m.group(1)!),
            reason: 'setting from the .sh is missing from Generated.xcconfig');
      }
    });
  });

  // --- Swift Package Manager: umbrella wired into the Xcode project --------
  group('Xcode project references the FlutterGeneratedPluginSwiftPackage', () {
    const fs = LocalFileSystem();

    for (final relativePath in <String>[
      'templates/app/swift/tvos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl',
      'packages/flutter_tvos/example/tvos/Runner.xcodeproj/project.pbxproj',
    ]) {
      test('$relativePath wires the SPM umbrella package', () {
        final File file = fs.file(relativePath);
        expect(file.existsSync(), isTrue, reason: 'expected to find $relativePath from package root');
        final String pbxproj = file.readAsStringSync();

        // objectVersion >= 56 is required for XCLocalSwiftPackageReference.
        final Match? objVersion = RegExp(r'objectVersion = (\d+);').firstMatch(pbxproj);
        expect(objVersion, isNotNull);
        expect(int.parse(objVersion!.group(1)!), greaterThanOrEqualTo(56));

        // The local package reference + its section.
        expect(pbxproj, contains('isa = XCLocalSwiftPackageReference;'));
        expect(
          pbxproj,
          contains('relativePath = Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage;'),
        );
        // The product dependency + its section.
        expect(pbxproj, contains('isa = XCSwiftPackageProductDependency;'));
        expect(pbxproj, contains('productName = FlutterGeneratedPluginSwiftPackage;'));

        // Wired into the project's packageReferences and the Runner target's
        // packageProductDependencies, and linked in the Frameworks phase.
        expect(pbxproj, contains('packageReferences = ('));
        expect(pbxproj, contains('packageProductDependencies = ('));
        expect(pbxproj, contains('FlutterGeneratedPluginSwiftPackage in Frameworks'));
      });
    }
  });

  // --- #65: an Xcode archive ships whatever mode the CLI last staged --------
  //
  // The Runner project runs no Dart build: its phases copy the payload left in
  // tvos/Flutter by the last `flutter-tvos build/run`, and the engine comes
  // from the Flutter.xcframework that same run copied in. Xcode's CONFIGURATION
  // never touches any of it, so archiving Release straight after a debug run
  // shipped the JIT engine inside a release app -- which runs under development
  // signing and then hangs on a blank screen once installed from TestFlight
  // (reproduced end to end: a build with the debug engine never draws a frame,
  // while the same source built cleanly for release runs).
  //
  // FLUTTER_BUILD_MODE records the staged mode; the "Check Flutter build mode"
  // phase compares it against the configuration and fails the build.
  group('build-mode guard', () {
    const fs = LocalFileSystem();

    test('Generated.xcconfig records the staged build mode', () {
      for (final mode in <String>['debug', 'profile', 'release']) {
        expect(
          NativeTvosBundle.buildGeneratedXcconfig(
            flutterRoot: '/opt/flutter-tvos/flutter',
            applicationPath: '/app',
            targetFile: 'lib/main.dart',
            buildDir: '/app/build',
            buildName: '1.0.0',
            buildNumber: '1',
            buildMode: mode,
            stagedSdk: 'appletvos',
          ),
          contains('FLUTTER_STAGED_BUILD_MODE=$mode'),
        );
      }
    });

    for (final relativePath in <String>[
      'templates/app/swift/tvos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl',
      'packages/flutter_tvos/example/tvos/Runner.xcodeproj/project.pbxproj',
    ]) {
      test('$relativePath fails the build on a mode mismatch', () {
        final File file = fs.file(relativePath);
        expect(file.existsSync(), isTrue,
            reason: 'expected to find $relativePath from package root');
        final String pbxproj = file.readAsStringSync();

        // The phase exists and is wired into the target, not just defined.
        expect(pbxproj, contains('name = "Check Flutter build mode";'));
        expect(
          pbxproj,
          contains('AAF60000000000000000F00D /* Check Flutter build mode */,'),
          reason: 'the phase must be listed in the target buildPhases',
        );

        // It reads the staged mode and fails, rather than only warning: a
        // warning scrolls past in an archive log and the bad build still ships.
        final int guardStart =
            pbxproj.indexOf('name = "Check Flutter build mode";');
        final int guardEnd = pbxproj.indexOf('};', guardStart);
        final String guard = pbxproj.substring(guardStart, guardEnd);
        expect(guard, contains(r'STAGED=\"${FLUTTER_STAGED_BUILD_MODE}\"'),
            reason: 'the marker must not be FLUTTER_BUILD_MODE, which is '
                'upstream\'s user-facing override and can be set at target '
                'level, shadowing Generated.xcconfig');
        // The payload check is what survives a stale marker, so assert it is
        // present rather than trusting the marker comparison alone.
        expect(guard, contains('kernel_blob.bin'));
        expect(guard, contains('exit 1'));
        expect(guard, contains('flutter-tvos build tvos --'),
            reason: 'the error must tell the user how to fix it');

        // It has to run before the phases that copy the payload in, otherwise
        // a failing build has already written the wrong engine into the bundle.
        expect(
          pbxproj.indexOf('AAF60000000000000000F00D /* Check Flutter build mode */,'),
          lessThan(pbxproj.indexOf('AAF10000000000000000F00D /* Embed App.framework */,')),
        );
      });
    }
  });

  // Projects created before the guard existed keep their old phase list --
  // project.pbxproj is written once at `create` and never rewritten on build --
  // so the CLI warns instead, the same way it does for the other phases that
  // arrived after 1.0.0.
  group('pbxprojLacksBuildModeGuard', () {
    test('true for a project without the phase', () {
      expect(
        NativeTvosBundle.pbxprojLacksBuildModeGuard(
            '\t\t\t\tname = "Embed App.framework";\n'),
        isTrue,
      );
    });

    test('false once the phase is present', () {
      expect(
        NativeTvosBundle.pbxprojLacksBuildModeGuard(
            '\t\t\t\tname = "Check Flutter build mode";\n'),
        isFalse,
      );
    });
  });


  // Asserting on the phase's *text* only proves the strings are still there.
  // The thing that protects a release build is what the shell does, so run it:
  // an inverted condition, or a case pattern that stopped matching Release,
  // would leave every assertion above intact and still ship a dead app.
  group('build-mode guard script', () {
    const fs = LocalFileSystem();

    /// The phase's `shellScript`, unescaped back into the source Xcode runs.
    String guardScript(String pbxproj) {
      final int phase = pbxproj.indexOf('/* Check Flutter build mode */ = {');
      expect(phase, isNonNegative, reason: 'no build-mode guard phase found');
      const key = 'shellScript = "';
      final int start = pbxproj.indexOf(key, phase) + key.length;
      final int end = pbxproj.indexOf('";', start);
      final String escaped = pbxproj.substring(start, end);
      final source = StringBuffer();
      for (var i = 0; i < escaped.length; i++) {
        if (escaped[i] != r'\') {
          source.write(escaped[i]);
          continue;
        }
        // Xcode escapes exactly \n, \" and \\ in this string.
        final String escapee = escaped[++i];
        source.write(escapee == 'n' ? '\n' : escapee);
      }
      return source.toString();
    }

    /// Runs [script] the way the build phase would, against a throwaway
    /// project directory. [stagedMode] left null means an older CLI that never
    /// wrote FLUTTER_BUILD_MODE.
    ProcessResult runGuard(
      String script, {
      required String configuration,
      String? stagedMode,
      bool aotPayloadStaged = true,
      bool jitPayloadStaged = false,
      String? stagedSdk,
      String? platformName,
      bool optOut = false,
    }) {
      final Directory projectDir =
          fs.systemTempDirectory.createTempSync('flutter_tvos_guard.');
      addTearDown(() => projectDir.deleteSync(recursive: true));
      final File file = projectDir.childFile('check_flutter_build_mode.sh')
        ..writeAsStringSync(script);
      if (aotPayloadStaged) {
        projectDir
            .childDirectory('Flutter')
            .childDirectory('App.framework')
            .createSync(recursive: true);
      }
      if (jitPayloadStaged) {
        projectDir
            .childDirectory('Flutter')
            .childDirectory('flutter_assets')
            .childFile('kernel_blob.bin')
            .createSync(recursive: true);
      }
      return Process.runSync('/bin/sh', <String>[file.path], environment: <String, String>{
        'CONFIGURATION': configuration,
        'PROJECT_DIR': projectDir.path,
        if (stagedMode != null) 'FLUTTER_STAGED_BUILD_MODE': stagedMode,
        if (stagedSdk != null) 'FLUTTER_STAGED_SDK': stagedSdk,
        if (platformName != null) 'PLATFORM_NAME': platformName,
        if (optOut) 'FLUTTER_STAGED_BUILD_MODE_CHECK': 'off',
      });
    }

    for (final relativePath in <String>[
      'templates/app/swift/tvos.tmpl/Runner.xcodeproj/project.pbxproj.tmpl',
      'packages/flutter_tvos/example/tvos/Runner.xcodeproj/project.pbxproj',
    ]) {
      group(relativePath, () {
        late String script;

        setUp(() {
          script = guardScript(fs.file(relativePath).readAsStringSync());
        });

        // The reported failure: archive Release after a debug run and the
        // build ships the JIT engine, which cannot start under a distribution
        // signature.
        test('fails a Release build staged for debug', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Release', stagedMode: 'debug');
          expect(result.exitCode, 1);
          expect(result.stdout, contains('error: '));
          expect(result.stdout, contains('flutter-tvos build tvos --release'));
        });

        test('passes a Release build staged for release', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Release', stagedMode: 'release');
          expect(result.exitCode, 0, reason: result.stdout.toString());
        });

        test('passes a Debug build staged for debug', () {
          final ProcessResult result = runGuard(script,
              configuration: 'Debug',
              stagedMode: 'debug',
              aotPayloadStaged: false);
          expect(result.exitCode, 0, reason: result.stdout.toString());
        });

        // The CLI drives profile builds through the Release configuration, so
        // this pairing is normal and the payload is AOT either way.
        test('only warns for a Release build staged for profile', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Release', stagedMode: 'profile');
          expect(result.exitCode, 0);
          expect(result.stdout, contains('warning: '));
          expect(result.stdout, contains('profile'));
        });

        // An unset marker is the state after `flutter-tvos clean`, on a fresh
        // checkout (Generated.xcconfig is gitignored) and with a CLI older than
        // this phase. Under Debug the cost of guessing wrong is a launch
        // failure on a device in your hand, so it warns...
        test('only warns for a Debug build with no staged mode recorded', () {
          final ProcessResult result = runGuard(script,
              configuration: 'Debug', aotPayloadStaged: false);
          expect(result.exitCode, 0);
          expect(result.stdout, contains('warning: '));
        });

        // ...but under Release it is a submission that dies after review, and
        // the App.framework backstop cannot catch it: nothing in a normal build
        // ever deletes App.framework, so a release one survives any number of
        // debug builds and is still sitting there.
        test('fails a Release build with no staged mode recorded', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Release');
          expect(result.exitCode, 1);
          expect(result.stdout, contains('error: '));
        });

        test('fails an unrecorded Release build even with App.framework staged',
            () {
          final ProcessResult result = runGuard(script,
              configuration: 'Release', aotPayloadStaged: true);
          expect(result.exitCode, 1);
        });

        // The payload check exists because the marker can go stale while what
        // is on disk cannot: a kernel_blob under a non-debug configuration is
        // proof of a JIT payload whatever the marker claims.
        test('fails a Release build with a JIT payload despite a release marker',
            () {
          final ProcessResult result = runGuard(script,
              configuration: 'Release',
              stagedMode: 'release',
              jitPayloadStaged: true);
          expect(result.exitCode, 1);
          expect(result.stdout, contains('kernel_blob.bin'));
        });

        // A simulator payload archives for a device just as quietly as a debug
        // one ships under Release.
        test('fails when the staged SDK does not match the platform', () {
          final ProcessResult result = runGuard(script,
              configuration: 'Release',
              stagedMode: 'release',
              stagedSdk: 'appletvsimulator',
              platformName: 'appletvos');
          expect(result.exitCode, 1);
          expect(result.stdout, contains('appletvsimulator'));
        });

        test('passes when the staged SDK matches the platform', () {
          final ProcessResult result = runGuard(script,
              configuration: 'Release',
              stagedMode: 'release',
              stagedSdk: 'appletvos',
              platformName: 'appletvos');
          expect(result.exitCode, 0, reason: result.stdout.toString());
        });

        // The four cases below exist because mutating the script to enforce
        // Release only, or deleting the Profile arm outright, previously left
        // every test green.
        test('fails a Debug build staged for release', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Debug', stagedMode: 'release');
          expect(result.exitCode, 1);
        });

        test('fails a Debug build staged for profile', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Debug', stagedMode: 'profile');
          expect(result.exitCode, 1);
        });

        test('fails a Profile build staged for debug', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Profile', stagedMode: 'debug');
          expect(result.exitCode, 1);
        });

        test('passes a Profile build staged for profile', () {
          final ProcessResult result =
              runGuard(script, configuration: 'Profile', stagedMode: 'profile');
          expect(result.exitCode, 0, reason: result.stdout.toString());
        });

        test('skips when CONFIGURATION is unset', () {
          final ProcessResult result =
              runGuard(script, configuration: '', stagedMode: 'debug');
          expect(result.exitCode, 0);
          expect(result.stdout, contains('warning: '));
        });

        test('honours the opt-out setting', () {
          final ProcessResult result = runGuard(script,
              configuration: 'Release',
              stagedMode: 'debug',
              optOut: true);
          expect(result.exitCode, 0);
        });

        test('fails a Release build with no App.framework staged', () {
          final ProcessResult result = runGuard(script,
              configuration: 'Release',
              stagedMode: 'release',
              aotPayloadStaged: false);
          expect(result.exitCode, 1);
          expect(result.stdout, contains('App.framework'));
        });

        // Flavors add configurations we know nothing about; guessing wrong
        // there would fail builds that are perfectly fine.
        test('skips a configuration it does not recognize', () {
          final ProcessResult result = runGuard(script,
              configuration: 'Staging', stagedMode: 'debug');
          expect(result.exitCode, 0);
          expect(result.stdout, contains('skipping'));
          // warning, not note: note is dropped by xcbeautify and most CI filters.
          expect(result.stdout, contains('warning: '));
        });
      });
    }
  });

}
