// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools/src/base/file_system.dart';

/// Writes the two files `pub get` leaves in [dartTool] that tvOS plugin
/// discovery reads: `package_config.json` and `package_graph.json`.
///
/// The app named [appName] sits in the parent of [dartTool]. [packages] maps
/// each other package to its `rootUri`, as pub writes it (absolute `file://`
/// or relative to [dartTool]). The app depends on [dependencies] and
/// [devDependencies] (by default every package is a direct dependency), and
/// [packageDependencies] gives each package's own `dependencies`.
void writePubGetOutput(
  Directory dartTool, {
  String appName = 'app',
  required Map<String, String> packages,
  List<String>? dependencies,
  List<String> devDependencies = const <String>[],
  Map<String, List<String>> packageDependencies = const <String, List<String>>{},
}) {
  dartTool.createSync(recursive: true);
  dartTool
      .childFile('package_config.json')
      .writeAsStringSync(
        json.encode(<String, Object>{
          'configVersion': 2,
          'packages': <Map<String, String>>[
            <String, String>{'name': appName, 'rootUri': '../', 'packageUri': 'lib/'},
            for (final MapEntry<String, String> package in packages.entries)
              <String, String>{'name': package.key, 'rootUri': package.value, 'packageUri': 'lib/'},
          ],
        }),
      );
  dartTool
      .childFile('package_graph.json')
      .writeAsStringSync(
        json.encode(<String, Object>{
          'configVersion': 1,
          'roots': <String>[appName],
          'packages': <Map<String, Object>>[
            <String, Object>{
              'name': appName,
              'dependencies': dependencies ?? packages.keys.toList(),
              'devDependencies': devDependencies,
            },
            for (final String name in packages.keys)
              <String, Object>{
                'name': name,
                'dependencies': packageDependencies[name] ?? const <String>[],
              },
          ],
        }),
      );
}
