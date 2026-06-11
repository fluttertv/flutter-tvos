// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Phase 2 of tvOS Swift Package Manager support: the generators that produce
// the `FlutterFramework` binary-target package and the
// `FlutterGeneratedPluginSwiftPackage` umbrella a tvOS app build consumes.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tvos/tvos_swift_package_manager.dart';

import '../src/common.dart';

void main() {
  late MemoryFileSystem fs;
  late TvosSwiftPackageManager spm;

  setUp(() {
    fs = MemoryFileSystem.test();
    spm = TvosSwiftPackageManager(fileSystem: fs);
  });

  group('FlutterFramework package', () {
    test('writes a binary-target manifest and symlinks the xcframework', () {
      final Directory xcframework = fs.directory('/engine/Flutter.xcframework')
        ..createSync(recursive: true);
      final Directory pkg = fs.directory('/app/tvos/Flutter/ephemeral/Packages/FlutterFramework');

      spm.generateFlutterFrameworkPackage(packageDirectory: pkg, xcframework: xcframework);

      final String manifest = pkg.childFile('Package.swift').readAsStringSync();
      expect(manifest, contains('name: "FlutterFramework"'));
      expect(manifest, contains('.binaryTarget(name: "FlutterFramework", path: "Flutter.xcframework")'));

      final Link link = pkg.childLink('Flutter.xcframework');
      expect(link.existsSync(), isTrue);
      expect(link.targetSync(), '/engine/Flutter.xcframework');
    });

    test('is re-runnable (refreshes the symlink, no error)', () {
      final Directory xcframework = fs.directory('/engine/Flutter.xcframework')
        ..createSync(recursive: true);
      final Directory pkg = fs.directory('/app/Packages/FlutterFramework');
      spm.generateFlutterFrameworkPackage(packageDirectory: pkg, xcframework: xcframework);
      // Second run must not throw on the existing symlink.
      spm.generateFlutterFrameworkPackage(packageDirectory: pkg, xcframework: xcframework);
      expect(pkg.childLink('Flutter.xcframework').existsSync(), isTrue);
    });
  });

  group('FlutterGeneratedPluginSwiftPackage umbrella', () {
    Directory pluginAt(String name) {
      final Directory d = fs.directory('/pub/$name/tvos')..createSync(recursive: true);
      d.childFile('Package.swift').writeAsStringSync('// $name');
      return d;
    }

    test('depends on FlutterFramework and every plugin, with a static product', () {
      final Directory pkg = fs.directory('/app/Packages/FlutterGeneratedPluginSwiftPackage');
      final String manifest = spm.generatePluginsSwiftPackage(
        packageDirectory: pkg,
        flutterFrameworkRelativePath: '../FlutterFramework',
        plugins: <TvosSpmPlugin>[
          TvosSpmPlugin(name: 'shared_preferences_tvos', packagePath: pluginAt('shared_preferences_tvos').path),
          TvosSpmPlugin(name: 'url_launcher_tvos', packagePath: pluginAt('url_launcher_tvos').path),
        ],
      );

      // Umbrella identity + static linkage (so plugin symbols land in Runner).
      expect(manifest, contains('name: "FlutterGeneratedPluginSwiftPackage"'));
      expect(manifest, contains('type: .static'));
      expect(manifest, contains('.tvOS("13.0")'));

      // Flutter engine dependency.
      expect(manifest, contains('.package(name: "FlutterFramework", path: "../FlutterFramework")'));
      expect(manifest, contains('.product(name: "FlutterFramework", package: "FlutterFramework")'));

      // Plugin package deps reference the symlinked relative path.
      expect(manifest, contains('.package(name: "shared_preferences_tvos", path: ".packages/shared_preferences_tvos")'));
      expect(manifest, contains('.package(name: "url_launcher_tvos", path: ".packages/url_launcher_tvos")'));

      // Plugin PRODUCT names are hyphenated (SwiftPM CFBundleIdentifier rule).
      expect(manifest, contains('.product(name: "shared-preferences-tvos", package: "shared_preferences_tvos")'));
      expect(manifest, contains('.product(name: "url-launcher-tvos", package: "url_launcher_tvos")'));
    });

    test('symlinks each plugin under .packages/ and writes a sources placeholder', () {
      final Directory pkg = fs.directory('/app/Packages/FlutterGeneratedPluginSwiftPackage');
      final Directory pluginDir = pluginAt('shared_preferences_tvos');
      spm.generatePluginsSwiftPackage(
        packageDirectory: pkg,
        flutterFrameworkRelativePath: '../FlutterFramework',
        plugins: <TvosSpmPlugin>[
          TvosSpmPlugin(name: 'shared_preferences_tvos', packagePath: pluginDir.path),
        ],
      );

      final Link link = pkg.childDirectory('.packages').childLink('shared_preferences_tvos');
      expect(link.existsSync(), isTrue);
      expect(link.targetSync(), pluginDir.path);

      // SwiftPM requires a sources dir for the target.
      expect(
        pkg
            .childDirectory('Sources')
            .childDirectory('FlutterGeneratedPluginSwiftPackage')
            .childFile('FlutterGeneratedPluginSwiftPackage.swift')
            .existsSync(),
        isTrue,
      );
    });

    test('handles an app with no tvOS plugins (only the Flutter dependency)', () {
      final Directory pkg = fs.directory('/app/Packages/FlutterGeneratedPluginSwiftPackage');
      final String manifest = spm.generatePluginsSwiftPackage(
        packageDirectory: pkg,
        flutterFrameworkRelativePath: '../FlutterFramework',
        plugins: const <TvosSpmPlugin>[],
      );
      expect(manifest, contains('.package(name: "FlutterFramework", path: "../FlutterFramework")'));
      // No plugin package lines.
      expect(manifest, isNot(contains('.packages/')));
    });
  });
}
