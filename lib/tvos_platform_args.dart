// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Makes `--platforms=tvos` a first-class option for `flutter-tvos create`.
///
/// Upstream Flutter's `--platforms` multi-option has a hardcoded `allowed:`
/// whitelist (`ios, android, macos, windows, linux, web`) enforced by the
/// argument parser *before* any command code runs, so `tvos` would be
/// rejected outright. We don't patch Flutter, so this rewrites argv at our
/// own entrypoint — the one seam we fully control:
///
///   * `--platforms=tvos`            → `--tvos-only` (no `--platforms`)
///     `TvosCreateCommand` self-generates the shared app + `tvos/`; it
///     never runs upstream `flutter create`, so no iOS/Android app is
///     scaffolded — nothing is created then deleted.
///   * `--platforms=tvos,ios,...`    → `--platforms=ios,...`
///     (drop `tvos`; the other platforms are scaffolded normally and
///     `tvos/` is added alongside.)
///   * no `tvos` / no `create`       → returned unchanged.
///
/// Pure function: no I/O, so it unit-tests directly.
List<String> expandTvosPlatformArgs(List<String> args) {
  if (!args.contains('create')) {
    return args;
  }

  final List<String> withoutPlatforms = <String>[];
  final Set<String> requested = <String>{};
  bool sawPlatforms = false;

  for (var i = 0; i < args.length; i++) {
    final String a = args[i];
    if (a == '--platforms') {
      sawPlatforms = true;
      if (i + 1 < args.length) {
        requested.addAll(_split(args[i + 1]));
        i++; // consume the value token
      }
      continue; // drop; re-added below
    }
    if (a.startsWith('--platforms=')) {
      sawPlatforms = true;
      requested.addAll(_split(a.substring('--platforms='.length)));
      continue; // drop; re-added below
    }
    withoutPlatforms.add(a);
  }

  if (!sawPlatforms || !requested.contains('tvos')) {
    // Nothing tvOS-specific to do — leave the original argv untouched so
    // non-tvos `create` behaviour is byte-for-byte unchanged.
    return args;
  }

  final List<String> others =
      requested.where((String p) => p != 'tvos').toList();
  if (others.isEmpty) {
    // Pure tvOS: self-generated, no upstream flutter create at all.
    return <String>[...withoutPlatforms, '--tvos-only'];
  }
  // tvos + siblings: scaffold the siblings normally; tvos/ added alongside.
  return <String>[...withoutPlatforms, '--platforms=${others.join(',')}'];
}

Iterable<String> _split(String csv) =>
    csv.split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty);
