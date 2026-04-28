// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'package:file/file.dart';
import 'package:flutter_tools/src/project.dart';

void updateLaunchJsonFile(FlutterProject project, Uri observatoryUri) {
  final Directory vscodeDir = project.directory.childDirectory('.vscode');
  if (!vscodeDir.existsSync()) {
    vscodeDir.createSync(recursive: true);
  }

  final File launchJsonFile = vscodeDir.childFile('launch.json');
  // ignore: unused_local_variable — populated for future tvOS attach config injection
  var launchJson = <String, dynamic>{};

  if (launchJsonFile.existsSync()) {
    try {
      final String content = launchJsonFile.readAsStringSync();
      // Extremely basic regex strip for comments. Real environments might use a json5 parser.
      final String stripped = content.replaceAll(RegExp(r'//.*'), '');
      launchJson = jsonDecode(stripped) as Map<String, dynamic>;
    } on Exception {
      // ignore
    }
  }

  // Update logic to inject attach config for tvOS here
}
