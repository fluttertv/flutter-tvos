// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression test for https://github.com/fluttertv/flutter-tvos/issues/29:
// plugin discovery must work when the tvOS app is a member of a Dart pub
// workspace (`resolution: workspace`).
//
// Under a workspace, `dart pub get` writes package_config.json only at the
// workspace root's .dart_tool/; each member gets a workspace_ref.json that
// points back to the root. Reading the member's own
// .dart_tool/package_config.json (as pre-fix flutter-tvos did) finds nothing,
// so the build silently registers no plugins. The fix walks up to the root's
// package_config.json and resolves each relative rootUri against it.

import 'dart:convert';

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tvos/tvos_plugins.dart' show discoverTvosSpmPlugins;
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

  // Lays out a pub workspace:
  //   /ws                     workspace root  (package_config.json lives here)
  //   /ws/app                 tvOS app        (a workspace member)
  //   /ws/plugins/gizmo_tvos  federated tvOS plugin shipping a Package.swift
  //
  // The member app's own .dart_tool/ holds only workspace_ref.json, exactly
  // as `dart pub get` writes it — no package_config.json.
  FlutterProject seedWorkspace() {
    final Directory app = fileSystem.directory('/ws/app')
      ..createSync(recursive: true);
    app.childDirectory('tvos').createSync();
    app.childFile('pubspec.yaml').writeAsStringSync(
      'name: app\nresolution: workspace\n',
    );

    final Directory plugin = fileSystem.directory('/ws/plugins/gizmo_tvos')
      ..createSync(recursive: true);
    plugin.childFile('pubspec.yaml').writeAsStringSync('''
name: gizmo_tvos
flutter:
  plugin:
    platforms:
      tvos:
        pluginClass: GizmoTvosPlugin
''');
    final Directory pluginTvos = plugin.childDirectory('tvos')..createSync();
    pluginTvos.childFile('gizmo_tvos.podspec').writeAsStringSync('# podspec');
    pluginTvos.childFile('Package.swift').writeAsStringSync(
      'let package = Package(\n'
      '  name: "gizmo_tvos",\n'
      '  products: [.library(name: "gizmo-tvos", targets: ["gizmo_tvos"])]\n'
      ')\n',
    );

    // package_config.json hoisted to the workspace root, with rootUris
    // *relative to the root's .dart_tool/* — the shape pub writes for a
    // workspace, not absolute file:// URIs.
    fileSystem.directory('/ws/.dart_tool').childFile('package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        json.encode(<String, dynamic>{
          'configVersion': 2,
          'packages': <Map<String, String>>[
            <String, String>{'name': 'app', 'rootUri': '../app'},
            <String, String>{
              'name': 'gizmo_tvos',
              'rootUri': '../plugins/gizmo_tvos',
            },
          ],
        }),
      );

    // The member's .dart_tool has only a workspace_ref.json pointer — no
    // package_config.json. This is what breaks the naive single-dir read.
    app.childDirectory('.dart_tool').childFile('workspace_ref.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(json.encode(<String, String>{'workspaceRoot': '../..'}));

    app.childFile('.flutter-plugins-dependencies').writeAsStringSync(
      json.encode(<String, dynamic>{
        'dependencyGraph': <Map<String, String>>[
          <String, String>{'name': 'gizmo_tvos'},
        ],
      }),
    );

    return FlutterProject.fromDirectory(app);
  }

  testUsingContext(
    'discovers a workspace-member app\'s tvOS plugins via the hoisted '
    'package_config.json (issue #29)',
    () {
      final List<TvosSpmPlugin> spm = discoverTvosSpmPlugins(seedWorkspace());
      // Pre-fix this was empty: the member's .dart_tool has no
      // package_config.json, so no plugin path resolved and nothing registered.
      expect(spm.map((p) => p.name), <String>['gizmo_tvos']);
      expect(spm.single.packagePath, '/ws/plugins/gizmo_tvos/tvos');
    },
    overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => processManager,
    },
  );
}
