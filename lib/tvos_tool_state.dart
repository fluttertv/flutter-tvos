// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

/// Remembers the release a checkout was switched away from, so `downgrade`
/// knows where to go back to.
///
/// Stored at `.git/flutter-tvos-previous`. Three constraints pick that
/// location and only it satisfies all three: the file must survive
/// `git reset --hard` (so not a tracked path), must survive `shared.sh`
/// deleting `bin/cache` on every version change (so not there), and must be
/// per-checkout — which rules out `~/.config/flutter/`, since users wanting
/// concurrent versions are told to clone twice and a global file would have
/// one clone's downgrade jump to the other's history.
class TvosToolState {
  TvosToolState({required this.repoRoot, required FileSystem fileSystem})
    : _fileSystem = fileSystem;

  /// The flutter-tvos checkout root.
  final String repoRoot;

  final FileSystem _fileSystem;

  File get _file => _fileSystem
      .directory(repoRoot)
      .childDirectory('.git')
      .childFile('flutter-tvos-previous');

  /// The tag switched away from, or null if none was recorded or it cannot be
  /// read.
  String? readPreviousTag() {
    try {
      final File file = _file;
      if (!file.existsSync()) {
        return null;
      }
      final String contents = file.readAsStringSync().trim();
      return contents.isEmpty ? null : contents;
    } on FileSystemException catch (e) {
      globals.printTrace('Could not read the previous flutter-tvos tag: $e');
      return null;
    }
  }

  /// Records [tag]. Never throws: a `.git` that is a file rather than a
  /// directory (worktrees, submodules) costs the user `downgrade`, which is a
  /// far smaller loss than aborting a switch that is otherwise fine.
  void writePreviousTag(String tag) {
    try {
      _file.writeAsStringSync('$tag\n');
    } on FileSystemException catch (e) {
      globals.printTrace('Could not record the previous flutter-tvos tag: $e');
    }
  }
}
