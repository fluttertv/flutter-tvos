// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// That the build runs the steps other tests cover on their own: the UIScene
// migration before the runner is built, and the plugin list refresh before
// the kernel compile. Each of those is tested directly elsewhere; without
// these, dropping the call from the build would leave the suite green.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/ios/plist_parser.dart';
import 'package:flutter_tools/src/macos/xcode.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/build_targets/application.dart';
import 'package:flutter_tvos/tvos_build_info.dart';
import 'package:flutter_tvos/tvos_builder.dart';
import 'package:flutter_tvos/tvos_uiscene_migration.dart';
import 'package:test/fake.dart';

import '../../flutter/packages/flutter_tools/test/src/test_build_system.dart';
import '../src/common.dart';
import '../src/context.dart';
import '../src/fakes.dart';

const _debugSimulator = TvosBuildInfo(
  BuildInfo(
    BuildMode.debug,
    null,
    treeShakeIcons: false,
    packageConfigPath: '.dart_tool/package_config.json',
  ),
  targetArch: 'arm64',
  simulator: true,
);

void main() {
  late MemoryFileSystem fileSystem;
  late BufferLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    logger = BufferLogger.test();
  });

  group('TvosBuilder.buildBundle', () {
    // The Dart registrant as the kernel compile found it.
    String? registrantAtCompile;
    setUp(() => registrantAtCompile = null);

    // A tvOS-only app after `flutter-tvos clean`: `validateCommand` ran before
    // `pub get`, so the plugin list it left has no plugins in it, and `pub get`
    // does not write one for a project with no platform of Flutter's own.
    FlutterProject seedCleanedApp() {
      final Directory app = fileSystem.directory('/app')..createSync();
      app.childDirectory('tvos').childDirectory('Runner').createSync(recursive: true);
      app.childDirectory('lib').childFile('main.dart').createSync(recursive: true);
      app
          .childFile('pubspec.yaml')
          .writeAsStringSync(
            'name: app\n'
            'dependencies:\n'
            '  gizmo_tvos:\n'
            '    path: ../plugins/gizmo_tvos\n',
          );
      fileSystem.file('/plugins/gizmo_tvos/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: gizmo_tvos
flutter:
  plugin:
    platforms:
      tvos:
        dartPluginClass: GizmoTvos
''');
      final Directory dartTool = app.childDirectory('.dart_tool')..createSync();
      dartTool
          .childFile('package_config.json')
          .writeAsStringSync(
            json.encode(<String, Object>{
              'configVersion': 2,
              'packages': <Map<String, String>>[
                <String, String>{'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
                <String, String>{
                  'name': 'gizmo_tvos',
                  'rootUri': '../../plugins/gizmo_tvos',
                  'packageUri': 'lib/',
                },
              ],
            }),
          );
      dartTool
          .childFile('package_graph.json')
          .writeAsStringSync(
            json.encode(<String, Object>{
              'configVersion': 1,
              'roots': <String>['app'],
              'packages': <Map<String, Object>>[
                <String, Object>{
                  'name': 'app',
                  'dependencies': <String>['gizmo_tvos'],
                  'devDependencies': <String>[],
                },
                <String, Object>{'name': 'gizmo_tvos', 'dependencies': <String>[]},
              ],
            }),
          );
      app
          .childFile('.flutter-plugins-dependencies')
          .writeAsStringSync(
            json.encode(<String, Object>{
              'plugins': <String, Object>{},
              'dependencyGraph': <Object>[],
            }),
          );
      return FlutterProject.fromDirectory(app);
    }

    testUsingContext(
      'compiles the Dart registrant with the tvOS plugins on the first build after `clean`',
      () async {
        await expectLater(
          TvosBuilder.buildBundle(
            project: seedCleanedApp(),
            tvosBuildInfo: _debugSimulator,
            targetFile: 'lib/main.dart',
          ),
          throwsToolExit(message: 'The build failed.'),
        );

        expect(registrantAtCompile, contains('gizmo_tvos.GizmoTvos.registerWith()'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => FakeProcessManager.any(),
        Logger: () => logger,
        Xcode: () => _FakeXcode(),
        // Stands in for the kernel compile: records what it would link in.
        BuildSystem: () => TestBuildSystem.all(BuildResult(success: false), (
          Target target,
          Environment environment,
        ) {
          final File registrant = fileSystem.file(
            '/app/.dart_tool/flutter_build/dart_plugin_registrant.dart',
          );
          registrantAtCompile = registrant.existsSync() ? registrant.readAsStringSync() : '';
        }),
      },
    );
  });

  group('NativeTvosBundle.build', () {
    testUsingContext(
      'moves an unchanged runner onto scenes before it builds it',
      () async {
        final Directory app = fileSystem.directory('/app')..createSync();
        fileSystem.currentDirectory = app;
        app.childFile('pubspec.yaml').writeAsStringSync('name: app\n');
        final Directory runner = app.childDirectory('tvos').childDirectory('Runner')
          ..createSync(recursive: true);
        runner.childFile('Info.plist').writeAsStringSync(_preSceneInfoPlist);
        runner.childFile('AppDelegate.swift').writeAsStringSync(
          TvosUISceneMigration.originalAppDelegate,
        );
        runner.childDirectory('Base.lproj').childFile('Main.storyboard')
          ..createSync(recursive: true)
          ..writeAsStringSync(_preSceneStoryboard);
        final environment = Environment.test(
          app,
          defines: <String, String>{
            kBuildMode: BuildMode.debug.cliName,
            kTargetPlatform: getNameForTargetPlatform(TargetPlatform.ios),
          },
          artifacts: Artifacts.test(),
          processManager: FakeProcessManager.empty(),
          fileSystem: fileSystem,
          logger: logger,
        );

        // What follows the migration needs an engine and Xcode, which this
        // test has neither of; the migration has to have happened by then.
        try {
          await NativeTvosBundle(_debugSimulator, 'lib/main.dart').build(environment);
        } on Object {
          // Expected: see above.
        }

        expect(
          runner.childFile('AppDelegate.swift').readAsStringSync(),
          TvosUISceneMigration.migratedAppDelegate,
        );
        expect(
          runner.childFile('Info.plist').readAsStringSync(),
          contains('<key>UIApplicationSceneManifest</key>'),
        );
        expect(logger.statusText, contains('Finished migration to UIScene lifecycle'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => FakeProcessManager.empty(),
        Logger: () => logger,
        FeatureFlags: () => TestFeatureFlags(isUISceneMigrationEnabled: true),
        PlistParser: () => _TextPlistParser(fileSystem),
      },
    );
  });
}

const _preSceneInfoPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>FLTAssetsPath</key>
  <string>flutter_assets</string>
  <key>UIMainStoryboardFile</key>
  <string>Main</string>
</dict>
</plist>
''';

const _preSceneStoryboard = '''
<document type="com.apple.InterfaceBuilder.AppleTV.Storyboard" initialViewController="BYZ-38-t0r">
  <scenes>
    <scene sceneID="tne-QT-ifu">
      <objects>
        <viewController id="BYZ-38-t0r"
                        customClass="FlutterViewController"
                        customModule="Flutter" customModuleProvider="framework"
                        sceneMemberID="viewController"/>
      </objects>
    </scene>
  </scenes>
</document>
''';

class _FakeXcode extends Fake implements Xcode {
  @override
  Future<String> sdkLocation(EnvironmentType environmentType) async => '/sdk/AppleTVSimulator.sdk';
}

/// Reads the migration's inserted manifest back from the text, as plutil
/// would from a well-formed plist.
class _TextPlistParser extends Fake implements PlistParser {
  _TextPlistParser(this._fileSystem);

  final FileSystem _fileSystem;

  @override
  T? getValueFromFile<T>(String plistFilePath, String key) {
    final String plist = _fileSystem.file(plistFilePath).readAsStringSync();
    return (plist.contains('<key>$key</key>') ? <String, Object>{} : null) as T?;
  }
}
