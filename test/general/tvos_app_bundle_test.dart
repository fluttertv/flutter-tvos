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

  // --- ITMS-91065: embedded Flutter.framework is code-signed --------------
  //
  // The Flutter engine is pulled into the app bundle transitively through the
  // static FlutterGeneratedPluginSwiftPackage umbrella (a .binaryTarget on the
  // dynamic Flutter.xcframework). Xcode embeds it but does NOT code-sign it, so
  // archives shipped an unsigned engine and Beta App Review / the App Store
  // rejected them with ITMS-91065 ("Missing signature") — Flutter is a
  // commonly-used third-party SDK that must ship signed. A dedicated build
  // phase re-signs it with the app's own identity (like CocoaPods used to).
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
