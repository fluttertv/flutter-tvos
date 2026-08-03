// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
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
    for (final release in releases) {
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

/// A resolved point in the flutter-tvos git history.
@immutable
class TvosVersion {
  const TvosVersion({required this.hash, required this.tag, this.branch});

  /// Full git commit hash.
  final String hash;

  /// The exact release tag at this commit, or null if the commit is not
  /// tagged (e.g. a development checkout on a branch).
  final String? tag;

  /// The branch HEAD was on, or null when it was already detached.
  ///
  /// Kept because the commit alone is not enough to put someone back where they
  /// were: switching detaches, so restoring by hash leaves them on a detached
  /// HEAD at the right commit rather than on their branch.
  final String? branch;

  String get hashShort => hash.length >= 10 ? hash.substring(0, 10) : hash;

  /// Human label: the tag when present, otherwise the short hash.
  String get label => tag ?? hashShort;
}

/// Knows which flutter-tvos releases exist and how to move the checkout
/// between them. Deliberately knows nothing about commands.
class TvosReleases {
  /// [processUtils] is injectable so tests can drive the git queries with a
  /// `FakeProcessManager` without standing up Zone DI; production callers omit
  /// it and fall back to [globals.processUtils].
  TvosReleases({required this.workingDirectory, ProcessUtils? processUtils})
    : _processUtils = processUtils;

  /// The flutter-tvos checkout root — where `.git` and `bin/flutter-tvos` live.
  final String workingDirectory;

  final ProcessUtils? _processUtils;

  ProcessUtils get _git => _processUtils ?? globals.processUtils;

  /// All release tags, newest first.
  ///
  /// The fetch is best-effort by default: with no network we still list what
  /// git already has, which is also still checkout-able. Failing the whole
  /// command because the remote is unreachable would make the tool useless
  /// offline for no gain.
  ///
  /// [requireFetch] inverts that for callers whose answer is only meaningful
  /// against the remote. `upgrade` is the one: "you are already up to date" is
  /// a claim about what exists upstream, and stale local tags cannot support
  /// it — a user offline on an old release would be told they are current.
  /// Listing versions has no such problem, so it keeps the default.
  Future<List<TvosRelease>> list({bool fetch = true, bool requireFetch = false}) async {
    if (fetch) {
      try {
        // --force because a plain `git fetch --tags` refuses to move a tag that
        // already exists locally ("would clobber existing tag") and exits 0
        // while doing so, on stderr nobody reads. A user who fetched a release
        // that was later re-pointed would silently stay on the withdrawn
        // commit while being told they are on the tag. This checkout hits that
        // rejection today, on v1.0.0.
        await _git.run(<String>[
          'git',
          'fetch',
          '--tags',
          '--force',
        ], throwOnError: true, workingDirectory: workingDirectory);
      } on ProcessException catch (e) {
        if (requireFetch) {
          throwToolExit(
            '"git fetch --tags" failed in $workingDirectory, so the list of '
            'available releases cannot be trusted.\n${e.message}',
          );
        }
        // Deliberately does not say "the remote is unreachable": a non-zero
        // exit here means git failed for *some* reason, and asserting the
        // network is at fault turns a dubious-ownership or bad-config error
        // into a confidently wrong diagnosis.
        globals.printWarning(
          '"git fetch --tags" failed in $workingDirectory; showing the releases '
          'already known locally.\n${e.message}',
        );
      }
    }

    RunResult result;
    try {
      result = await _git.run(<String>[
        'git',
        'tag',
        '-l',
        '--sort=-v:refname',
      ], throwOnError: true, workingDirectory: workingDirectory);
    } on ProcessException catch (e) {
      // Without this the exception escapes as an "Oops; flutter has exited
      // unexpectedly" crash report inviting a bug against flutter/flutter,
      // for something as ordinary as a checkout git refuses to read
      // (dubious ownership under a different uid, or no .git at all — which
      // shared.sh explicitly supports via its shasum fallback).
      throwToolExit(
        'Could not list the flutter-tvos releases: "git tag" failed in '
        '$workingDirectory.\n'
        'This must be a git clone of the flutter-tvos repository.\n${e.message}',
      );
    }

    return const LineSplitter()
        .convert(result.stdout.trim())
        .map(TvosRelease.parse)
        .whereType<TvosRelease>()
        .toList();
  }

  /// Resolves a user-supplied selector to a release with its commit.
  ///
  /// Accepts a bare Flutter version (`3.32.8`), which picks the newest tool
  /// release for it, or an exact tag (`v3.32.8-tvos.1.0.0`). Anything else is
  /// an error listing the alternatives — no prefix guessing, because guessing
  /// wrong here silently checks out a version the user did not ask for.
  Future<TvosRelease> resolve(String selector) async {
    final String wanted = selector.trim();
    final List<TvosRelease> releases = await list();
    final selectorIsTag = TvosRelease.parse(wanted) != null;

    TvosRelease? match;
    for (final release in releases) {
      final hit = selectorIsTag
          ? release.tag == wanted
          : release.flutterVersion == wanted;
      if (hit) {
        // The list is newest-first, so the first hit for a bare version is its
        // newest tool release.
        match = release;
        break;
      }
    }

    if (match == null) {
      final String available = TvosRelease.collapseToNewestPerFlutterVersion(releases)
          .map((TvosRelease r) => '  ${r.flutterVersion}')
          .join('\n');
      throwToolExit(
        'No flutter-tvos release matches "$selector".\n\n'
        '${available.isEmpty ? 'No releases are known locally. Check your network connection.' : 'Available versions:\n$available'}',
      );
    }

    return match.withHash(await peelToCommit(match.tag));
  }

  /// Resolves the commit the checkout is currently on, and its exact tag if any.
  Future<TvosVersion> current() async {
    String hash;
    String? tag;
    try {
      final RunResult head = await _git.run(<String>[
        'git',
        'rev-parse',
        '--verify',
        'HEAD',
      ], throwOnError: true, workingDirectory: workingDirectory);
      hash = head.stdout.trim();
    } on ProcessException catch (e) {
      throwToolExit(
        'Unable to determine the current flutter-tvos version: could not read '
        'HEAD in $workingDirectory.\n${e.message}',
      );
    }

    try {
      final RunResult described = await _git.run(<String>[
        'git',
        'describe',
        '--tags',
        '--exact-match',
        'HEAD',
      ], throwOnError: true, workingDirectory: workingDirectory);
      tag = described.stdout.trim();
    } on ProcessException {
      // Not on a tag — a development checkout. Not an error.
      tag = null;
    }

    String? branch;
    try {
      final RunResult symbolic = await _git.run(<String>[
        'git',
        'symbolic-ref',
        '-q',
        '--short',
        'HEAD',
      ], throwOnError: true, workingDirectory: workingDirectory);
      branch = symbolic.stdout.trim();
      if (branch.isEmpty) {
        branch = null;
      }
    } on ProcessException {
      // Already detached. `-q` makes that a quiet non-zero rather than an
      // error, and it is a perfectly ordinary state to switch away from.
      branch = null;
    }

    return TvosVersion(hash: hash, tag: tag, branch: branch);
  }

  Future<bool> hasUncommittedChanges() async {
    // Fail *closed*: this is the only guard before [checkout] moves the tree,
    // so if we
    // cannot determine the tree's status we must not report it clean.
    try {
      final RunResult result = await _git.run(<String>[
        'git',
        'status',
        '-s',
      ], throwOnError: true, workingDirectory: workingDirectory);
      return result.stdout.trim().isNotEmpty;
    } on ProcessException catch (e) {
      throwToolExit(
        'The tool could not verify the status of the flutter-tvos checkout in '
        '$workingDirectory. Ensure git is installed and in your PATH and try '
        'again, or re-run with --force to skip this check.\n${e.message}',
      );
    }
  }

  /// Moves the worktree to [hash], leaving every branch pointer alone.
  ///
  /// `checkout --force --detach`, not `reset --hard`. The worktree result is
  /// identical, but `reset --hard` rewrites whatever branch is checked out —
  /// and the dirty-tree guard cannot protect against that, because
  /// `git status -s` reports worktree state and says nothing about the branch
  /// pointer. A contributor sitting on `main` with unpushed commits passes the
  /// guard cleanly and has those commits left reachable only from the reflog.
  /// Going *backwards* is what makes this bite, which is why `use` and
  /// `downgrade` need it even though `upgrade` has always used `reset --hard`.
  Future<void> checkout(String hash) async {
    try {
      await _git.run(<String>[
        'git',
        'checkout',
        '--force',
        '--detach',
        hash,
      ], throwOnError: true, workingDirectory: workingDirectory);
    } on ProcessException catch (e) {
      throwToolExit(
        'Could not switch the flutter-tvos checkout in $workingDirectory to '
        '$hash.\n${e.message}',
      );
    }
  }

  /// Peels an annotated tag to its commit. `git rev-parse <annotated-tag>`
  /// returns the tag-object SHA, which would never equal a `rev-parse HEAD`
  /// result; `^{commit}` is a no-op for lightweight tags.
  ///
  /// Public so `upgrade` can peel a tag it already holds without paying for a
  /// second `list()` and its `git fetch`.
  Future<String> peelToCommit(String tag) async {
    try {
      final RunResult result = await _git.run(<String>[
        'git',
        'rev-parse',
        '$tag^{commit}',
      ], throwOnError: true, workingDirectory: workingDirectory);
      return result.stdout.trim();
    } on ProcessException catch (e) {
      throwToolExit('Could not resolve the commit for $tag.\n${e.message}');
    }
  }
}
