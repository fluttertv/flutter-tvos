// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/project.dart';

/// Represents the tvOS sub-project within a Flutter project.
class TvosProject {
  TvosProject.fromFlutter(this.parent);

  final FlutterProject parent;

  String get pluginConfigKey => 'tvos';

  Directory get managedDirectory => _directory.childDirectory('flutter');

  Directory get pluginSymlinkDirectory => _directory.childDirectory('flutter').childDirectory('ephemeral').childDirectory('.symlinks').childDirectory('plugins');

  bool existsSync() => _directory.existsSync();

  Directory get _directory => parent.directory.childDirectory('tvos');

  /// Ensures that all tvOS-specific files and properties are ready.
  Future<void> ensureReadyForPlatformSpecificTooling() async {
    if (!parent.directory.existsSync() || parent.hasExampleApp || parent.isPlugin) {
      return;
    }
    _directory.createSync(recursive: true);
  }
}
