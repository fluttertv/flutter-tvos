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

  // Same category as `upgrade`, so the four version-management commands sit
  // together in `--help` instead of splitting across two sections. 'Tools' is
  // not a FlutterCommandCategory constant at all — the real one is
  // 'Tools & Devices' — so the literal was quietly making its own group.
  @override
  String get category => FlutterCommandCategory.sdk;


  // Listing tags and moving the checkout both need nothing from the artifact
  // cache, and updating it first is actively wrong here: on a fresh clone it
  // downloads hundreds of megabytes to print a list, and `use` would update the
  // cache for the version it is about to leave -- which shared.sh then deletes
  // along with bin/cache on the switch. Stock UpgradeCommand sets this for the
  // same reason.
  @override
  bool get shouldUpdateCache => false;

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

    // Collapsed rows show a Flutter version's *newest* tool release, so a
    // checkout sitting on an older one must still match its row -- otherwise
    // the list marks nothing at all and tells the user they are nowhere. Four
    // of the nine tagged Flutter versions have two tool releases, so that is
    // the ordinary state of anyone who has not upgraded within their line.
    // When the two differ, name what they are actually on.
    final TvosRelease? currentRelease =
        current.tag == null ? null : TvosRelease.parse(current.tag!);

    for (final release in shown) {
      final isCurrent = showAll
          ? release.tag == current.tag
          : currentRelease?.flutterVersion == release.flutterVersion;
      final bool onOlderToolRelease = isCurrent && release.tag != current.tag;
      globals.printStatus(
        '  ${release.flutterVersion.padRight(9)}'
        '${release.tag.padRight(24)}'
        '${isCurrent ? (onOlderToolRelease ? '(current: ${current.tag})' : '(current)') : ''}'
            .trimRight(),
      );
    }

    if (!showAll) {
      globals.printStatus('');
      globals.printStatus('Switch with "flutter-tvos use <version>".');
    }

    return FlutterCommandResult.success();
  }
}
