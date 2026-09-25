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

  // What `flutter pub get` writes for an app depending on [dependencies],
  // each a package under /plugins, and nothing else: no
  // `.flutter-plugins-dependencies`, which Flutter 3.47 does not write for a
  // project without its own platforms.
  void runPubGet(Directory app, {List<String> dependencies = const <String>['gizmo_tvos']}) {
    final Directory dartTool = app.childDirectory('.dart_tool')..createSync(recursive: true);
    dartTool
        .childFile('package_config.json')
        .writeAsStringSync(
          json.encode(<String, Object>{
            'configVersion': 2,
            'packages': <Map<String, String>>[
              <String, String>{'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
              for (final name in dependencies)
                <String, String>{
                  'name': name,
                  'rootUri': '../../plugins/$name',
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
                'dependencies': dependencies,
                'devDependencies': <String>[],
              },
              for (final name in dependencies)
                <String, Object>{'name': name, 'dependencies': <String>[]},
            ],
          }),
        );
  }

  void writePackage(String name, String pubspec) {
    fileSystem.directory('/plugins/$name').childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(pubspec);
  }

  // Lays out:
  //   /app                  the app, with tvos/ and nothing else unless asked
  //   /plugins/gizmo_tvos   a tvOS plugin with a native and a Dart plugin class
  // and, unless asked otherwise, what `flutter pub get` leaves behind.
  FlutterProject seedApp({bool withIos = false, bool pubGetRan = true, bool isPlugin = false}) {
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

  testUsingContext('says nothing before `pub get` has written a package config', () async {
    await ensureReadyForTvosTooling(seedApp(pubGetRan: false));

    expect(objcRegistrant(), isNot(contains('GizmoTvosPlugin')));
    // Upstream's reader prints "package_config.json does not exist" for
    // this, in red, on the first command after `clean` or a fresh clone.
    expect(logger.errorText, isEmpty);
  }, overrides: overrides());

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
    'writes the tvOS plugin list the Podfile reads when the build refreshes the file',
    () async {
      final FlutterProject project = seedApp();
      // `validateCommand`, which writes `plugins.tvos`.
      await ensureReadyForTvosTooling(project);

      // `TvosBuilder.buildBundle`, before the kernel compile. The tooling only
      // writes `plugins.tvos` again after it, and a build can stop in between.
      await TvosBuilder.writeDartPluginRegistrant(project);

      final Map<String, Object?> deps = pluginsDependencies();
      expect(names((deps['plugins']! as Map<String, Object?>)['tvos']), <String>['gizmo_tvos']);
      expect(names(deps['dependencyGraph']), contains('gizmo_tvos'));
    },
    overrides: overrides(),
  );

  testUsingContext("writes nothing into a plugin package's own directory", () async {
    // What `flutter-tvos test` in a plugin's root ran into: its tvos/ holds
    // the plugin's native sources, and the registrants and plugin lists
    // belong to an app that uses it, such as its example/.
    final FlutterProject plugin = seedApp(isPlugin: true);
    plugin.directory.childDirectory('tvos').childDirectory('Classes').createSync();

    await ensureReadyForTvosTooling(plugin);

    for (final path in <String>[
      '.flutter-plugins-dependencies',
      '.flutter-plugins',
      'tvos/Flutter/GeneratedPluginRegistrant.swift',
      'tvos/Runner/GeneratedPluginRegistrant.m',
      '.dart_tool/flutter_build/dart_plugin_registrant.dart',
    ]) {
      expect(plugin.directory.childFile(path).existsSync(), isFalse, reason: path);
    }
  }, overrides: overrides());

  for (final (String platform, List<String> files, TestFeatureFlags flags)
      in <(String, List<String>, TestFeatureFlags)>[
        ('android', <String>[], TestFeatureFlags()),
        ('ios', <String>[], TestFeatureFlags()),
        ('linux', <String>['CMakeLists.txt'], TestFeatureFlags(isLinuxEnabled: true)),
        ('macos', <String>[], TestFeatureFlags(isMacOSEnabled: true)),
        ('windows', <String>['CMakeLists.txt'], TestFeatureFlags(isWindowsEnabled: true)),
        ('web', <String>['index.html'], TestFeatureFlags(isWebEnabled: true)),
      ]) {
    testUsingContext(
      'leaves the list to `flutter pub get` for a project with $platform/',
      () async {
        final FlutterProject project = seedApp();
        final Directory directory = project.directory.childDirectory(platform)..createSync();
        for (final file in files) {
          directory.childFile(file).createSync();
        }

        await ensureReadyForTvosTooling(project);

        expect(names(pluginsDependencies()['dependencyGraph']), isEmpty);
      },
      overrides: overrides(featureFlags: () => flags),
    );
  }

  testUsingContext('writes the list for a desktop platform Flutter has not enabled', () async {
    final FlutterProject project = seedApp();
    project.directory.childDirectory('macos').createSync();

    await ensureReadyForTvosTooling(project);

    expect(names(pluginsDependencies()['dependencyGraph']), contains('gizmo_tvos'));
  }, overrides: overrides(featureFlags: () => TestFeatureFlags()));

  group('on the build path, after `pub get`,', () {
    testUsingContext('drops a removed plugin from the tvOS list the Podfile reads', () async {
      writePackage('other_tvos', '''
name: other_tvos
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: OtherTvosPlugin
''');
      final FlutterProject project = seedApp();
      runPubGet(project.directory, dependencies: <String>['gizmo_tvos', 'other_tvos']);
      await ensureReadyForTvosTooling(project);

      // gizmo_tvos removed from pubspec.yaml, then `pub get`.
      runPubGet(project.directory, dependencies: <String>['other_tvos']);
      await TvosBuilder.writeDartPluginRegistrant(project);

      expect(names((pluginsDependencies()['plugins']! as Map<String, Object?>)['tvos']), <String>[
        'other_tvos',
      ]);
    }, overrides: overrides());

    testUsingContext(
      'warns, rather than stops the build, on a dependency upstream rejects as a plugin',
      () async {
        // `flutter: plugin:` with neither platforms nor legacy keys: upstream's
        // list refuses it, and a tvOS-only app has always built with it.
        writePackage(
          'odd_package',
          'name: odd_package\nflutter:\n  plugin:\n    unexpected: true\n',
        );
        final FlutterProject project = seedApp();
        runPubGet(project.directory, dependencies: <String>['gizmo_tvos', 'odd_package']);

        await TvosBuilder.writeDartPluginRegistrant(project);

        expect(logger.warningText, contains('Could not refresh .flutter-plugins-dependencies'));
        expect(dartRegistrant(), contains('_PluginRegistrant'));
      },
      overrides: overrides(),
    );

    testUsingContext('warns, rather than stops the build, without a package graph', () async {
      final FlutterProject project = seedApp();
      fileSystem.file('/app/.dart_tool/package_graph.json').deleteSync();

      await TvosBuilder.writeDartPluginRegistrant(project);

      expect(logger.warningText, contains('Could not refresh .flutter-plugins-dependencies'));
    }, overrides: overrides());

    testUsingContext('writes no plugin list into a plugin package', () async {
      // The build path reaches the refresh without ensureReadyForTvosTooling,
      // so the refresh's own plugin check is what keeps upstream's writer out.
      await TvosBuilder.writeDartPluginRegistrant(seedApp(isPlugin: true));

      expect(fileSystem.file('/app/.flutter-plugins-dependencies').existsSync(), isFalse);
    }, overrides: overrides());
  });
}
