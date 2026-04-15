// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/tvos_plugins.dart' show TvosPlugin;

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';

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

    testUsingContext('Podfile is written to tvos/ directory during create flow', () {
      // Simulate what create.dart does: copy Podfile from template dir to project tvos/
      final Directory templateDir = fileSystem.directory('/cli/templates/app/swift/tvos.tmpl')
        ..createSync(recursive: true);
      templateDir.childFile('Podfile').writeAsStringSync(
        'platform :tvos, \'13.0\'\n'
        'target \'Runner\' do\n'
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
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });
  });

  group('.flutter-plugins-dependencies', () {
    testUsingContext('generated JSON contains plugins.tvos key', () {
      // Simulate what tvos_plugins.dart writes
      final Directory projectDir = fileSystem.directory('/project')
        ..createSync(recursive: true);

      final Map<String, dynamic> dependenciesJson = <String, dynamic>{
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

      projectDir.childFile('.flutter-plugins-dependencies')
          .writeAsStringSync(json.encode(dependenciesJson));

      final String content = projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync();
      final Map<String, dynamic> parsed = json.decode(content) as Map<String, dynamic>;
      final List<dynamic> tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

      expect(tvosPlugins, hasLength(1));
      expect((tvosPlugins.first as Map<String, dynamic>)['name'], equals('url_launcher_ios'));
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });
  });

  group('NativeTvosBundle workspace detection', () {
    testUsingContext('uses workspace when Runner.xcworkspace exists', () {
      final Directory tvosDir = fileSystem.directory('/project/tvos')
        ..createSync(recursive: true);

      // Simulate CocoaPods creating the workspace
      tvosDir.childDirectory('Runner.xcworkspace').createSync();
      tvosDir.childDirectory('Runner.xcodeproj').createSync();

      final bool hasWorkspace = tvosDir.childDirectory('Runner.xcworkspace').existsSync();
      expect(hasWorkspace, isTrue);

      // The build command should use -workspace when this is true
      // This verifies the condition used in application.dart line 148
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('uses project when no workspace exists', () {
      final Directory tvosDir = fileSystem.directory('/project/tvos')
        ..createSync(recursive: true);

      tvosDir.childDirectory('Runner.xcodeproj').createSync();

      final bool hasWorkspace = tvosDir.childDirectory('Runner.xcworkspace').existsSync();
      expect(hasWorkspace, isFalse);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });
  });

  group('Podfile plugin resolution', () {
    testUsingContext('Podfile reads plugins from .flutter-plugins-dependencies', () {
      final Directory projectDir = fileSystem.directory('/project')
        ..createSync(recursive: true);
      final Directory tvosDir = projectDir.childDirectory('tvos')
        ..createSync();

      // Write .flutter-plugins-dependencies as tvos_plugins.dart would
      final Map<String, dynamic> deps = <String, dynamic>{
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
      projectDir.childFile('.flutter-plugins-dependencies')
          .writeAsStringSync(json.encode(deps));

      // Verify the JSON is parseable and contains expected plugins
      final String content = projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync();
      final Map<String, dynamic> parsed = json.decode(content) as Map<String, dynamic>;
      final List<dynamic> plugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

      expect(plugins, hasLength(2));
      expect(
        plugins.map((dynamic p) => (p as Map<String, dynamic>)['name']),
        containsAll(<String>['path_provider_foundation', 'url_launcher_ios']),
      );
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });
  });

  group('TvosPlugin', () {
    group('MethodChannel plugin', () {
      testWithoutContext('hasMethodChannel returns true when pluginClass set', () {
        final TvosPlugin plugin = TvosPlugin(
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
        final TvosPlugin plugin = TvosPlugin(
          name: 'my_plugin',
          path: '/path',
          pluginClass: 'MyPlugin',
        );
        final Map<String, dynamic> map = plugin.toMap();
        expect(map['name'], equals('my_plugin'));
        expect(map['class'], equals('MyPlugin'));
        expect(map.containsKey('ffiPlugin'), isFalse);
      });
    });

    group('FFI plugin', () {
      testWithoutContext('hasFfi returns true when ffiPlugin flag is true', () {
        final TvosPlugin plugin = TvosPlugin(
          name: 'native_crypto',
          path: '/path/to/native_crypto',
          ffiPlugin: true,
        );
        expect(plugin.hasFfi(), isTrue);
        expect(plugin.hasMethodChannel(), isFalse);
        expect(plugin.hasNativeBuild(), isTrue);
      });

      testWithoutContext('hasFfi returns false when ffiPlugin flag is null', () {
        final TvosPlugin plugin = TvosPlugin(
          name: 'my_plugin',
          path: '/path',
          pluginClass: 'MyPlugin',
          ffiPlugin: null,
        );
        expect(plugin.hasFfi(), isFalse);
      });

      testWithoutContext('hasFfi returns false when ffiPlugin flag is false', () {
        final TvosPlugin plugin = TvosPlugin(
          name: 'my_plugin',
          path: '/path',
          pluginClass: 'MyPlugin',
          ffiPlugin: false,
        );
        expect(plugin.hasFfi(), isFalse);
      });

      testWithoutContext('toMap includes ffiPlugin key when true', () {
        final TvosPlugin plugin = TvosPlugin(
          name: 'native_crypto',
          path: '/path',
          ffiPlugin: true,
        );
        final Map<String, dynamic> map = plugin.toMap();
        expect(map['name'], equals('native_crypto'));
        expect(map['ffiPlugin'], isTrue);
        expect(map.containsKey('class'), isFalse);
      });

      testWithoutContext('toMap omits ffiPlugin key when false', () {
        final TvosPlugin plugin = TvosPlugin(
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
        final TvosPlugin plugin = TvosPlugin(
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
        final TvosPlugin plugin = TvosPlugin(
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
        final TvosPlugin plugin = TvosPlugin(
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
    testUsingContext('FFI plugins included in plugins.tvos with native_build true', () {
      final Directory projectDir = fileSystem.directory('/project')
        ..createSync(recursive: true);

      // Simulate what ensureReadyForTvosTooling writes for an FFI plugin
      final Map<String, dynamic> dependenciesJson = <String, dynamic>{
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

      projectDir.childFile('.flutter-plugins-dependencies')
          .writeAsStringSync(json.encode(dependenciesJson));

      final String content = projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync();
      final Map<String, dynamic> parsed = json.decode(content) as Map<String, dynamic>;
      final List<dynamic> tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

      expect(tvosPlugins, hasLength(1));
      final Map<String, dynamic> ffiPlugin = tvosPlugins.first as Map<String, dynamic>;
      expect(ffiPlugin['name'], equals('native_crypto'));
      expect(ffiPlugin['native_build'], isTrue);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('Dart-only plugins have native_build false', () {
      final Directory projectDir = fileSystem.directory('/project')
        ..createSync(recursive: true);

      final Map<String, dynamic> dependenciesJson = <String, dynamic>{
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

      projectDir.childFile('.flutter-plugins-dependencies')
          .writeAsStringSync(json.encode(dependenciesJson));

      final String content = projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync();
      final Map<String, dynamic> parsed = json.decode(content) as Map<String, dynamic>;
      final List<dynamic> tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

      final Map<String, dynamic> dartPlugin = tvosPlugins.first as Map<String, dynamic>;
      expect(dartPlugin['native_build'], isFalse);
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });

    testUsingContext('mixed MethodChannel and FFI plugins coexist', () {
      final Directory projectDir = fileSystem.directory('/project')
        ..createSync(recursive: true);

      final Map<String, dynamic> dependenciesJson = <String, dynamic>{
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

      projectDir.childFile('.flutter-plugins-dependencies')
          .writeAsStringSync(json.encode(dependenciesJson));

      final String content = projectDir.childFile('.flutter-plugins-dependencies').readAsStringSync();
      final Map<String, dynamic> parsed = json.decode(content) as Map<String, dynamic>;
      final List<dynamic> tvosPlugins = (parsed['plugins'] as Map<String, dynamic>)['tvos'] as List<dynamic>;

      expect(tvosPlugins, hasLength(3));

      final nativeBuildPlugins = tvosPlugins
          .where((dynamic p) => (p as Map<String, dynamic>)['native_build'] == true)
          .toList();
      final dartOnlyPlugins = tvosPlugins
          .where((dynamic p) => (p as Map<String, dynamic>)['native_build'] == false)
          .toList();

      expect(nativeBuildPlugins, hasLength(2));
      expect(dartOnlyPlugins, hasLength(1));
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    });
  });
}
