// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// tvOS plugins are found from what `pub get` resolved (#99).
//
// They used to be found through the `dependencyGraph` of
// `.flutter-plugins-dependencies`, which Flutter keeps only for backwards
// compatibility (flutter/flutter#48918). Without it, or with it in another
// shape, discovery found no plugins and said nothing: the app built, and every
// plugin call threw MissingPluginException at runtime. Now the package config
// and package graph are read, the way Flutter's own `findPlugins` reads them,
// and the result is the same list, in the same order, that Flutter wrote to
// `dependencyGraph`.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/flutter_plugins.dart' show refreshPluginsList;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/tvos_plugins.dart'
    show discoverTvosSpmPlugins, ensureReadyForTvosTooling, writeTvosDartPluginRegistrant;
import 'package:flutter_tvos/tvos_swift_package_manager.dart' show TvosSpmPlugin;

import '../src/common.dart';
import '../src/context.dart';
import '../src/pub_get.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late BufferLogger logger;
  // A file that cannot be read, as Flutter's error-handling file system
  // reports one: with a ToolExit.
  String? unreadablePath;

  setUp(() {
    unreadablePath = null;
    fileSystem = MemoryFileSystem.test(
      opHandle: (String context, FileSystemOp operation) {
        if (operation == FileSystemOp.read && context == unreadablePath) {
          throwToolExit(
            'Flutter failed to read a file at "$context". '
            'The flutter tool cannot access the file or directory.',
          );
        }
      },
    );
    logger = BufferLogger.test();
  });

  Map<Type, Generator> overrides() => <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
    Logger: () => logger,
  };

  void writePackage(String name, String pubspec, {bool packageSwift = false}) {
    final Directory directory = fileSystem.directory('/pub/$name');
    directory.childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(pubspec);
    if (packageSwift) {
      directory.childDirectory('tvos').childFile('Package.swift')
        ..createSync(recursive: true)
        ..writeAsStringSync('let package = Package(name: "$name")\n');
    }
  }

  // An app, with tvos/ and (unless [withIos] is false) ios/, that depends on:
  //   alpha_tvos      a tvOS plugin that depends on zeta_tvos
  //   zeta_tvos       a tvOS-only plugin, reached only through alpha_tvos
  //   gadget          a plugin for iOS and tvOS
  //   ios_only        a plugin with no tvOS implementation
  //   plain_package   a package that is not a plugin
  // and, under dev_dependencies only, dev_tool_tvos, a Dart-only tvOS plugin.
  //
  // With ios/, `flutter pub get` writes `.flutter-plugins-dependencies`
  // itself, so ensureReadyForTvosTooling does not rewrite it and a test can
  // put whatever it likes there.
  FlutterProject seedApp({bool withIos = true, bool pubGetRan = true}) {
    final Directory app = fileSystem.directory('/app')..createSync(recursive: true);
    app.childDirectory('tvos').childDirectory('Runner').createSync(recursive: true);
    if (withIos) {
      app.childDirectory('ios').createSync();
    }
    app.childFile('pubspec.yaml').writeAsStringSync('name: app\n');

    writePackage('alpha_tvos', '''
name: alpha_tvos
dependencies:
  zeta_tvos: any
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: AlphaTvosPlugin
''', packageSwift: true);
    writePackage('zeta_tvos', '''
name: zeta_tvos
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: ZetaTvosPlugin
''', packageSwift: true);
    writePackage('gadget', '''
name: gadget
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: GadgetPlugin
      tvos:
        pluginClass: GadgetPlugin
''');
    writePackage('ios_only', '''
name: ios_only
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: IosOnlyPlugin
''');
    writePackage('plain_package', 'name: plain_package\n');
    writePackage('dev_tool_tvos', '''
name: dev_tool_tvos
flutter:
  plugin:
    platforms:
      tvos:
        dartPluginClass: DevToolTvos
''');

    if (pubGetRan) {
      writePubGetOutput(
        app.childDirectory('.dart_tool'),
        packages: <String, String>{
          for (final name in <String>[
            'alpha_tvos',
            'zeta_tvos',
            'gadget',
            'ios_only',
            'plain_package',
            'dev_tool_tvos',
          ])
            name: 'file:///pub/$name',
        },
        dependencies: const <String>['alpha_tvos', 'gadget', 'ios_only', 'plain_package'],
        devDependencies: const <String>['dev_tool_tvos'],
        packageDependencies: const <String, List<String>>{
          'alpha_tvos': <String>['zeta_tvos'],
        },
      );
    }
    return FlutterProject.fromDirectory(app);
  }

  // Upstream's order: a plugin after the plugins it depends on, and
  // alphabetical otherwise.
  const expectedTvosPlugins = <String>['dev_tool_tvos', 'gadget', 'zeta_tvos', 'alpha_tvos'];

  File pluginsDependenciesFile() => fileSystem.file('/app/.flutter-plugins-dependencies');

  Map<String, Object?> pluginsDependencies() =>
      json.decode(pluginsDependenciesFile().readAsStringSync()) as Map<String, Object?>;

  List<String> names(Object? entries) => <String>[
    for (final Object? entry in entries! as List<Object?>)
      (entry! as Map<String, Object?>)['name']! as String,
  ];

  List<String> podfilePlugins() =>
      names((pluginsDependencies()['plugins']! as Map<String, Object?>)['tvos']);

  String objcRegistrant() =>
      fileSystem.file('/app/tvos/Runner/GeneratedPluginRegistrant.m').readAsStringSync();

  String dartRegistrant() => fileSystem
      .file('/app/.dart_tool/flutter_build/dart_plugin_registrant.dart')
      .readAsStringSync();

  // The classes registered in GeneratedPluginRegistrant.m, in order.
  List<String> registeredClasses() => <String>[
    for (final RegExpMatch match in RegExp(
      r'\[(\w+) registerWithRegistrar:',
    ).allMatches(objcRegistrant()))
      match.group(1)!,
  ];

  void expectAllPluginsFound() {
    expect(podfilePlugins(), expectedTvosPlugins);
    expect(registeredClasses(), <String>['GadgetPlugin', 'ZetaTvosPlugin', 'AlphaTvosPlugin']);
    expect(dartRegistrant(), contains('dev_tool_tvos.DevToolTvos.registerWith()'));
    expect(
      discoverTvosSpmPlugins(
        FlutterProject.fromDirectory(fileSystem.directory('/app')),
      ).map((TvosSpmPlugin plugin) => plugin.name),
      <String>['zeta_tvos', 'alpha_tvos'],
    );
  }

  testUsingContext('finds the same plugins, in the same order, as the dependencyGraph '
      'Flutter writes', () async {
    final FlutterProject project = seedApp();
    // What `flutter pub get` does for a project with ios/.
    await refreshPluginsList(project);
    final Set<String> tvosPlugins = expectedTvosPlugins.toSet();
    final fromGraph = <String>[
      for (final String name in names(pluginsDependencies()['dependencyGraph']))
        if (tvosPlugins.contains(name)) name,
    ];

    await ensureReadyForTvosTooling(project);

    expect(podfilePlugins(), fromGraph);
    expectAllPluginsFound();
  }, overrides: overrides());

  testUsingContext('finds the plugins when dependencyGraph is missing', () async {
    final FlutterProject project = seedApp();
    pluginsDependenciesFile().writeAsStringSync(
      json.encode(<String, Object>{'plugins': <String, Object>{}}),
    );

    await ensureReadyForTvosTooling(project);

    expectAllPluginsFound();
    // The file is upstream's: no dependencyGraph is made up for it.
    expect(pluginsDependencies().containsKey('dependencyGraph'), isFalse);
  }, overrides: overrides());

  testUsingContext('finds the plugins when dependencyGraph is not a list', () async {
    final FlutterProject project = seedApp();
    pluginsDependenciesFile().writeAsStringSync(
      json.encode(<String, Object>{
        'plugins': <String, Object>{},
        'dependencyGraph': <String, Object>{'alpha_tvos': <String>[]},
      }),
    );

    await ensureReadyForTvosTooling(project);

    expectAllPluginsFound();
  }, overrides: overrides());

  testUsingContext('finds the plugins with no .flutter-plugins-dependencies at all', () async {
    final FlutterProject project = seedApp();

    // The build path, which does not go through ensureReadyForTvosTooling.
    writeTvosDartPluginRegistrant(project);

    expect(dartRegistrant(), contains('dev_tool_tvos.DevToolTvos.registerWith()'));
    expect(discoverTvosSpmPlugins(project).map((TvosSpmPlugin plugin) => plugin.name), <String>[
      'zeta_tvos',
      'alpha_tvos',
    ]);
  }, overrides: overrides());

  // As before: dependencyGraph listed every plugin the app reaches, its
  // dev_dependencies included, and so did every tvOS list made from it.
  testUsingContext('keeps a tvOS plugin that is only a dev dependency', () async {
    final FlutterProject project = seedApp();

    await ensureReadyForTvosTooling(project);

    expect(podfilePlugins(), contains('dev_tool_tvos'));
    expect(dartRegistrant(), contains('dev_tool_tvos.DevToolTvos.registerWith()'));
    expect(logger.traceText, contains('Discovered tvOS plugin: dev_tool_tvos'));
    expect(logger.traceText, contains('(dev dependency)'));
  }, overrides: overrides());

  testUsingContext('finds a tvOS-only plugin the app reaches only through another plugin, '
      'after it', () async {
    await ensureReadyForTvosTooling(seedApp());

    expect(podfilePlugins(), containsAllInOrder(<String>['zeta_tvos', 'alpha_tvos']));
    expect(objcRegistrant(), contains('@import zeta_tvos;'));
  }, overrides: overrides());

  testUsingContext('leaves out packages that are not tvOS plugins', () async {
    await ensureReadyForTvosTooling(seedApp());

    expect(podfilePlugins(), isNot(contains('plain_package')));
    expect(podfilePlugins(), isNot(contains('ios_only')));
    expect(objcRegistrant(), isNot(contains('IosOnlyPlugin')));
  }, overrides: overrides());

  group('stops the build', () {
    testUsingContext('without a package config', () async {
      final FlutterProject project = seedApp(pubGetRan: false);

      expect(() => discoverTvosSpmPlugins(project), throwsToolExit(message: 'pub get'));
      expect(() => writeTvosDartPluginRegistrant(project), throwsToolExit(message: 'pub get'));
    }, overrides: overrides());

    testUsingContext('on a package config that does not parse', () async {
      final FlutterProject project = seedApp();
      fileSystem.file('/app/.dart_tool/package_config.json').writeAsStringSync('{"configVer');

      await expectLater(
        ensureReadyForTvosTooling(project),
        throwsToolExit(message: 'package_config.json'),
      );
    }, overrides: overrides());

    testUsingContext('without a package graph', () async {
      final FlutterProject project = seedApp();
      fileSystem.file('/app/.dart_tool/package_graph.json').deleteSync();

      await expectLater(
        ensureReadyForTvosTooling(project),
        throwsToolExit(message: 'package_graph.json'),
      );
    }, overrides: overrides());

    testUsingContext('on a package graph that names a package the config does not have', () async {
      final FlutterProject project = seedApp();
      final File graph = fileSystem.file('/app/.dart_tool/package_graph.json');
      graph.writeAsStringSync(
        graph
            .readAsStringSync()
            .replaceFirst('"gadget",', '"gadget","missing_package",')
            .replaceFirst(
              '{"name":"plain_package","dependencies":[]}',
              '{"name":"plain_package","dependencies":[]},'
                  '{"name":"missing_package","dependencies":[]}',
            ),
      );

      await expectLater(
        ensureReadyForTvosTooling(project),
        throwsToolExit(message: 'Could not read the package graph'),
      );
    }, overrides: overrides());
  });

  // `validateCommand` runs before `pub get`: on a fresh clone there is
  // nothing to find yet, and the native build writes the registrants after
  // `pub get`.
  group('before pub get', () {
    testUsingContext('leaves the registrants alone without a package config', () async {
      await ensureReadyForTvosTooling(seedApp(pubGetRan: false), beforePubGet: true);

      expect(fileSystem.file('/app/tvos/Runner/GeneratedPluginRegistrant.m').existsSync(), isFalse);
      expect(logger.errorText, isEmpty);
    }, overrides: overrides());

    // A `.dart_tool` from an older SDK, say, which `pub get` is about to
    // rewrite: stopping here would stop a build that `pub get` repairs.
    testUsingContext('leaves the registrants alone without a package graph', () async {
      final FlutterProject project = seedApp();
      fileSystem.file('/app/.dart_tool/package_graph.json').deleteSync();

      await ensureReadyForTvosTooling(project, beforePubGet: true);

      expect(fileSystem.file('/app/tvos/Runner/GeneratedPluginRegistrant.m').existsSync(), isFalse);
      expect(logger.traceText, contains('package_graph.json'));
    }, overrides: overrides());

    testUsingContext('finds the plugins when pub get has already run', () async {
      await ensureReadyForTvosTooling(seedApp(), beforePubGet: true);

      expectAllPluginsFound();
    }, overrides: overrides());

    // Only a package config or graph that cannot be read waits for `pub get`.
    // Anything wrong once they are read stays wrong after it, so it stops
    // the command now, not late in the native build.
    testUsingContext('stops on an error that pub get does not repair', () async {
      final FlutterProject project = seedApp();
      unreadablePath = '/pub/gadget/pubspec.yaml';

      await expectLater(
        ensureReadyForTvosTooling(project, beforePubGet: true),
        throwsToolExit(message: 'cannot access the file'),
      );
      expect(logger.traceText, isNot(contains('not found before pub get')));
    }, overrides: overrides());
  });

  testUsingContext('stops the build without a package config after pub get', () async {
    await expectLater(
      ensureReadyForTvosTooling(seedApp(pubGetRan: false)),
      throwsToolExit(message: 'package_config.json'),
    );
  }, overrides: overrides());
}
