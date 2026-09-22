// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression test: plugins in a project created with `--platforms=tvos`.
//
// Flutter 3.47 stopped writing `.flutter-plugins-dependencies` for a project
// with none of Flutter's own platforms, and every tvOS plugin is found through
// that file's `dependencyGraph`. In a tvOS-only project the generated
// registrants came out empty, so every native plugin threw
// MissingPluginException at runtime and no Dart plugin registered.
//
// Where the list is written matters as much as whether: `validateCommand`
// runs before `pub get`, so after `clean` or on a fresh clone the list has to
// be written again once `pub get` has run, before the kernel compile links the
// Dart registrant in.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/tvos_builder.dart';
import 'package:flutter_tvos/tvos_plugins.dart' show ensureReadyForTvosTooling;

import '../src/common.dart';
import '../src/context.dart';
import '../src/fakes.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;
  late BufferLogger logger;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
    logger = BufferLogger.test();
  });

  // What `flutter pub get` writes, and nothing else: no
  // `.flutter-plugins-dependencies`, which Flutter 3.47 does not write for a
  // project without its own platforms.
  void runPubGet(Directory app) {
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

  // Lays out:
  //   /app                  the app, with tvos/ and nothing else unless asked
  //   /plugins/gizmo_tvos   a tvOS plugin with a native and a Dart plugin class
  // and, unless asked otherwise, what `flutter pub get` leaves behind.
  FlutterProject seedApp({
    bool withIos = false,
    bool pubGetRan = true,
    bool isPlugin = false,
  }) {
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
          '    path: ../plugins/gizmo_tvos\n'
          '${isPlugin ? 'flutter:\n  plugin:\n    platforms:\n      tvos:\n        pluginClass: AppPlugin\n' : ''}',
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
        dartPluginClass: GizmoTvos
''');

    if (pubGetRan) {
      runPubGet(app);
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

  String dartRegistrant() => fileSystem
      .file('/app/.dart_tool/flutter_build/dart_plugin_registrant.dart')
      .readAsStringSync();

  Map<Type, Generator> overrides({FeatureFlags Function()? featureFlags}) => <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    Logger: () => logger,
    FeatureFlags: ?featureFlags,
  };

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
    'says nothing before `pub get` has written a package config',
    () async {
      await ensureReadyForTvosTooling(seedApp(pubGetRan: false));

      expect(objcRegistrant(), isNot(contains('GizmoTvosPlugin')));
      // Upstream's reader prints "package_config.json does not exist" for
      // this, in red, on the first command after `clean` or a fresh clone.
      expect(logger.errorText, isEmpty);
    },
    overrides: overrides(),
  );

  testUsingContext(
    'registers Dart plugins on the first build after `clean` or a fresh clone',
    () async {
      final FlutterProject project = seedApp(pubGetRan: false);

      // `validateCommand`, which runs before `pub get`.
      await ensureReadyForTvosTooling(project);
      expect(dartRegistrant(), isNot(contains('GizmoTvos.registerWith()')));

      // `pub get`, which writes no plugin list for this project.
      runPubGet(project.directory);

      // `TvosBuilder.buildBundle`, before the kernel compile links it in.
      await TvosBuilder.writeDartPluginRegistrant(project);

      expect(dartRegistrant(), contains('gizmo_tvos.GizmoTvos.registerWith()'));
    },
    overrides: overrides(),
  );

  testUsingContext(
    'leaves a plugin package alone, as `flutter pub get` does',
    () async {
      await ensureReadyForTvosTooling(seedApp(isPlugin: true));

      expect(names(pluginsDependencies()['dependencyGraph']), isEmpty);
    },
    overrides: overrides(),
  );

  for (final macOSEnabled in <bool>[true, false]) {
    testUsingContext(
      macOSEnabled
          ? 'leaves the list to `flutter pub get` for a desktop platform it has enabled'
          : 'writes the list for a desktop platform Flutter has not enabled',
      () async {
        final FlutterProject project = seedApp();
        project.directory.childDirectory('macos').createSync();

        await ensureReadyForTvosTooling(project);

        expect(
          names(pluginsDependencies()['dependencyGraph']),
          macOSEnabled ? isEmpty : contains('gizmo_tvos'),
        );
      },
      overrides: overrides(
        featureFlags: () => TestFeatureFlags(isMacOSEnabled: macOSEnabled),
      ),
    );
  }
}
