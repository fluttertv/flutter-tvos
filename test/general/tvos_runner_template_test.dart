// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// The runner a new project gets, and the example app's copy of it, on the
// UIScene lifecycle: built with Xcode 27, a runner without scenes does not
// launch on tvOS 27. These read the files that ship, so reverting any part of
// the scene setup fails here rather than on a device.

import 'dart:io' as io;
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tvos/tvos_uiscene_migration.dart';
import 'package:test/fake.dart';

import '../src/common.dart';

const _template = 'templates/app/swift/tvos.tmpl';
const _example = 'packages/flutter_tvos/example/tvos';

/// The package root, found from the package itself rather than the working
/// directory: tests in other files run in this process at the same time, and
/// `flutter-tvos create .` tests move the working directory.
late Directory _root;

String _read(String path) => _root.childFile(path).readAsStringSync();

/// A value from a shipped plist, read by plutil as Xcode reads the file, so a
/// key that only sits in a comment does not count.
String _plutil(String path, String keyPath) {
  final io.ProcessResult result = io.Process.runSync('plutil', <String>[
    '-extract',
    keyPath,
    'raw',
    '-o',
    '-',
    _root.childFile(path).path,
  ]);
  expect(result.exitCode, 0, reason: '$keyPath in $path: ${result.stderr}');
  return (result.stdout as String).trim();
}

const _sceneConfiguration = 'UIApplicationSceneManifest.UISceneConfigurations.'
    'UIWindowSceneSessionRoleApplication.0';

/// The opening tag of the storyboard element whose class is
/// `FlutterViewController`, attributes and line breaks included.
String _flutterViewControllerTag(String storyboard) {
  final Iterable<Match> tags = RegExp(
    r'<[A-Za-z]+\b[^>]*\bcustomClass="FlutterViewController"[^>]*>',
  ).allMatches(storyboard);
  expect(tags, hasLength(1));
  return tags.single[0]!;
}

void main() {
  setUpAll(() async {
    final Uri lib = (await Isolate.resolvePackageUri(Uri.parse('package:flutter_tvos/')))!;
    _root = const LocalFileSystem().directory(lib.toFilePath()).parent;
  });

  group('the new-project runner', () {
    testWithoutContext('has the AppDelegate a migrated project gets', () {
      expect(
        _read('$_template/Runner/AppDelegate.swift.copy.tmpl'),
        TvosUISceneMigration.migratedAppDelegate,
      );
    });

    testWithoutContext('has a SceneDelegate built on FlutterSceneDelegate', () {
      expect(
        _read('$_template/Runner/SceneDelegate.swift.copy.tmpl'),
        contains('class SceneDelegate: FlutterSceneDelegate'),
      );
    });

    testWithoutContext('declares its scene in Info.plist, with that SceneDelegate and Main', () {
      const plist = '$_template/Runner/Info.plist.tmpl';

      expect(
        _plutil(plist, '$_sceneConfiguration.UISceneDelegateClassName'),
        r'$(PRODUCT_MODULE_NAME).SceneDelegate',
      );
      expect(_plutil(plist, '$_sceneConfiguration.UISceneStoryboardFile'), 'Main');
      expect(_plutil(plist, 'UIMainStoryboardFile'), 'Main');
      // One scene, as in Flutter's iOS template and the migrated manifest.
      expect(
        _plutil(plist, 'UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes'),
        'false',
      );
    });

    testWithoutContext('names FlutterViewController as the Objective-C class it is (#87)', () {
      final String storyboard = _read('$_template/Runner/Base.lproj/Main.storyboard.copy.tmpl');
      final String tag = _flutterViewControllerTag(storyboard);

      // With a module, Interface Builder encodes a Swift class name UIKit
      // cannot find, and the scene starts with a plain view controller.
      expect(tag, isNot(contains('customModule')));
      expect(storyboard, isNot(matches(RegExp(r'\n[ \t]+\n'))));
    });

    testWithoutContext('compiles SceneDelegate.swift into the Runner target', () {
      final String pbxproj = _read('$_template/Runner.xcodeproj/project.pbxproj.tmpl');
      final String fileRef = RegExp(
        r'(\w{24}) /\* SceneDelegate\.swift \*/ = \{isa = PBXFileReference;',
      ).firstMatch(pbxproj)![1]!;
      final String buildFile = RegExp(
        r'(\w{24}) /\* SceneDelegate\.swift in Sources \*/ = \{isa = PBXBuildFile; '
        'fileRef = $fileRef ',
      ).firstMatch(pbxproj)![1]!;

      String section(String name) =>
          RegExp('/\\* Begin $name section \\*/(.*?)/\\* End $name section \\*/', dotAll: true)
              .firstMatch(pbxproj)![1]!;
      expect(section('PBXSourcesBuildPhase'), contains(buildFile));
      expect(section('PBXGroup'), contains('$fileRef /* SceneDelegate.swift */'));
    });

    testWithoutContext('is left as it is by the migration on its first build', () async {
      final fileSystem = MemoryFileSystem.test();
      final Directory runner = fileSystem.directory('/app/tvos/Runner');
      final files = <String, String>{
        'Info.plist': _read('$_template/Runner/Info.plist.tmpl'),
        'AppDelegate.swift': _read('$_template/Runner/AppDelegate.swift.copy.tmpl'),
        'Base.lproj/Main.storyboard': _read(
          '$_template/Runner/Base.lproj/Main.storyboard.copy.tmpl',
        ),
      };
      files.forEach((String path, String content) {
        runner.childFile(path)
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
      });
      final logger = BufferLogger.test();

      await TvosUISceneMigration(
        runner,
        logger,
        isMigrationFeatureEnabled: true,
        plistParser: _NoPlutil(),
      ).migrate();

      files.forEach((String path, String content) {
        expect(runner.childFile(path).readAsStringSync(), content, reason: path);
      });
      expect(logger.statusText, isEmpty);
      expect(logger.warningText, isEmpty);
      expect(logger.errorText, isEmpty);
    });
  });

  group("the example app's runner", () {
    testWithoutContext('matches the template', () {
      for (final (String example, String template) in <(String, String)>[
        ('Runner/AppDelegate.swift', 'Runner/AppDelegate.swift.copy.tmpl'),
        ('Runner/SceneDelegate.swift', 'Runner/SceneDelegate.swift.copy.tmpl'),
        ('Runner/Base.lproj/Main.storyboard', 'Runner/Base.lproj/Main.storyboard.copy.tmpl'),
      ]) {
        expect(_read('$_example/$example'), _read('$_template/$template'), reason: example);
      }
    });

    testWithoutContext('declares its scene with the SceneDelegate it compiles', () {
      expect(
        _plutil('$_example/Runner/Info.plist', '$_sceneConfiguration.UISceneDelegateClassName'),
        r'$(PRODUCT_MODULE_NAME).SceneDelegate',
      );
      expect(
        _read('$_example/Runner.xcodeproj/project.pbxproj'),
        contains('/* SceneDelegate.swift in Sources */,'),
      );
    });
  });
}

/// A text Info.plist is read as text, so the migration has no reason to call
/// plutil on the template; any call would fail the test.
class _NoPlutil extends Fake implements PlistParser {}
