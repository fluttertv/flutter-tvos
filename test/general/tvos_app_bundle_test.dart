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
