// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression tests for the TestFlight/App-Store packaging issues reported in
// https://github.com/fluttertv/flutter-tvos/issues/18:
//   1. App.framework was not embedded in archive builds (crash on launch).
//   2. App.framework's Info.plist was missing keys App Store validation needs.
//   3. flutter_assets were duplicated one level deep on rebuilds
//      (flutter_assets/assets/assets/...).

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:flutter_tvos/build_targets/application.dart';

import '../src/common.dart';

void main() {
  // --- Issue #3: flutter_assets duplication -------------------------------
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
        '-mtvos-version-min=13.0',
      );
    });

    test('simulator SDK uses the simulator flag', () {
      expect(
        NativeTvosBundle.tvosVersionMinFlag('appletvsimulator'),
        '-mtvos-simulator-version-min=13.0',
      );
    });
  });

  // Both AOT clang steps must carry the min-version flag, else App.framework's
  // LC_BUILD_VERSION minos is stamped with the SDK version (ITMS-90208). The
  // flag's value is covered above; here we assert it actually reaches the argv.
  group('AOT clang argv carry the min-version flag', () {
    const String flag = '-mtvos-version-min=13.0';

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
}
