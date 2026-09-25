// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io' as io;

import 'package:file/local.dart' as local;
import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/error_handling_io.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tvos/tvos_uiscene_migration.dart';
import 'package:process/process.dart';
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

/// A manifest as Flutter's guide adds it: one scene, built from Main.
const _sceneManifest = '''
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneStoryboardFile</key>
          <string>Main</string>
        </dict>
      </array>
    </dict>
  </dict>
''';

/// The pre-scene Info.plist written on one line, as some tools write XML:
/// there is no `<key>UIMainStoryboardFile</key>` line to insert before.
final String _oneLineInfoPlist = _preSceneInfoPlist.trim().replaceAll(RegExp(r'\n\s*'), ' ');

/// What `defaults write` leaves in place of the XML: a binary plist, which is
/// not UTF-8 text.
final List<int> _binaryInfoPlist = <int>[...utf8.encode('bplist00'), 0xd1, 0x01, 0xff, 0xfe, 0x00];

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

/// A storyboard whose `FlutterViewController` is the app's own Swift class in
/// the Runner module, which UIKit finds.
final String _appsOwnFlutterViewController = _brokenStoryboard.replaceFirst(
  'customModule="Flutter" customModuleProvider="framework"',
  'customModule="Runner" customModuleProvider="target"',
);

String _withManifest(String plist) => plist.replaceFirst(
  '  <key>UIMainStoryboardFile</key>',
  '$_sceneManifest  <key>UIMainStoryboardFile</key>',
);

void main() {
  late MemoryFileSystem fs;
  late Directory runner;
  late BufferLogger logger;
  late _FakePlistParser plistParser;

  File infoPlist() => runner.childFile('Info.plist');
  File appDelegate() => runner.childFile('AppDelegate.swift');
  File storyboard([String path = 'Base.lproj/Main.storyboard']) => runner.childFile(path);
  File writeStoryboard(String path, String contents) => storyboard(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

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

  void goOnScenes() => infoPlist().writeAsStringSync(_withManifest(_preSceneInfoPlist));

  group('an unchanged template project', () {
    testWithoutContext('is moved onto scenes: AppDelegate, manifest and storyboard', () async {
      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      final String plist = infoPlist().readAsStringSync();
      expect(plist, contains('<key>UIApplicationSceneManifest</key>'));
      expect(plist, contains('<string>FlutterSceneDelegate</string>'));
      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(logger.statusText, contains('Finished migration to UIScene lifecycle'));
      // The storyboard is part of the migration, not a separate repair.
      expect(logger.statusText, isNot(contains('Fixed ')));
      expect(logger.warningText, isEmpty);
      // A text plist is read as text; plutil only checks the insertion.
      expect(plistParser.readKeys, <String>['UIApplicationSceneManifest']);
      expect(plistParser.topLevelKeys(infoPlist()), contains('UIApplicationSceneManifest'));
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

    testWithoutContext('keeps a CRLF Info.plist CRLF', () async {
      infoPlist().writeAsStringSync(_preSceneInfoPlist.replaceAll('\n', '\r\n'));

      await migrate();

      final String plist = infoPlist().readAsStringSync();
      expect(plist, contains('<key>UIApplicationSceneManifest</key>'));
      expect(plist, isNot(matches(RegExp(r'[^\r]\n'))));
    });

    testWithoutContext(
      'puts the manifest in the root dictionary, past a commented-out UIMainStoryboardFile',
      () async {
        const comment = '  <!-- <key>UIMainStoryboardFile</key><string>Old</string> -->\n';
        infoPlist().writeAsStringSync(
          _preSceneInfoPlist.replaceFirst(
            '  <key>FLTAssetsPath</key>',
            '$comment  <key>FLTAssetsPath</key>',
          ),
        );

        await migrate();

        final String plist = infoPlist().readAsStringSync();
        expect(plist, contains(comment));
        expect(plistParser.insertedKeys, isEmpty);
        expect(plistParser.topLevelKeys(infoPlist()), contains('UIApplicationSceneManifest'));
        expect(
          plist.indexOf('<key>UIApplicationSceneManifest</key>'),
          greaterThan(plist.indexOf(comment) + comment.length - 1),
        );
      },
    );

    testWithoutContext(
      'puts the manifest in the root dictionary, past a nested UIMainStoryboardFile',
      () async {
        infoPlist().writeAsStringSync(
          _preSceneInfoPlist.replaceFirst(
            '  <key>FLTAssetsPath</key>',
            '  <key>Nested</key>\n'
                '  <dict>\n'
                '    <key>UIMainStoryboardFile</key>\n'
                '    <string>Main</string>\n'
                '  </dict>\n'
                '  <key>FLTAssetsPath</key>',
          ),
        );

        await migrate();

        expect(plistParser.insertedKeys, isEmpty);
        expect(plistParser.topLevelKeys(infoPlist()), contains('UIApplicationSceneManifest'));
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      },
    );

    testWithoutContext('is migrated when a comment only mentions the manifest', () async {
      // UIKit never reads a comment, so neither does the migration.
      infoPlist().writeAsStringSync(
        _preSceneInfoPlist.replaceFirst(
          '  <key>UIMainStoryboardFile</key>',
          '  <!-- <key>UIApplicationSceneManifest</key> comes with tvOS 27 -->\n'
              '  <key>UIMainStoryboardFile</key>',
        ),
      );

      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(logger.statusText, contains('Finished migration to UIScene lifecycle'));
    });

    testWithoutContext('is migrated when CDATA only holds the manifest key', () async {
      infoPlist().writeAsStringSync(
        _preSceneInfoPlist.replaceFirst(
          '  <key>UIMainStoryboardFile</key>',
          '  <key>Notes</key>\n'
              '  <string><![CDATA[<key>UIApplicationSceneManifest</key>]]></string>\n'
              '  <key>UIMainStoryboardFile</key>',
        ),
      );

      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(plistParser.topLevelKeys(infoPlist()), contains('UIApplicationSceneManifest'));
    });

    testWithoutContext(
      'falls back to plutil -insert when the manifest cannot go in as text',
      () async {
        infoPlist().writeAsStringSync(_oneLineInfoPlist);

        await migrate();

        expect(plistParser.insertedKeys, <String>['UIApplicationSceneManifest']);
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      },
    );

    testWithoutContext(
      'falls back to plutil -insert when plutil cannot read the text it inserted',
      () async {
        plistParser.manifestReadable = false;

        await migrate();

        expect(plistParser.insertedKeys, <String>['UIApplicationSceneManifest']);
        // The text insertion was taken back before plutil inserted its own.
        expect(
          infoPlist().readAsStringSync(),
          isNot(contains('UIApplicationSupportsMultipleScenes')),
        );
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      },
    );

    testWithoutContext('is left alone when the manifest cannot be inserted either way', () async {
      plistParser.insertSucceeds = false;
      infoPlist().writeAsStringSync(_oneLineInfoPlist);

      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
      expect(infoPlist().readAsStringSync(), _oneLineInfoPlist);
      expect(storyboard().readAsStringSync(), _brokenStoryboard);
      expect(logger.errorText, contains('will not launch on tvOS 27'));
      expect(logger.errorText, contains('Info.plist could not be edited'));
      expect(logger.errorText, isNot(contains('has been changed')));
    });

    testWithoutContext('is migrated through plutil when its Info.plist is binary', () async {
      plistParser.binaryStoryboardName = 'Main';
      infoPlist().writeAsBytesSync(_binaryInfoPlist);

      await migrate();

      expect(plistParser.insertedKeys, <String>['UIApplicationSceneManifest']);
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(logger.errorText, isEmpty);
    });

    testWithoutContext('is migrated without plutil when Xcode preprocesses its Info.plist', () async {
      // plutil cannot parse this at all; the insertion stands on its own.
      infoPlist().writeAsStringSync(
        _preSceneInfoPlist.replaceFirst(
          '  <key>FLTAssetsPath</key>',
          '#if DEBUG\n  <key>UIFileSharingEnabled</key>\n  <true/>\n#endif\n  <key>FLTAssetsPath</key>',
        ),
      );

      await migrate();

      expect(plistParser.readKeys, isEmpty);
      expect(plistParser.insertedKeys, isEmpty);
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      final String plist = infoPlist().readAsStringSync();
      expect(
        plist.indexOf('<key>UIApplicationSceneManifest</key>'),
        greaterThan(plist.indexOf('#endif')),
      );
      expect(logger.errorText, isEmpty);
    });

    testWithoutContext(
      'is left alone, without plutil, when its UIMainStoryboardFile is inside #if',
      () async {
        final String conditional = _preSceneInfoPlist.replaceFirst(
          '  <key>UIMainStoryboardFile</key>\n  <string>Main</string>\n',
          '#if TV\n  <key>UIMainStoryboardFile</key>\n  <string>Main</string>\n#endif\n',
        );
        infoPlist().writeAsStringSync(conditional);

        await migrate();

        expect(plistParser.readKeys, isEmpty);
        expect(plistParser.insertedKeys, isEmpty);
        expect(infoPlist().readAsStringSync(), conditional);
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
        expect(logger.errorText, contains('Info.plist is preprocessed'));
      },
    );

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

    testWithoutContext(
      'is left alone when its storyboard does not open on a FlutterViewController',
      () async {
        // tvOS never showed this storyboard before scenes, so it can have
        // drifted; a scene built from it would show a plain view controller.
        final String drifted = _brokenStoryboard.replaceFirst(
          'initialViewController="BYZ-38-t0r"',
          'initialViewController="other"',
        );
        storyboard().writeAsStringSync(drifted);

        await migrate();

        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
        expect(infoPlist().readAsStringSync(), _preSceneInfoPlist);
        expect(storyboard().readAsStringSync(), drifted);
        expect(logger.errorText, contains('does not open on a FlutterViewController'));
      },
    );

    testWithoutContext('is left alone when it has no Main.storyboard', () async {
      storyboard().deleteSync();

      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
      expect(infoPlist().readAsStringSync(), _preSceneInfoPlist);
      expect(logger.errorText, contains('has no Main.storyboard'));
    });

    testWithoutContext(
      'is migrated when Main.storyboard is only localized, with no Base',
      () async {
        runner.childDirectory('Base.lproj').deleteSync(recursive: true);
        final File localized = writeStoryboard('en.lproj/Main.storyboard', _brokenStoryboard);

        await migrate();

        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
        expect(localized.readAsStringSync(), isNot(contains('customModule="Flutter"')));
      },
    );

    testWithoutContext('gets its localized storyboards fixed with the rest', () async {
      final File localized = writeStoryboard('en.lproj/Main.storyboard', _brokenStoryboard);

      await migrate();

      expect(localized.readAsStringSync(), isNot(contains('customModule="Flutter"')));
      // Part of the migration: no separate repair message.
      expect(logger.statusText, isNot(contains('Fixed ')));
    });

    testWithoutContext('leaves LaunchScreen and other storyboards alone', () async {
      final File launchScreen = writeStoryboard(
        'Base.lproj/LaunchScreen.storyboard',
        _brokenStoryboard,
      );
      final File other = writeStoryboard('Other.storyboard', _brokenStoryboard);

      await migrate();

      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(launchScreen.readAsStringSync(), _brokenStoryboard);
      expect(other.readAsStringSync(), _brokenStoryboard);
    });

    testWithoutContext("keeps a FlutterViewController of the app's own module as it is", () async {
      storyboard().writeAsStringSync(_appsOwnFlutterViewController);

      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(storyboard().readAsStringSync(), _appsOwnFlutterViewController);
    });

    testWithoutContext('does not rewrite a storyboard that needs no fix', () async {
      storyboard().writeAsStringSync(_appsOwnFlutterViewController);
      final DateTime before = storyboard().statSync().modified;

      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(storyboard().statSync().modified, before);
    });

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
    setUp(goOnScenes);

    testWithoutContext('gets its storyboard fixed, and nothing else (#87)', () async {
      appDelegate().writeAsStringSync(TvosUISceneMigration.migratedAppDelegate);

      await migrate();

      final String board = storyboard().readAsStringSync();
      expect(board, contains('customClass="FlutterViewController"'));
      expect(board, isNot(contains('customModule="Flutter"')));
      expect(board, isNot(contains('customModuleProvider="framework"')));
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(logger.statusText, contains('Fixed tvos/Runner/Base.lproj/Main.storyboard'));
      expect(logger.warningText, isEmpty);
    });

    testWithoutContext(
      'is recognised without plutil when Xcode preprocesses its Info.plist',
      () async {
        // plutil cannot parse this, and every call on it prints plutil's
        // errors. Text is read as text.
        infoPlist().writeAsStringSync(
          infoPlist().readAsStringSync().replaceFirst(
            '  <key>UIMainStoryboardFile</key>',
            '#if DEBUG\n  <key>UIFileSharingEnabled</key>\n  <true/>\n#endif\n'
                '  <key>UIMainStoryboardFile</key>',
          ),
        );

        await migrate();

        expect(plistParser.readKeys, isEmpty);
        expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      },
    );

    testWithoutContext('is recognised from a binary Info.plist', () async {
      infoPlist().writeAsBytesSync(_binaryInfoPlist);
      plistParser.binaryManifest = <String, Object>{
        'UISceneConfigurations': <String, Object>{
          'UIWindowSceneSessionRoleApplication': <Object>[
            <String, Object>{'UISceneStoryboardFile': 'Main'},
          ],
        },
      };
      appDelegate().writeAsStringSync(TvosUISceneMigration.migratedAppDelegate);

      await migrate();

      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(plistParser.insertedKeys, isEmpty);
    });

    testWithoutContext(
      'gets every copy of its storyboard fixed, localized ones included',
      () async {
        final File localized = writeStoryboard('en.lproj/Main.storyboard', _brokenStoryboard);

        await migrate();

        expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
        expect(localized.readAsStringSync(), isNot(contains('customModule="Flutter"')));
      },
    );

    testWithoutContext('fixes only the storyboards its scene manifest names', () async {
      final File launchScreen = writeStoryboard(
        'Base.lproj/LaunchScreen.storyboard',
        _brokenStoryboard,
      );
      final File shared = writeStoryboard('Shared/Widgets.storyboard', _brokenStoryboard);

      await migrate();

      expect(storyboard().readAsStringSync(), isNot(contains('customModule="Flutter"')));
      expect(launchScreen.readAsStringSync(), _brokenStoryboard);
      expect(shared.readAsStringSync(), _brokenStoryboard);
    });

    testWithoutContext("leaves a FlutterViewController of the app's own module alone", () async {
      storyboard().writeAsStringSync(_appsOwnFlutterViewController);

      await migrate();

      expect(storyboard().readAsStringSync(), _appsOwnFlutterViewController);
      expect(logger.statusText, isNot(contains('Fixed ')));
    });

    testWithoutContext('leaves other classes in the storyboard as they were', () async {
      await migrate();

      expect(
        storyboard().readAsStringSync(),
        contains('customClass="MyView" customModule="Runner" customModuleProvider="target"'),
      );
    });

    testWithoutContext('does not follow a link out of the project', () async {
      final File outside = fs.file('/elsewhere/Shared.lproj/Main.storyboard')
        ..createSync(recursive: true)
        ..writeAsStringSync(_brokenStoryboard);
      fs.link(runner.childDirectory('Shared.lproj').path).createSync('/elsewhere/Shared.lproj');
      final File linkedFile = fs.file('/elsewhere/Linked.storyboard')
        ..writeAsStringSync(_brokenStoryboard);
      runner.childDirectory('Base.lproj').deleteSync(recursive: true);
      runner.childDirectory('Base.lproj').createSync();
      fs.link(storyboard().path).createSync(linkedFile.path);

      await migrate();

      expect(outside.readAsStringSync(), _brokenStoryboard);
      expect(linkedFile.readAsStringSync(), _brokenStoryboard);
    });

    testWithoutContext('has an unchanged template AppDelegate migrated too', () async {
      // Moved onto scenes by hand, with the template's AppDelegate left in
      // place: its window is never shown, and its plugins never reach the
      // scene's engine.
      await migrate();

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.migratedAppDelegate);
      expect(logger.statusText, contains('Finished migration to UIScene lifecycle'));
      expect(logger.warningText, isEmpty);
    });

    testWithoutContext(
      'keeps the template AppDelegate when its scene names no storyboard to show',
      () async {
        // The scene builds its window some other way; the AppDelegate's may
        // be all the app shows.
        infoPlist().writeAsStringSync(
          _withManifest(_preSceneInfoPlist).replaceFirst(
            '          <key>UISceneStoryboardFile</key>\n          <string>Main</string>\n',
            '',
          ),
        );

        await migrate();

        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
        expect(logger.warningText, contains('creates its own FlutterViewController'));
      },
    );

    testWithoutContext(
      'is warned when a changed AppDelegate still builds its own view controller',
      () async {
        const custom = '// my changes\n${TvosUISceneMigration.originalAppDelegate}';
        appDelegate().writeAsStringSync(custom);

        await migrate();

        expect(logger.warningText, contains('creates its own FlutterViewController'));
        expect(appDelegate().readAsStringSync(), custom);
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

  group("with upstream's enable-uiscene-migration off", () {
    testWithoutContext('a project is not migrated, and nothing is said', () async {
      await migrate(enabled: false);

      expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
      expect(infoPlist().readAsStringSync(), _preSceneInfoPlist);
      expect(storyboard().readAsStringSync(), _brokenStoryboard);
      expect(logger.statusText, isEmpty);
      expect(logger.warningText, isEmpty);
      expect(logger.errorText, isEmpty);
    });

    testWithoutContext(
      'a project on scenes is told what keeps it from starting, and nothing is edited',
      () async {
        goOnScenes();

        await migrate(enabled: false);

        expect(storyboard().readAsStringSync(), _brokenStoryboard);
        expect(appDelegate().readAsStringSync(), TvosUISceneMigration.originalAppDelegate);
        expect(logger.statusText, isEmpty);
        expect(
          logger.warningText,
          contains('tvos/Runner/Base.lproj/Main.storyboard names FlutterViewController'),
        );
        expect(logger.warningText, contains('creates its own FlutterViewController'));
      },
    );

    testWithoutContext('a missing runner Info.plist is not reported', () async {
      infoPlist().deleteSync();

      await migrate(enabled: false);

      expect(logger.errorText, isEmpty);
    });
  });

  testWithoutContext('says it cannot tell without a runner Info.plist', () async {
    infoPlist().deleteSync();

    await migrate();

    expect(storyboard().readAsStringSync(), _brokenStoryboard);
    expect(logger.errorText, contains('could not find tvos/Runner/Info.plist'));
    expect(logger.errorText, contains('#hide-migration-warning'));
  });

  // On disk, through the file system and plutil the tool really uses: a
  // permission error, and what plutil makes of the text insertion.
  group('on a real file system', () {
    late io.Directory temp;
    late FileSystem localFs;
    late Directory diskRunner;

    setUp(() {
      temp = io.Directory.systemTemp.createTempSync('tvos_uiscene_migration.');
      localFs = ErrorHandlingFileSystem(
        delegate: const local.LocalFileSystem(),
        platform: FakePlatform(operatingSystem: 'macos'),
      );
      diskRunner = localFs.directory(temp.path).childDirectory('Runner');
      diskRunner.childDirectory('Base.lproj').createSync(recursive: true);
      diskRunner.childFile('Info.plist').writeAsStringSync(_preSceneInfoPlist);
      diskRunner
          .childFile('AppDelegate.swift')
          .writeAsStringSync(TvosUISceneMigration.originalAppDelegate);
      diskRunner
          .childDirectory('Base.lproj')
          .childFile('Main.storyboard')
          .writeAsStringSync(_brokenStoryboard);
    });

    tearDown(() {
      io.Process.runSync('chmod', <String>['-R', 'u+w', temp.path]);
      temp.deleteSync(recursive: true);
    });

    void readOnly(String path) {
      expect(
        io.Process.runSync('chmod', <String>['444', diskRunner.childFile(path).path]).exitCode,
        0,
      );
    }

    Future<void> migrateOnDisk({PlistParser? parser}) => TvosUISceneMigration(
      diskRunner,
      logger,
      isMigrationFeatureEnabled: true,
      plistParser:
          parser ??
          PlistParser(
            fileSystem: localFs,
            logger: logger,
            processManager: const LocalProcessManager(),
          ),
    ).migrate();

    String plutil(String keyPath) {
      final io.ProcessResult result = io.Process.runSync('plutil', <String>[
        '-extract',
        keyPath,
        'raw',
        '-o',
        '-',
        diskRunner.childFile('Info.plist').path,
      ]);
      expect(result.exitCode, 0, reason: '$keyPath: ${result.stderr}');
      return (result.stdout as String).trim();
    }

    testWithoutContext(
      'reports a storyboard it cannot write, rather than failing the build',
      () async {
        diskRunner.childFile('Info.plist').writeAsStringSync(_withManifest(_preSceneInfoPlist));
        diskRunner
            .childFile('AppDelegate.swift')
            .writeAsStringSync(TvosUISceneMigration.migratedAppDelegate);
        readOnly('Base.lproj/Main.storyboard');

        await migrateOnDisk();

        expect(
          logger.errorText,
          contains('Could not write tvos/Runner/Base.lproj/Main.storyboard'),
        );
        expect(
          diskRunner.childDirectory('Base.lproj').childFile('Main.storyboard').readAsStringSync(),
          _brokenStoryboard,
        );
      },
    );

    testWithoutContext('reports an Info.plist it cannot write, and changes nothing', () async {
      readOnly('Info.plist');

      await migrateOnDisk();

      expect(logger.errorText, contains('Info.plist could not be written'));
      expect(
        diskRunner.childFile('AppDelegate.swift').readAsStringSync(),
        TvosUISceneMigration.originalAppDelegate,
      );
    });

    testWithoutContext(
      'takes the manifest back out when the AppDelegate cannot be written',
      () async {
        readOnly('AppDelegate.swift');

        await migrateOnDisk();

        expect(logger.errorText, contains('AppDelegate.swift could not be written'));
        expect(diskRunner.childFile('Info.plist').readAsStringSync(), _preSceneInfoPlist);
      },
    );

    testWithoutContext(
      'puts the manifest where plutil finds it, past a commented-out and a nested key',
      () async {
        const comment = '  <!-- <key>UIMainStoryboardFile</key><string>Old</string> -->\n';
        diskRunner
            .childFile('Info.plist')
            .writeAsStringSync(
              _preSceneInfoPlist.replaceFirst(
                '  <key>FLTAssetsPath</key>',
                '$comment'
                    '  <key>Nested</key>\n'
                    '  <dict>\n'
                    '    <key>UIMainStoryboardFile</key>\n'
                    '    <string>Main</string>\n'
                    '  </dict>\n'
                    '  <key>FLTAssetsPath</key>',
              ),
            );

        await migrateOnDisk();

        expect(
          plutil(
            'UIApplicationSceneManifest.UISceneConfigurations.'
            'UIWindowSceneSessionRoleApplication.0.UISceneDelegateClassName',
          ),
          'FlutterSceneDelegate',
        );
        final String plist = diskRunner.childFile('Info.plist').readAsStringSync();
        // Put in as text, not by `plutil -insert`, which drops comments.
        expect(plist, contains(comment));
        expect(plist, contains('FLTAssetsPath points the engine'));
        expect(logger.errorText, isEmpty);
      },
    );

    testWithoutContext('leaves a CRLF Info.plist valid for plutil', () async {
      diskRunner
          .childFile('Info.plist')
          .writeAsStringSync(_preSceneInfoPlist.replaceAll('\n', '\r\n'));

      await migrateOnDisk();

      expect(plutil('UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes'), 'false');
      expect(
        diskRunner.childFile('Info.plist').readAsStringSync(),
        isNot(matches(RegExp(r'[^\r]\n'))),
      );
    });
  });
}

/// Reads plist keys out of the file the way plutil would for a well-formed
/// XML plist — the root dictionary only, comments and CDATA ignored — and
/// records what it was asked. A binary plist answers from the fields below.
class _FakePlistParser extends Fake implements PlistParser {
  _FakePlistParser(this._fs);

  final FileSystem _fs;
  final List<String> insertedKeys = <String>[];
  final List<String> readKeys = <String>[];
  bool insertSucceeds = true;
  bool manifestReadable = true;
  String? binaryStoryboardName;
  Map<String, Object>? binaryManifest;

  /// The keys of [plist]'s root dictionary.
  List<String> topLevelKeys(File plist) {
    final String text = plist.readAsStringSync().replaceAll(
      RegExp(r'<!--.*?-->|<!\[CDATA\[.*?\]\]>', dotAll: true),
      '',
    );
    final keys = <String>[];
    var depth = 0;
    for (final Match token in RegExp(r'<dict\s*>|</dict\s*>|<key>([^<]*)</key>').allMatches(text)) {
      final String tag = token[0]!;
      if (tag.startsWith('</dict')) {
        depth--;
      } else if (tag.startsWith('<dict')) {
        depth++;
      } else if (depth == 1) {
        keys.add(token[1]!);
      }
    }
    return keys;
  }

  bool _isBinary(String path) =>
      _fs.file(path).readAsBytesSync().take(6).toList().toString() ==
      utf8.encode('bplist').toString();

  @override
  T? getValueFromFile<T>(String plistFilePath, String key) {
    readKeys.add(key);
    if (_isBinary(plistFilePath)) {
      return switch (key) {
            'UIMainStoryboardFile' => binaryStoryboardName,
            'UIApplicationSceneManifest' => binaryManifest,
            _ => null,
          }
          as T?;
    }
    if (!topLevelKeys(_fs.file(plistFilePath)).contains(key)) {
      return null;
    }
    switch (key) {
      case 'UIMainStoryboardFile':
        return RegExp(
              r'<key>UIMainStoryboardFile</key>\s*<string>([^<]*)</string>',
            ).firstMatch(_fs.file(plistFilePath).readAsStringSync())?.group(1)
            as T?;
      case 'UIApplicationSceneManifest':
        return (manifestReadable ? <String, Object>{} : null) as T?;
    }
    return null;
  }

  @override
  bool insertKeyWithJson(String plistFilePath, {required String key, required String json}) {
    insertedKeys.add(key);
    if (!insertSucceeds) {
      return false;
    }
    final File file = _fs.file(plistFilePath);
    if (_isBinary(plistFilePath)) {
      binaryManifest = <String, Object>{};
      return true;
    }
    // As plutil would: the new key in the root dictionary.
    final String text = file.readAsStringSync();
    final int root = text.indexOf(RegExp(r'<dict\s*>')) + '<dict>'.length;
    file.writeAsStringSync(text.replaceRange(root, root, '<key>$key</key><dict/>'));
    return true;
  }
}
