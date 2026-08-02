// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tvos_releases.dart';

/// `flutter-tvos versions` — lists the Flutter versions this toolchain can be
/// switched to, marking the one in use.
class TvosVersionsCommand extends FlutterCommand {
  TvosVersionsCommand({TvosReleases? releases}) : _releases = releases {
    argParser.addFlag(
      'all',
      negatable: false,
      help: 'Show every release tag instead of one line per Flutter version.',
    );
  }

  final TvosReleases? _releases;

  /// Cache.flutterRoot points at the vendored `flutter/` SDK; its parent is the
  /// flutter-tvos repo root, where `.git` and `bin/flutter-tvos` live.
  TvosReleases get releases =>
      _releases ??
      TvosReleases(workingDirectory: globals.fs.directory(Cache.flutterRoot).parent.path);

  @override
  final String name = 'versions';

  @override
  final String description =
      'List the Flutter versions this flutter-tvos checkout can be switched to.';

  @override
  final String category = 'Tools';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final List<TvosRelease> all = await releases.list();
    final TvosVersion current = await releases.current();

    if (all.isEmpty) {
      globals.printStatus(
        'No flutter-tvos releases are known. If this checkout was cloned '
        'without tags, run "git fetch --tags".',
      );
      return FlutterCommandResult.success();
    }

    final bool showAll = boolArg('all');
    final List<TvosRelease> shown = showAll
        ? all
        : TvosRelease.collapseToNewestPerFlutterVersion(all);

    for (final TvosRelease release in shown) {
      final bool isCurrent = release.tag == current.tag;
      globals.printStatus(
        '  ${release.flutterVersion.padRight(9)}'
        '${release.tag.padRight(24)}'
        '${isCurrent ? '(current)' : ''}'.trimRight(),
      );
    }

    if (!showAll) {
      globals.printStatus('');
      globals.printStatus('Switch with "flutter-tvos use <version>".');
    }

    return FlutterCommandResult.success();
  }
}
