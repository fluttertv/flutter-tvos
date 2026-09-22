// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression test: plugins in a project created with `--platforms=tvos`.
//
// Flutter 3.47 stopped writing `.flutter-plugins-dependencies` for a project
// with none of Flutter's own platforms, and every tvOS plugin is found through
// that file's `dependencyGraph`. In a tvOS-only project the generated
// registrant came out empty, so every native plugin threw
// MissingPluginException at runtime.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/tvos_plugins.dart' show ensureReadyForTvosTooling;

import '../src/common.dart';
import '../src/context.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;
  late BufferLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
    logger = BufferLogger.test();
  });

  // Lays out what `flutter pub get` leaves behind for:
  //   /app                  the app, with tvos/ and nothing else unless asked
  //   /plugins/gizmo_tvos   a tvOS plugin with a native plugin class
  // and no `.flutter-plugins-dependencies`, which Flutter 3.47 does not write
  // for a project without its own platforms.
  FlutterProject seedApp({bool withIos = false, bool pubGetRan = true}) {
    final Directory app = fileSystem.directory('/app')..createSync(recursive: true);
    app.childDirectory('tvos').childDirectory('Runner').createSync(recursive: true);
    if (withIos) {
      app.childDirectory('ios').createSync();
    }
    app
        .childFile('pubspec.yaml')
        .writeAsStringSync(
          'name: app\n'
          'dependencies:\n'
          '  gizmo_tvos:\n'
          '    path: ../plugins/gizmo_tvos\n',
        );

    fileSystem.directory('/plugins/gizmo_tvos').childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: gizmo_tvos
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: GizmoTvosPlugin
''');

    if (pubGetRan) {
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
    }
    return FlutterProject.fromDirectory(app);
  }

  Map<String, Object?> pluginsDependencies() =>
      json.decode(fileSystem.file('/app/.flutter-plugins-dependencies').readAsStringSync())
          as Map<String, Object?>;

  List<String> names(Object? entries) => <String>[
    for (final Object? entry in entries! as List<Object?>)
      (entry! as Map<String, Object?>)['name']! as String,
  ];

  String objcRegistrant() =>
      fileSystem.file('/app/tvos/Runner/GeneratedPluginRegistrant.m').readAsStringSync();

  testUsingContext(
    'registers the plugins of a project with no other platform',
    () async {
      await ensureReadyForTvosTooling(seedApp());

      final Map<String, Object?> deps = pluginsDependencies();
      expect(names(deps['dependencyGraph']), contains('gizmo_tvos'));
      expect(names((deps['plugins']! as Map<String, Object?>)['tvos']), <String>['gizmo_tvos']);
      expect(objcRegistrant(), contains('[GizmoTvosPlugin registerWithRegistrar:'));
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
      Logger: () => logger,
    },
  );

  testUsingContext(
    "leaves the list to `flutter pub get` when the project has one of Flutter's platforms",
    () async {
      await ensureReadyForTvosTooling(seedApp(withIos: true));

      // Flutter writes the file for this project itself, on `pub get`; with
      // none written here, discovery has nothing to go on.
      expect(names(pluginsDependencies()['dependencyGraph']), isEmpty);
      expect(objcRegistrant(), isNot(contains('GizmoTvosPlugin')));
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
      Logger: () => logger,
    },
  );

  testUsingContext(
    'carries on as before when `pub get` has not run yet',
    () async {
      await ensureReadyForTvosTooling(seedApp(pubGetRan: false));

      expect(objcRegistrant(), isNot(contains('GizmoTvosPlugin')));
      expect(logger.traceText, contains('Could not refresh .flutter-plugins-dependencies'));
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
      Logger: () => logger,
    },
  );
}
