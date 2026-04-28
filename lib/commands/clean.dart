// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/commands/clean.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

class TvosCleanCommand extends CleanCommand {
  TvosCleanCommand({required super.verbose});

  @override
  Future<FlutterCommandResult> runCommand() async {
    // Run standard Flutter clean first (removes build/, .dart_tool/, etc.)
    final FlutterCommandResult result = await super.runCommand();

    // Clean tvOS-specific build artifacts
    final FlutterProject project = FlutterProject.current();
    final Directory tvosDir = project.directory.childDirectory('tvos');

    if (tvosDir.existsSync()) {
      _cleanDirectory(tvosDir, 'Pods');
      _cleanDirectory(tvosDir, 'Flutter/Flutter.framework');
      _cleanDirectory(tvosDir, 'Flutter/App.framework');
      _cleanDirectory(tvosDir, 'Flutter/flutter_assets');
      _cleanFile(tvosDir, 'Flutter/Generated.xcconfig');
      _cleanFile(tvosDir, 'Podfile.lock');
      _cleanFile(tvosDir, '.symlinks');

      // Remove GeneratedPluginRegistrant (regenerated at build time)
      _cleanFile(tvosDir, 'Flutter/GeneratedPluginRegistrant.swift');

      globals.logger.printStatus('Cleaned tvOS build artifacts.');
    }

    // Clean tvOS xcodebuild output
    final Directory tvosBuildDir = project.directory.childDirectory('build').childDirectory('tvos');
    if (tvosBuildDir.existsSync()) {
      tvosBuildDir.deleteSync(recursive: true);
      globals.logger.printStatus('Removed build/tvos/');
    }

    return result;
  }

  void _cleanDirectory(Directory parent, String relativePath) {
    final Directory dir = parent.fileSystem.directory(
      parent.fileSystem.path.join(parent.path, relativePath),
    );
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
      globals.logger.printTrace('Removed ${dir.path}');
    }
  }

  void _cleanFile(Directory parent, String relativePath) {
    final File file = parent.fileSystem.file(
      parent.fileSystem.path.join(parent.path, relativePath),
    );
    if (file.existsSync()) {
      file.deleteSync();
      globals.logger.printTrace('Removed ${file.path}');
    }
  }
}
