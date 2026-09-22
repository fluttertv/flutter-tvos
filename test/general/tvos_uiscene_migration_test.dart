// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tvos/tvos_uiscene_migration.dart';
import 'package:test/fake.dart';

import '../src/common.dart';

/// The runner's Info.plist as the tvOS template generated it before scenes,
/// comment included.
const _preSceneInfoPlist = r'''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <!--
    FLTAssetsPath points the engine at the directory the build produces.
  -->
  <key>FLTAssetsPath</key>
  <string>flutter_assets</string>
  <key>UIMainStoryboardFile</key>
  <string>Main</string>
</dict>
</plist>
''';

const _sceneManifest = '''
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UISceneConfigurations</key>
    <dict/>
  </dict>
''';

/// The runner's Main.storyboard as the tvOS template generated it: the class
/// reference that UIKit cannot resolve.
const _brokenStoryboard = '''
<document type="com.apple.InterfaceBuilder.AppleTV.Storyboard" initialViewController="BYZ-38-t0r">
  <scenes>
    <scene sceneID="tne-QT-ifu">
      <objects>
        <viewController id="BYZ-38-t0r"
                        customClass="FlutterViewController"
                        customModule="Flutter" customModuleProvider="framework"
                        sceneMemberID="viewController">
          <view key="view" id="8bC-Xf-vdC"/>
        </viewController>
        <view id="other" customClass="MyView" customModule="Runner" customModuleProvider="target"/>
      </objects>
    </scene>
  </scenes>
</document>
''';

/// What `defaults write` leaves in place of the XML: a binary plist, which is
/// not UTF-8 text.
final List<int> _binaryInfoPlist = <int>[...utf8.encode('bplist00'), 0xd1, 0x01, 0xff, 0xfe, 0x00];

void main() {
  late MemoryFileSystem fs;
  late Directory runner;
  late BufferLogger logger;
  late _FakePlistParser plistParser;

  File infoPlist() => runner.childFile('Info.plist');
  File appDelegate() => runner.childFile('AppDelegate.swift');
  File storyboard() => runner.childDirectory('Base.lproj').childFile('Main.storyboard');

  setUp(() {
    fs = MemoryFileSystem.test();
    runner = fs.directory('/app/tvos/Runner');
    runner.childDirectory('Base.lproj').createSync(recursive: true);
    infoPlist().writeAsStringSync(_preSceneInfoPlist);
    appDelegate().writeAsStringSync(TvosUISceneMigration.originalAppDelegate);
    storyboard().writeAsStringSync(_brokenStoryboard);
    logger = BufferLogger.test();
    plistParser = _FakePlistParser(fs);
  });

  Future<void> migrate({bool enabled = true}) => TvosUISceneMigration(
    runner,
    logger,
    isMigrationFeatureEnabled: enabled,
    plistParser: plistParser,
  ).migrate();

  void goOnScenes() {
    infoPlist().writeAsStringSync(
      _preSceneInfoPlist.replaceFirst(
        '  <key>UIMainStoryboardFile</key>',
        '$_sceneManifest  <key>UIMainStoryboardFile</key>',
      ),
    );
  }

  group('an unchanged template project', () {
    testWithoutContext('is moved onto scenes: AppDelegate, manifest and storyboard', () async {
      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      final String plist = infoPlist().readAsStringSync();
      expect(plist, contains('<key>UIApplicationSceneManifest</key>'));
      expect(plist, contains('<string>FlutterSceneDelegate</string>'));
      expect(plist, contains('<string>Main</string>'));
      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(logger.statusText, contains('Finished migration to UIScene lifecycle'));
      // The storyboard is part of the migration, not a separate repair.
      expect(logger.statusText, isNot(contains('Fixed ')));
      expect(logger.warningText, isEmpty);
    });

    testWithoutContext('keeps the Info.plist comments, which plutil -insert would drop', () async {
      await migrate();

      expect(infoPlist().readAsStringSync(), contains('FLTAssetsPath points the engine'));
      expect(plistParser.insertedKeys, isEmpty);
    });

    testWithoutContext(
      'still counts as unchanged when reindented with CRLF line endings',
      () async {
        appDelegate().writeAsStringSync(
          TvosUISceneMigration.originalAppDelegate
              .replaceAll('    ', '\t')
              .replaceAll('\n', '\r\n'),
        );

        await migrate();

        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      },
    );

    testWithoutContext(
      'falls back to plutil -insert when the manifest cannot go in as text',
      () async {
        // A binary or reformatted plist: plutil still reads the storyboard name,
        // but there is no `<key>UIMainStoryboardFile</key>` line to insert at.
        plistParser.storyboardNameOverride = 'Main';
        infoPlist().writeAsStringSync('bplist00-not-text');

        await migrate();

        expect(plistParser.insertedKeys, <String>['UIApplicationSceneManifest']);
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      },
    );

    testWithoutContext('is left alone when the manifest cannot be inserted either way', () async {
      plistParser.storyboardNameOverride = 'Main';
      plistParser.insertSucceeds = false;
      infoPlist().writeAsStringSync('bplist00-not-text');

      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
      expect(infoPlist().readAsStringSync(), 'bplist00-not-text');
      expect(storyboard().readAsStringSync(), _brokenStoryboard);
      expect(logger.errorText, contains('will not launch on tvOS 27'));
      expect(logger.errorText, contains('Info.plist could not be edited'));
      expect(logger.errorText, isNot(contains('has been changed')));
    });

    testWithoutContext('is migrated through plutil when its Info.plist is binary', () async {
      plistParser.storyboardNameOverride = 'Main';
      infoPlist().writeAsBytesSync(_binaryInfoPlist);

      await migrate();

      expect(plistParser.insertedKeys, <String>['UIApplicationSceneManifest']);
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(logger.errorText, isEmpty);
    });

    testWithoutContext(
      'is told why when its Info.plist names another storyboard, and nothing is touched',
      () async {
        final String otherStoryboard = _preSceneInfoPlist.replaceFirst(
          '<string>Main</string>',
          '<string>Other</string>',
        );
        infoPlist().writeAsStringSync(otherStoryboard);

        await migrate();

        expect(infoPlist().readAsStringSync(), otherStoryboard);
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
        expect(storyboard().readAsStringSync(), _brokenStoryboard);
        expect(logger.errorText, contains('does not name Main as its UIMainStoryboardFile'));
        expect(logger.errorText, isNot(contains('has been changed')));
      },
    );

    testWithoutContext('says nothing and changes nothing on the next build', () async {
      await migrate();
      final String plist = infoPlist().readAsStringSync();
      final String board = storyboard().readAsStringSync();
      logger.clear();

      await migrate();

      expect(infoPlist().readAsStringSync(), plist);
      expect(storyboard().readAsStringSync(), board);
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(logger.statusText, isEmpty);
      expect(logger.warningText, isEmpty);
      expect(logger.errorText, isEmpty);
    });
  });

  group('a project already on scenes', () {
    testWithoutContext('gets its storyboard fixed, and nothing else (#87)', () async {
      goOnScenes();
      appDelegate().writeAsStringSync(TvosUISceneMigration.migratedAppDelegate);

      await migrate();

      final String board = storyboard().readAsStringSync();
      expect(board, contains('customClass="FlutterViewController"'));
      expect(board, isNot(contains('customModule="Flutter"')));
      expect(board, isNot(contains('customModuleProvider="framework"')));
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(logger.statusText, contains('Fixed Base.lproj/Main.storyboard'));
      expect(logger.warningText, isEmpty);
    });

    testWithoutContext('is recognised from a binary Info.plist', () async {
      infoPlist().writeAsBytesSync(_binaryInfoPlist);
      plistParser.sceneManifestOverride = true;
      appDelegate().writeAsStringSync(TvosUISceneMigration.migratedAppDelegate);

      await migrate();

      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(plistParser.insertedKeys, isEmpty);
    });

    testWithoutContext('leaves other classes in the storyboard as they were', () async {
      goOnScenes();

      await migrate();

      expect(
        storyboard().readAsStringSync(),
        contains('customClass="MyView" customModule="Runner" customModuleProvider="target"'),
      );
    });

    testWithoutContext(
      'is warned when the AppDelegate still builds its own view controller',
      () async {
        goOnScenes();

        await migrate();

        expect(logger.warningText, contains('creates its own FlutterViewController'));
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
      },
    );
  });

  group('a project with a changed AppDelegate', () {
    testWithoutContext('is told how to migrate, and nothing is touched', () async {
      const custom = '// my changes\n${TvosUISceneMigration.originalAppDelegate}';
      appDelegate().writeAsStringSync(custom);

      await migrate();

      expect(appDelegate().readAsStringSync(), custom);
      expect(infoPlist().readAsStringSync(), _preSceneInfoPlist);
      // Fixed, the storyboard would make UIKit build a second, throwaway
      // FlutterViewController behind the one this AppDelegate creates.
      expect(storyboard().readAsStringSync(), _brokenStoryboard);
      expect(logger.errorText, contains('will not launch on tvOS 27'));
      expect(logger.errorText, contains('AppDelegate.swift has been changed'));
      // It still builds its own window, which scenes would never show.
      expect(logger.errorText, contains('also remove the window and FlutterViewController'));
      expect(logger.statusText, isEmpty);
    });
  });

  testWithoutContext("does nothing with upstream's enable-uiscene-migration off", () async {
    goOnScenes();

    await migrate(enabled: false);

    expect(storyboard().readAsStringSync(), _brokenStoryboard);
    expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
    expect(logger.statusText, isEmpty);
    expect(logger.warningText, isEmpty);
    expect(logger.errorText, isEmpty);
  });

  testWithoutContext('does nothing without a runner Info.plist', () async {
    infoPlist().deleteSync();

    await migrate();

    expect(storyboard().readAsStringSync(), _brokenStoryboard);
    expect(logger.statusText, isEmpty);
    expect(logger.warningText, isEmpty);
    expect(logger.errorText, isEmpty);
  });
}

/// Reads the two keys the migration asks for out of the file text, and
/// records what would have gone through `plutil -insert`.
class _FakePlistParser extends Fake implements PlistParser {
  _FakePlistParser(this._fs);

  final FileSystem _fs;
  final List<String> insertedKeys = <String>[];
  bool insertSucceeds = true;
  String? storyboardNameOverride;
  bool? sceneManifestOverride;

  @override
  T? getValueFromFile<T>(String plistFilePath, String key) {
    final String text = utf8.decode(
      _fs.file(plistFilePath).readAsBytesSync(),
      allowMalformed: true,
    );
    switch (key) {
      case 'UIMainStoryboardFile':
        return (storyboardNameOverride ??
                RegExp(
                  r'<key>UIMainStoryboardFile</key>\s*<string>([^<]*)</string>',
                ).firstMatch(text)?.group(1))
            as T?;
      case 'UIApplicationSceneManifest':
        return ((sceneManifestOverride ?? text.contains('<key>UIApplicationSceneManifest</key>'))
                ? <String, Object>{}
                : null)
            as T?;
    }
    return null;
  }

  @override
  bool insertKeyWithJson(String plistFilePath, {required String key, required String json}) {
    insertedKeys.add(key);
    if (insertSucceeds) {
      _fs
          .file(plistFilePath)
          .writeAsBytesSync(utf8.encode('<key>$key</key>'), mode: FileMode.append);
    }
    return insertSucceeds;
  }
}
