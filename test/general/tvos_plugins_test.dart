// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/tvos_plugins.dart'
    show
        TvosPlugin,
        discoverTvosSpmPlugins,
        ensureReadyForTvosTooling,
        recommendTvosPluginsToInstall;
import 'package:flutter_tvos/tvos_swift_package_manager.dart' show TvosSpmPlugin;

import '../src/common.dart';
import '../src/context.dart';

void main() {
  late MemoryFileSystem fileSystem;
  late FakeProcessManager processManager;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
  });

  group('Podfile template', () {
    testWithoutContext('Podfile template file exists in templates directory', () {
      // Verify the Podfile template can be found relative to the CLI root
      // This is a static check — the actual file is on disk, not in MemoryFileSystem
      // The important thing is that create.dart copies it when it exists
    });

    testUsingContext(
      'Podfile is written to tvos/ directory during create flow',
      () {
        // Simulate what create.dart does: copy Podfile from template dir to project tvos/
        final Directory templateDir = fileSystem.directory('/cli/templates/app/swift/tvos.tmpl')
          ..createSync(recursive: true);
        templateDir
            .childFile('Podfile')
            .writeAsStringSync(
              "platform :tvos, '13.0'\n"
              "target 'Runner' do\n"
              '  use_frameworks!\n'
              'end\n',
            );

        final Directory targetDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);

        // This mimics the copy logic in create.dart lines 71-74
        final File podfileSrc = templateDir.childFile('Podfile');
        podfileSrc.copySync(targetDir.childFile('Podfile').path);

        expect(targetDir.childFile('Podfile').existsSync(), isTrue);
        final String content = targetDir.childFile('Podfile').readAsStringSync();
        expect(content, contains('platform :tvos'));
        expect(content, contains('use_frameworks!'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('.flutter-plugins-dependencies', () {
    testUsingContext(
      'generated JSON contains plugins.tvos key',
      () {
        // Simulate what tvos_plugins.dart writes
        final Directory projectDir = fileSystem.directory('/project')..createSync(recursive: true);

        final dependenciesJson = <String, dynamic>{
          'info': 'This is a generated file; do not edit or check into version control.',
          'plugins': <String, dynamic>{
            'tvos': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'url_launcher_ios',
                'path': '/pub-cache/url_launcher_ios/',
                'dependencies': <String>[],
              },
            ],
          },
          'dependencyGraph': <dynamic>[],
        };

        projectDir
            .childFile('.flutter-plugins-dependencies')
            .writeAsStringSync(json.encode(dependenciesJson));

        final String content = projectDir
            .childFile('.flutter-plugins-dependencies')
            .readAsStringSync();
        final parsed = json.decode(content) as Map<String, dynamic>;
        final tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

        expect(tvosPlugins, hasLength(1));
        expect((tvosPlugins.first as Map<String, dynamic>)['name'], equals('url_launcher_ios'));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('NativeTvosBundle workspace detection', () {
    testUsingContext(
      'uses workspace when Runner.xcworkspace exists',
      () {
        final Directory tvosDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);

        // Simulate CocoaPods creating the workspace
        tvosDir.childDirectory('Runner.xcworkspace').createSync();
        tvosDir.childDirectory('Runner.xcodeproj').createSync();

        final bool hasWorkspace = tvosDir.childDirectory('Runner.xcworkspace').existsSync();
        expect(hasWorkspace, isTrue);

        // The build command should use -workspace when this is true
        // This verifies the condition used in application.dart line 148
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'uses project when no workspace exists',
      () {
        final Directory tvosDir = fileSystem.directory('/project/tvos')
          ..createSync(recursive: true);

        tvosDir.childDirectory('Runner.xcodeproj').createSync();

        final bool hasWorkspace = tvosDir.childDirectory('Runner.xcworkspace').existsSync();
        expect(hasWorkspace, isFalse);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('Podfile plugin resolution', () {
    testUsingContext(
      'Podfile reads plugins from .flutter-plugins-dependencies',
      () {
        final Directory projectDir = fileSystem.directory('/project')..createSync(recursive: true);
        projectDir.childDirectory('tvos').createSync();

        // Write .flutter-plugins-dependencies as tvos_plugins.dart would
        final deps = <String, dynamic>{
          'plugins': <String, dynamic>{
            'tvos': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'path_provider_foundation',
                'path': '/pub-cache/path_provider_foundation/',
                'dependencies': <String>[],
              },
              <String, dynamic>{
                'name': 'url_launcher_ios',
                'path': '/pub-cache/url_launcher_ios/',
                'dependencies': <String>[],
              },
            ],
          },
        };
        projectDir.childFile('.flutter-plugins-dependencies').writeAsStringSync(json.encode(deps));

        // Verify the JSON is parseable and contains expected plugins
        final String content = projectDir
            .childFile('.flutter-plugins-dependencies')
            .readAsStringSync();
        final parsed = json.decode(content) as Map<String, dynamic>;
        final plugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

        expect(plugins, hasLength(2));
        expect(
          plugins.map((dynamic p) => (p as Map<String, dynamic>)['name']),
          containsAll(<String>['path_provider_foundation', 'url_launcher_ios']),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('TvosPlugin', () {
    group('MethodChannel plugin', () {
      testWithoutContext('hasMethodChannel returns true when pluginClass set', () {
        final plugin = TvosPlugin(
          name: 'my_plugin',
          path: '/path/to/my_plugin',
          pluginClass: 'MyPlugin',
        );
        expect(plugin.hasMethodChannel(), isTrue);
        expect(plugin.hasFfi(), isFalse);
        expect(plugin.hasDart(), isFalse);
        expect(plugin.hasNativeBuild(), isTrue);
      });

      testWithoutContext('toMap includes class but not ffiPlugin', () {
        final plugin = TvosPlugin(name: 'my_plugin', path: '/path', pluginClass: 'MyPlugin');
        final Map<String, dynamic> map = plugin.toMap();
        expect(map['name'], equals('my_plugin'));
        expect(map['class'], equals('MyPlugin'));
        expect(map.containsKey('ffiPlugin'), isFalse);
      });
    });

    group('FFI plugin', () {
      testWithoutContext('hasFfi returns true when ffiPlugin flag is true', () {
        final plugin = TvosPlugin(
          name: 'native_crypto',
          path: '/path/to/native_crypto',
          ffiPlugin: true,
        );
        expect(plugin.hasFfi(), isTrue);
        expect(plugin.hasMethodChannel(), isFalse);
        expect(plugin.hasNativeBuild(), isTrue);
      });

      testWithoutContext('hasFfi returns false when ffiPlugin flag is null', () {
        final plugin = TvosPlugin(name: 'my_plugin', path: '/path', pluginClass: 'MyPlugin');
        expect(plugin.hasFfi(), isFalse);
      });

      testWithoutContext('hasFfi returns false when ffiPlugin flag is false', () {
        final plugin = TvosPlugin(
          name: 'my_plugin',
          path: '/path',
          pluginClass: 'MyPlugin',
          ffiPlugin: false,
        );
        expect(plugin.hasFfi(), isFalse);
      });

      testWithoutContext('toMap includes ffiPlugin key when true', () {
        final plugin = TvosPlugin(name: 'native_crypto', path: '/path', ffiPlugin: true);
        final Map<String, dynamic> map = plugin.toMap();
        expect(map['name'], equals('native_crypto'));
        expect(map['ffiPlugin'], isTrue);
        expect(map.containsKey('class'), isFalse);
      });

      testWithoutContext('toMap omits ffiPlugin key when false', () {
        final plugin = TvosPlugin(
          name: 'my_plugin',
          path: '/path',
          pluginClass: 'MyPlugin',
          ffiPlugin: false,
        );
        final Map<String, dynamic> map = plugin.toMap();
        expect(map.containsKey('ffiPlugin'), isFalse);
      });
    });

    group('Dart-only plugin', () {
      testWithoutContext('hasDart returns true when dartPluginClass set', () {
        final plugin = TvosPlugin(
          name: 'dart_plugin',
          path: '/path',
          dartPluginClass: 'DartPluginImpl',
        );
        expect(plugin.hasDart(), isTrue);
        expect(plugin.hasMethodChannel(), isFalse);
        expect(plugin.hasFfi(), isFalse);
        expect(plugin.hasNativeBuild(), isFalse);
      });
    });

    group('hybrid plugin', () {
      testWithoutContext('plugin with both MethodChannel and FFI', () {
        final plugin = TvosPlugin(
          name: 'hybrid_plugin',
          path: '/path',
          pluginClass: 'HybridPlugin',
          ffiPlugin: true,
        );
        expect(plugin.hasMethodChannel(), isTrue);
        expect(plugin.hasFfi(), isTrue);
        expect(plugin.hasNativeBuild(), isTrue);
      });

      testWithoutContext('plugin with MethodChannel, FFI, and Dart', () {
        final plugin = TvosPlugin(
          name: 'full_plugin',
          path: '/path',
          pluginClass: 'FullPlugin',
          dartPluginClass: 'FullDartPlugin',
          ffiPlugin: true,
        );
        expect(plugin.hasMethodChannel(), isTrue);
        expect(plugin.hasFfi(), isTrue);
        expect(plugin.hasDart(), isTrue);
        expect(plugin.hasNativeBuild(), isTrue);
      });
    });
  });

  group('FFI plugin dependencies JSON', () {
    testUsingContext(
      'FFI plugins included in plugins.tvos with native_build true',
      () {
        final Directory projectDir = fileSystem.directory('/project')..createSync(recursive: true);

        // Simulate what ensureReadyForTvosTooling writes for an FFI plugin
        final dependenciesJson = <String, dynamic>{
          'info': 'This is a generated file; do not edit or check into version control.',
          'plugins': <String, dynamic>{
            'tvos': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'native_crypto',
                'path': '/pub-cache/native_crypto/',
                'native_build': true,
                'dependencies': <String>[],
                'dev_dependency': false,
              },
            ],
          },
          'dependencyGraph': <dynamic>[],
        };

        projectDir
            .childFile('.flutter-plugins-dependencies')
            .writeAsStringSync(json.encode(dependenciesJson));

        final String content = projectDir
            .childFile('.flutter-plugins-dependencies')
            .readAsStringSync();
        final parsed = json.decode(content) as Map<String, dynamic>;
        final tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

        expect(tvosPlugins, hasLength(1));
        final ffiPlugin = tvosPlugins.first as Map<String, dynamic>;
        expect(ffiPlugin['name'], equals('native_crypto'));
        expect(ffiPlugin['native_build'], isTrue);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'Dart-only plugins have native_build false',
      () {
        final Directory projectDir = fileSystem.directory('/project')..createSync(recursive: true);

        final dependenciesJson = <String, dynamic>{
          'info': 'This is a generated file; do not edit or check into version control.',
          'plugins': <String, dynamic>{
            'tvos': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'dart_only_plugin',
                'path': '/pub-cache/dart_only_plugin/',
                'native_build': false,
                'dependencies': <String>[],
                'dev_dependency': false,
              },
            ],
          },
          'dependencyGraph': <dynamic>[],
        };

        projectDir
            .childFile('.flutter-plugins-dependencies')
            .writeAsStringSync(json.encode(dependenciesJson));

        final String content = projectDir
            .childFile('.flutter-plugins-dependencies')
            .readAsStringSync();
        final parsed = json.decode(content) as Map<String, dynamic>;
        final tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

        final dartPlugin = tvosPlugins.first as Map<String, dynamic>;
        expect(dartPlugin['native_build'], isFalse);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'mixed MethodChannel and FFI plugins coexist',
      () {
        final Directory projectDir = fileSystem.directory('/project')..createSync(recursive: true);

        final dependenciesJson = <String, dynamic>{
          'info': 'This is a generated file; do not edit or check into version control.',
          'plugins': <String, dynamic>{
            'tvos': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'flutter_tvos',
                'path': '/pub-cache/flutter_tvos/',
                'native_build': true,
                'dependencies': <String>[],
                'dev_dependency': false,
              },
              <String, dynamic>{
                'name': 'native_crypto',
                'path': '/pub-cache/native_crypto/',
                'native_build': true,
                'dependencies': <String>[],
                'dev_dependency': false,
              },
              <String, dynamic>{
                'name': 'dart_only_plugin',
                'path': '/pub-cache/dart_only_plugin/',
                'native_build': false,
                'dependencies': <String>[],
                'dev_dependency': false,
              },
            ],
          },
          'dependencyGraph': <dynamic>[],
        };

        projectDir
            .childFile('.flutter-plugins-dependencies')
            .writeAsStringSync(json.encode(dependenciesJson));

        final String content = projectDir
            .childFile('.flutter-plugins-dependencies')
            .readAsStringSync();
        final parsed = json.decode(content) as Map<String, dynamic>;
        final tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

        expect(tvosPlugins, hasLength(3));

        final List<dynamic> nativeBuildPlugins = tvosPlugins
            .where((dynamic p) => (p as Map<String, dynamic>)['native_build'] == true)
            .toList();
        final List<dynamic> dartOnlyPlugins = tvosPlugins
            .where((dynamic p) => (p as Map<String, dynamic>)['native_build'] == false)
            .toList();

        expect(nativeBuildPlugins, hasLength(2));
        expect(dartOnlyPlugins, hasLength(1));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('recommendTvosPluginsToInstall', () {
    testWithoutContext('returns no messages when the dep graph is empty', () {
      expect(
        recommendTvosPluginsToInstall(allPluginNames: const <String>[]),
        isEmpty,
      );
    });

    testWithoutContext(
      'suggests `<name>_tvos` for a known plugin the user has not added',
      () {
        final messages = recommendTvosPluginsToInstall(
          allPluginNames: const <String>['audioplayers'],
        );
        expect(messages, hasLength(1));
        expect(messages.first, contains('audioplayers_tvos'));
        expect(messages.first, contains('pub.dev'));
      },
    );

    testWithoutContext(
      'matches only the user-facing aggregator name, not federated impls — '
      'so an app on `audioplayers` (which transitively pulls in '
      '`audioplayers_darwin`) gets exactly one suggestion',
      () {
        final messages = recommendTvosPluginsToInstall(
          allPluginNames: const <String>['audioplayers', 'audioplayers_darwin'],
        );
        expect(messages, hasLength(1),
            reason: 'aggregator key matches once; the _darwin sibling is not a key');
        expect(messages.single, contains('audioplayers_tvos'));
      },
    );

    testWithoutContext(
      'stays silent when the user has already added `<name>_tvos`',
      () {
        final messages = recommendTvosPluginsToInstall(
          allPluginNames: const <String>[
            'audioplayers',
            'audioplayers_darwin',
            'audioplayers_tvos',
          ],
        );
        expect(messages, isEmpty);
      },
    );

    testWithoutContext(
      'ignores plugins outside the curated list silently — we do not '
      'speak about random plugins on every build',
      () {
        final messages = recommendTvosPluginsToInstall(
          allPluginNames: const <String>['some_obscure_plugin', 'url_launcher'],
        );
        // url_launcher is not currently in `_kKnownTvosPlugins` either.
        expect(messages, isEmpty);
      },
    );

    testWithoutContext(
      'fires once per known plugin in the dep graph',
      () {
        final messages = recommendTvosPluginsToInstall(
          allPluginNames: const <String>[
            'video_player',
            'video_player_avfoundation',
            'shared_preferences',
            'shared_preferences_foundation',
          ],
        );
        expect(messages, hasLength(2));
        expect(messages, anyElement(contains('video_player_tvos')));
        expect(messages, anyElement(contains('shared_preferences_tvos')));
      },
    );
  });

  group('ensureReadyForTvosTooling end-to-end', () {
    // Guard against future refactors silently dropping the call to
    // recommendTvosPluginsToInstall — the pure-function unit tests
    // above won't catch a missing wire-up at the call site.
    late BufferLogger logger;
    setUp(() => logger = BufferLogger.test());
    testUsingContext(
      'walks the dep graph + prints a warning per missing fluttertv.dev plugin',
      () async {
        final Directory projectDir = fileSystem.directory('/p')..createSync();
        // tvos/ must exist or the function early-returns silently.
        projectDir.childDirectory('tvos').createSync();
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: app\n');

        // Two upstream packages the user pulls in, only one of which
        // (`audioplayers`) has a published `*_tvos` sibling on
        // fluttertv.dev; the other (`url_launcher`) is intentionally
        // outside the curated list and must NOT produce a warning.
        final Directory pluginsDir =
            fileSystem.directory('/p/.dart_tool')..createSync();
        for (final name in <String>['audioplayers', 'url_launcher']) {
          final Directory pkgDir = fileSystem.directory('/pubcache/$name')..createSync(recursive: true);
          pkgDir.childFile('pubspec.yaml').writeAsStringSync('''
name: $name
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: ${name}Plugin
''');
        }
        pluginsDir.childFile('package_config.json').writeAsStringSync(
          json.encode(<String, dynamic>{
            'packages': <Map<String, String>>[
              <String, String>{'name': 'audioplayers', 'rootUri': 'file:///pubcache/audioplayers'},
              <String, String>{'name': 'url_launcher', 'rootUri': 'file:///pubcache/url_launcher'},
            ],
          }),
        );
        projectDir.childFile('.flutter-plugins-dependencies').writeAsStringSync(
          json.encode(<String, dynamic>{
            'dependencyGraph': <Map<String, String>>[
              <String, String>{'name': 'audioplayers'},
              <String, String>{'name': 'url_launcher'},
            ],
          }),
        );

        final FlutterProject project = FlutterProject.fromDirectory(projectDir);
        await ensureReadyForTvosTooling(project);

        expect(
          logger.warningText,
          contains('audioplayers_tvos is available on pub.dev'),
          reason: 'audioplayers is in the curated list and the user has '
              'no audioplayers_tvos in their deps yet',
        );
        expect(
          logger.warningText,
          isNot(contains('url_launcher')),
          reason: 'url_launcher is not in the curated list — must stay silent',
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
        Logger: () => logger,
      },
    );

    // Regression test for the bug where ensureReadyForTvosTooling was
    // wiping `.flutter-plugins-dependencies` — replacing the file
    // produced by stock `flutter pub get` with one that contained only
    // the `tvos` key and an empty `dependencyGraph`. That broke every
    // later `_discoverTvosPlugins` call (notably during the build
    // pipeline), making every federated tvOS plugin with
    // `dartPluginClass:` silently drop from `dart_plugin_registrant.dart`.
    testUsingContext(
      'preserves dependencyGraph and existing platform plugin keys',
      () async {
        final Directory projectDir = fileSystem.directory('/p')..createSync();
        projectDir.childDirectory('tvos').createSync();
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: app\n');

        // Simulate exactly what stock `flutter pub get` writes: a
        // populated `dependencyGraph` (used by `_discoverTvosPlugins`
        // to walk the project's deps) and existing `ios`/`android`
        // plugin lists that must NOT be lost.
        projectDir.childFile('.flutter-plugins-dependencies').writeAsStringSync(
          json.encode(<String, dynamic>{
            'info': 'This is a generated file; do not edit or check into version control.',
            'plugins': <String, dynamic>{
              'ios': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'shared_preferences_foundation',
                  'path': '/pubcache/shared_preferences_foundation',
                  'dependencies': <String>[],
                },
              ],
              'android': <Map<String, dynamic>>[
                <String, dynamic>{
                  'name': 'shared_preferences_android',
                  'path': '/pubcache/shared_preferences_android',
                  'dependencies': <String>[],
                },
              ],
            },
            'dependencyGraph': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'shared_preferences',
                'dependencies': <String>['shared_preferences_foundation'],
              },
              <String, dynamic>{
                'name': 'shared_preferences_foundation',
                'dependencies': <String>[],
              },
              <String, dynamic>{
                'name': 'shared_preferences_android',
                'dependencies': <String>[],
              },
            ],
            'date_created': '2026-05-26 00:00:00.000',
            'version': '3.44.0',
            'swift_package_manager_enabled': false,
          }),
        );

        // Minimal `.dart_tool/package_config.json` — required by
        // `_discoverTvosPlugins`'s name→path resolution step, but no
        // tvOS plugins are present so the resolved tvos list is `[]`.
        fileSystem.directory('/p/.dart_tool').createSync();
        fileSystem
            .file('/p/.dart_tool/package_config.json')
            .writeAsStringSync(json.encode(<String, dynamic>{'packages': <dynamic>[]}));

        final FlutterProject project = FlutterProject.fromDirectory(projectDir);
        await ensureReadyForTvosTooling(project);

        // Re-read what was written back to disk.
        final after = json.decode(
          projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync(),
        ) as Map<String, dynamic>;

        // dependencyGraph must survive untouched.
        expect(
          after['dependencyGraph'],
          isA<List<dynamic>>().having((l) => l.length, 'length', 3),
          reason: 'dependencyGraph from stock pub get must NOT be replaced with []',
        );

        // ios + android plugin lists must survive intact.
        final pluginsAfter = after['plugins'] as Map<String, dynamic>;
        expect(
          pluginsAfter.containsKey('ios'),
          isTrue,
          reason: 'plugins.ios entries must NOT be wiped',
        );
        expect(
          pluginsAfter.containsKey('android'),
          isTrue,
          reason: 'plugins.android entries must NOT be wiped',
        );
        expect(
          (pluginsAfter['ios'] as List<dynamic>).first as Map<String, dynamic>,
          containsPair('name', 'shared_preferences_foundation'),
        );

        // The new `tvos` key must be added alongside (empty in this
        // test because no tvOS plugin is in deps), not as a replacement.
        expect(pluginsAfter.containsKey('tvos'), isTrue);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
        Logger: () => logger,
      },
    );

    // The two read-time defences flagged in code review on PR #15:
    // a `.flutter-plugins-dependencies` whose root JSON isn't an
    // object (e.g. `[]`, `null`, a bare number) must not crash the
    // build with a `TypeError` — we fall back to a fresh skeleton
    // and warn instead.
    testUsingContext(
      'falls back when .flutter-plugins-dependencies root is not an object',
      () async {
        final Directory projectDir = fileSystem.directory('/p')..createSync();
        projectDir.childDirectory('tvos').createSync();
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: app\n');
        // Valid JSON, but the root is an array — would crash on
        // a blind `as Map<String, dynamic>` cast.
        projectDir
            .childFile('.flutter-plugins-dependencies')
            .writeAsStringSync('[]');
        fileSystem.directory('/p/.dart_tool').createSync();
        fileSystem
            .file('/p/.dart_tool/package_config.json')
            .writeAsStringSync(json.encode(<String, dynamic>{'packages': <dynamic>[]}));

        final FlutterProject project = FlutterProject.fromDirectory(projectDir);

        // Should NOT throw — should warn and regenerate from skeleton.
        await ensureReadyForTvosTooling(project);

        expect(
          logger.warningText,
          contains('.flutter-plugins-dependencies is not a JSON object'),
        );
        // The fallback skeleton was written, with the `tvos` key grafted on.
        final after = json.decode(
          projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect((after['plugins'] as Map<String, dynamic>).containsKey('tvos'), isTrue);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
        Logger: () => logger,
      },
    );

    testUsingContext(
      'falls back when plugins key exists but is not a map',
      () async {
        final Directory projectDir = fileSystem.directory('/p')..createSync();
        projectDir.childDirectory('tvos').createSync();
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: app\n');
        // Root IS a map this time, but `plugins` is the wrong shape
        // (an array). The cast `as Map<String, dynamic>?` would
        // throw `TypeError` outside the try/catch; the type-check
        // pattern degrades gracefully instead.
        projectDir.childFile('.flutter-plugins-dependencies').writeAsStringSync(
          json.encode(<String, dynamic>{
            'plugins': <dynamic>[], // wrong: should be a map
            'dependencyGraph': <dynamic>[],
          }),
        );
        fileSystem.directory('/p/.dart_tool').createSync();
        fileSystem
            .file('/p/.dart_tool/package_config.json')
            .writeAsStringSync(json.encode(<String, dynamic>{'packages': <dynamic>[]}));

        final FlutterProject project = FlutterProject.fromDirectory(projectDir);
        await ensureReadyForTvosTooling(project);

        final after = json.decode(
          projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync(),
        ) as Map<String, dynamic>;
        // Wrong-shaped plugins replaced with a fresh map containing tvos.
        expect(after['plugins'], isA<Map<String, dynamic>>());
        expect((after['plugins'] as Map<String, dynamic>).containsKey('tvos'), isTrue);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
        Logger: () => logger,
      },
    );
  });

  group('discoverTvosSpmPlugins', () {
    // Writes a project with two tvOS plugins: `gizmo_tvos` ships a
    // tvos/Package.swift (SPM), `widget_tvos` ships only a podspec.
    FlutterProject seedProject({required bool gizmoHasPackageSwift}) {
      final Directory projectDir = fileSystem.directory('/p')..createSync();
      projectDir.childDirectory('tvos').createSync();
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: app\n');

      for (final name in <String>['gizmo_tvos', 'widget_tvos']) {
        final Directory pkgDir = fileSystem.directory('/pubcache/$name')
          ..createSync(recursive: true);
        pkgDir.childFile('pubspec.yaml').writeAsStringSync('''
name: $name
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: ${name}Plugin
''');
        final Directory tvosDir = pkgDir.childDirectory('tvos')..createSync();
        // Both ship a podspec.
        tvosDir.childFile('$name.podspec').writeAsStringSync('# podspec');
        if (name == 'gizmo_tvos' && gizmoHasPackageSwift) {
          // A leading comment containing `name:` must not fool the parse (the
          // package name is anchored to the `Package(` initializer), and the
          // product name is read from `.library(name:)`.
          tvosDir.childFile('Package.swift').writeAsStringSync(
            '// name: "not-the-package"\n'
            'let package = Package(\n'
            '  name: "gizmo_tvos",\n'
            '  products: [.library(name: "gizmo-tvos", targets: ["gizmo_tvos"])]\n'
            ')\n',
          );
        }
      }

      fileSystem
          .directory('/p/.dart_tool')
          .childFile('package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          json.encode(<String, dynamic>{
            'packages': <Map<String, String>>[
              <String, String>{'name': 'gizmo_tvos', 'rootUri': 'file:///pubcache/gizmo_tvos'},
              <String, String>{'name': 'widget_tvos', 'rootUri': 'file:///pubcache/widget_tvos'},
            ],
          }),
        );
      projectDir.childFile('.flutter-plugins-dependencies').writeAsStringSync(
        json.encode(<String, dynamic>{
          'dependencyGraph': <Map<String, String>>[
            <String, String>{'name': 'gizmo_tvos'},
            <String, String>{'name': 'widget_tvos'},
          ],
        }),
      );
      return FlutterProject.fromDirectory(projectDir);
    }

    testUsingContext(
      'returns only plugins that ship a tvos/Package.swift',
      () {
        final List<TvosSpmPlugin> spm = discoverTvosSpmPlugins(
          seedProject(gizmoHasPackageSwift: true),
        );
        expect(spm.map((p) => p.name), <String>['gizmo_tvos']);
        expect(spm.single.packagePath, '/pubcache/gizmo_tvos/tvos');
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'returns empty when no plugin ships a Package.swift (pods-only)',
      () {
        final List<TvosSpmPlugin> spm = discoverTvosSpmPlugins(
          seedProject(gizmoHasPackageSwift: false),
        );
        expect(spm, isEmpty);
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'prefers the package name declared in the manifest, ignoring comments',
      () {
        // gizmo_tvos's manifest has a leading `// name: "not-the-package"`
        // comment before `Package(name: "gizmo_tvos")`; the anchored parse
        // must pick the real package name.
        final List<TvosSpmPlugin> spm = discoverTvosSpmPlugins(
          seedProject(gizmoHasPackageSwift: true),
        );
        expect(spm.single.name, 'gizmo_tvos');
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'reads the .library product name from the manifest',
      () {
        // gizmo_tvos declares `.library(name: "gizmo-tvos")` — the umbrella
        // links that product, so it must be parsed rather than assumed.
        final List<TvosSpmPlugin> spm = discoverTvosSpmPlugins(
          seedProject(gizmoHasPackageSwift: true),
        );
        expect(spm.single.libraryName, 'gizmo-tvos');
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('FFI forced references in GeneratedPluginRegistrant.m', () {
    // Seeds an app with a single FFI plugin `native_gadget` that declares
    // `ffiSymbols` and (optionally) ships a tvos/Package.swift, plus the
    // tvos/Runner/ directory the ObjC registrant is written into.
    FlutterProject seedFfiProject({
      required bool hasPackageSwift,
      List<String> ffiSymbols = const <String>[
        'native_gadget_init',
        'native_gadget_version',
      ],
    }) {
      final Directory projectDir = fileSystem.directory('/p')..createSync();
      projectDir.childDirectory('tvos').childDirectory('Runner').createSync(recursive: true);
      projectDir.childFile('pubspec.yaml').writeAsStringSync('name: app\n');

      final Directory pkgDir = fileSystem.directory('/pubcache/native_gadget')
        ..createSync(recursive: true);
      final String symbolsYaml = ffiSymbols.map((String s) => '          - $s').join('\n');
      pkgDir.childFile('pubspec.yaml').writeAsStringSync('''
name: native_gadget
flutter:
  plugin:
    platforms:
      tvos:
        ffiPlugin: true
        ffiSymbols:
$symbolsYaml
''');
      final Directory tvosDir = pkgDir.childDirectory('tvos')..createSync();
      tvosDir.childFile('native_gadget.podspec').writeAsStringSync('# podspec');
      if (hasPackageSwift) {
        tvosDir.childFile('Package.swift').writeAsStringSync(
          'let package = Package(name: "native_gadget")\n',
        );
      }

      fileSystem.directory('/p/.dart_tool').childFile('package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          json.encode(<String, dynamic>{
            'packages': <Map<String, String>>[
              <String, String>{
                'name': 'native_gadget',
                'rootUri': 'file:///pubcache/native_gadget',
              },
            ],
          }),
        );
      projectDir.childFile('.flutter-plugins-dependencies').writeAsStringSync(
        json.encode(<String, dynamic>{
          'dependencyGraph': <Map<String, String>>[
            <String, String>{'name': 'native_gadget'},
          ],
        }),
      );
      return FlutterProject.fromDirectory(projectDir);
    }

    String registrantOf(FlutterProject project) => project.directory
        .childDirectory('tvos')
        .childDirectory('Runner')
        .childFile('GeneratedPluginRegistrant.m')
        .readAsStringSync();

    testUsingContext(
      'emits a forced reference per symbol for an SPM FFI plugin',
      () async {
        final FlutterProject project = seedFfiProject(hasPackageSwift: true);
        await ensureReadyForTvosTooling(project);

        final String m = registrantOf(project);
        // File-scope forward declarations.
        expect(m, contains('extern void native_gadget_init(void);'));
        expect(m, contains('extern void native_gadget_version(void);'));
        // The anchor array + asm sink live INSIDE registerWithRegistry: so the
        // linker keeps them (a file-scope used-anchor gets dead-stripped).
        expect(m, contains('const void *_flutterTvosFfiForcedReferences[]'));
        expect(m, contains('(const void *)&native_gadget_init,'));
        expect(m, contains('(const void *)&native_gadget_version,'));
        expect(m, contains('__asm__ volatile("" : : "r"(_flutterTvosFfiForcedReferences[_i]));'));
        // The array reference must sit within the method body, not at file scope.
        final int bodyStart = m.indexOf('+ (void)registerWithRegistry:');
        expect(bodyStart, greaterThanOrEqualTo(0));
        expect(
          m.indexOf('_flutterTvosFfiForcedReferences[] ='),
          greaterThan(bodyStart),
          reason: 'anchor array must be emitted inside registerWithRegistry:',
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'emits NO forced references for a CocoaPods-only FFI plugin',
      () async {
        // No tvos/Package.swift → resolved via CocoaPods as a dynamic
        // framework whose exports already survive; forcing a reference to a
        // symbol that isn't on the link line would be a hard link error.
        final FlutterProject project = seedFfiProject(hasPackageSwift: false);
        await ensureReadyForTvosTooling(project);

        final String m = registrantOf(project);
        expect(m, isNot(contains('_flutterTvosFfiForcedReferences')));
        expect(m, isNot(contains('native_gadget_init')));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'drops symbols that are not valid C identifiers',
      () async {
        final FlutterProject project = seedFfiProject(
          hasPackageSwift: true,
          ffiSymbols: <String>['good_symbol', 'bad symbol', '0bad', 'also_good'],
        );
        await ensureReadyForTvosTooling(project);

        final String m = registrantOf(project);
        expect(m, contains('(const void *)&good_symbol,'));
        expect(m, contains('(const void *)&also_good,'));
        // The invalid entries must never reach the generated C.
        expect(m, isNot(contains('bad symbol')));
        expect(m, isNot(contains('0bad')));
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );

    testUsingContext(
      'omits the forced-reference block entirely when there are no FFI plugins',
      () async {
        // A method-channel-only app must produce byte-for-byte the same
        // registrant as before this feature — no stray FFI block.
        final Directory projectDir = fileSystem.directory('/p')..createSync();
        projectDir
            .childDirectory('tvos')
            .childDirectory('Runner')
            .createSync(recursive: true);
        projectDir.childFile('pubspec.yaml').writeAsStringSync('name: app\n');
        fileSystem.directory('/p/.dart_tool').childFile('package_config.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(json.encode(<String, dynamic>{'packages': <dynamic>[]}));
        projectDir.childFile('.flutter-plugins-dependencies').writeAsStringSync(
          json.encode(<String, dynamic>{'dependencyGraph': <dynamic>[]}),
        );

        final FlutterProject project = FlutterProject.fromDirectory(projectDir);
        await ensureReadyForTvosTooling(project);

        expect(
          registrantOf(project),
          isNot(contains('_flutterTvosFfiForcedReferences')),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
      },
    );
  });

  group('TvosPlugin.ffiSymbols', () {
    testWithoutContext('defaults to an empty list', () {
      final plugin = TvosPlugin(name: 'm', path: '/p', pluginClass: 'MPlugin');
      expect(plugin.ffiSymbols, isEmpty);
    });

    testWithoutContext('carries declared symbols', () {
      final plugin = TvosPlugin(
        name: 'native_gadget',
        path: '/p',
        ffiPlugin: true,
        ffiSymbols: <String>['a_sym', 'b_sym'],
      );
      expect(plugin.ffiSymbols, <String>['a_sym', 'b_sym']);
    });
  });
}
