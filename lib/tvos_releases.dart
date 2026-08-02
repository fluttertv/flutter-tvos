// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// A flutter-tvos release: one tagged point that pins a Flutter version, its
/// matching engine artifacts, and the CLI source ported to that version's
/// `flutter_tools` API.
@immutable
class TvosRelease {
  const TvosRelease({
    required this.tag,
    required this.flutterVersion,
    required this.toolVersion,
    this.hash,
  });

  /// The full tag, e.g. `v3.44.7-tvos.1.4.2`.
  final String tag;

  /// The Flutter version this release pins, e.g. `3.44.7`.
  final String flutterVersion;

  /// The flutter-tvos tool version, e.g. `1.4.2`.
  final String toolVersion;

  /// The commit the tag points at, once resolved. Null until [withHash].
  final String? hash;

  /// Matches flutter-tvos release tags, capturing both version halves.
  static final RegExp tagPattern = RegExp(r'^v(\d+\.\d+\.\d+)-tvos\.(\d+\.\d+\.\d+)$');

  /// Parses [tag], or returns null when it is not a release tag. Non-release
  /// tags in the repo (`nightly`, plain `v3.44.1`) are expected and ignored
  /// rather than treated as errors.
  static TvosRelease? parse(String tag) {
    final String trimmed = tag.trim();
    final RegExpMatch? match = tagPattern.firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    return TvosRelease(
      tag: trimmed,
      flutterVersion: match.group(1)!,
      toolVersion: match.group(2)!,
    );
  }

  /// One entry per Flutter version, keeping the first occurrence of each.
  ///
  /// [releases] must be newest-first (`git tag -l --sort=-v:refname`), so the
  /// first occurrence is the newest tool release for that Flutter version —
  /// which is also what a bare selector like `use 3.44.5` resolves to, so the
  /// list shows exactly what the user would get.
  static List<TvosRelease> collapseToNewestPerFlutterVersion(List<TvosRelease> releases) {
    final seen = <String>{};
    final result = <TvosRelease>[];
    for (final TvosRelease release in releases) {
      if (seen.add(release.flutterVersion)) {
        result.add(release);
      }
    }
    return result;
  }

  TvosRelease withHash(String hash) => TvosRelease(
    tag: tag,
    flutterVersion: flutterVersion,
    toolVersion: toolVersion,
    hash: hash,
  );

  @override
  bool operator ==(Object other) =>
      other is TvosRelease && other.tag == tag && other.hash == hash;

  @override
  int get hashCode => Object.hash(tag, hash);

  @override
  String toString() => tag;
}
