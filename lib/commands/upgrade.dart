// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/upgrade.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

/// `flutter-tvos upgrade` — upgrades the flutter-tvos toolchain itself to the
/// latest released version.
///
/// Unlike stock `flutter upgrade` (which moves the vendored Flutter SDK toward
/// upstream and would break our pinned `flutter.version` ↔ engine-artifact
/// contract), this command upgrades the **flutter-tvos checkout** to its
/// newest release tag. A release tag bumps the pinned Flutter version *and* the
/// matching engine artifacts together, so after the upgrade `precache` pulls
/// the correct engine for the new pin.
///
/// Release tags follow `v<flutter-version>-tvos.<tool-version>`, e.g.
/// `v3.44.1-tvos.1.2.0`. The newest tag by version order is the target.
///
/// Mirrors the structure of stock `UpgradeCommand` / `UpgradeCommandRunner`.
class TvosUpgradeCommand extends UpgradeCommand {
  TvosUpgradeCommand({required super.verboseHelp});

  @override
  String get description =>
      'Upgrade the flutter-tvos toolchain to the latest released version.';

  @override
  Future<FlutterCommandResult> runCommand() {
    final commandRunner = TvosUpgradeCommandRunner();
    // Cache.flutterRoot points at the vendored `flutter/` SDK; its parent is
    // the flutter-tvos repo root (where `.git` and `bin/flutter-tvos` live).
    commandRunner.workingDirectory =
        stringArg('working-directory') ?? globals.fs.directory(Cache.flutterRoot).parent.path;
    return commandRunner.runCommand(
      force: boolArg('force'),
      continueFlow: boolArg('continue'),
      testFlow: stringArg('working-directory') != null,
      verifyOnly: boolArg('verify-only'),
    );
  }
}

/// A resolved point in the flutter-tvos git history.
@immutable
class TvosVersion {
  const TvosVersion({required this.hash, required this.tag});

  /// Full git commit hash.
  final String hash;

  /// The exact release tag at this commit, or null if the commit is not
  /// tagged (e.g. a development checkout on a branch).
  final String? tag;

  String get hashShort => hash.length >= 10 ? hash.substring(0, 10) : hash;

  /// Human label: the tag when present, otherwise the short hash.
  String get label => tag ?? hashShort;
}

@visibleForTesting
class TvosUpgradeCommandRunner {
  /// [processUtils] is injectable so tests can drive the git queries with a
  /// `FakeProcessManager` without standing up Zone DI; production callers omit
  /// it and fall back to [globals.processUtils].
  TvosUpgradeCommandRunner({ProcessUtils? processUtils}) : _processUtils = processUtils;

  final ProcessUtils? _processUtils;

  ProcessUtils get _git => _processUtils ?? globals.processUtils;

  String? workingDirectory;

  /// Matches flutter-tvos release tags: `v<flutter>-tvos.<tool>`, e.g.
  /// `v3.44.1-tvos.1.2.0`.
  static final RegExp releaseTagPattern = RegExp(r'^v\d+\.\d+\.\d+-tvos\.\d+\.\d+\.\d+$');

  /// Selects the newest release tag from [tags], which are expected to be
  /// pre-sorted newest-first (`git tag -l --sort=-v:refname`). Non-release
  /// tags are ignored. Returns null when no release tag is present.
  @visibleForTesting
  static String? latestReleaseTag(List<String> tags) {
    for (final tag in tags) {
      if (releaseTagPattern.hasMatch(tag.trim())) {
        return tag.trim();
      }
    }
    return null;
  }

  Future<FlutterCommandResult> runCommand({
    required bool force,
    required bool continueFlow,
    required bool testFlow,
    required bool verifyOnly,
  }) async {
    if (!continueFlow) {
      await runCommandFirstHalf(force: force, testFlow: testFlow, verifyOnly: verifyOnly);
    } else {
      await runCommandSecondHalf();
    }
    return FlutterCommandResult.success();
  }

  Future<void> runCommandFirstHalf({
    required bool force,
    required bool testFlow,
    required bool verifyOnly,
  }) async {
    final TvosVersion upstream = await fetchLatestReleaseVersion();
    final TvosVersion current = await fetchCurrentVersion();

    if (current.hash == upstream.hash) {
      globals.printStatus('flutter-tvos is already up to date at ${upstream.label}.');
      return;
    }

    globals.printStatus('A new version of flutter-tvos is available.\n');
    globals.printStatus('  Latest:  ${upstream.label}', emphasis: true);
    globals.printStatus('  Current: ${current.label}\n');

    if (verifyOnly) {
      globals.printStatus('To upgrade now, run "flutter-tvos upgrade".');
      return;
    }

    // Guard against silently discarding local changes with `git reset --hard`.
    if (!force && await _hasUncommittedChanges()) {
      throwToolExit(
        'Your flutter-tvos checkout in $workingDirectory has uncommitted changes.\n'
        'Commit or stash them first, or re-run with --force to discard them and '
        'upgrade anyway.',
      );
    }

    globals.printStatus(
      'Upgrading flutter-tvos to ${upstream.label} from ${current.label} in $workingDirectory...',
    );
    await attemptReset(upstream.hash);
    if (!testFlow) {
      await flutterUpgradeContinue();
    }
  }

  /// Fetches tags from the remote and resolves the newest release tag.
  Future<TvosVersion> fetchLatestReleaseVersion() async {
    String tag;
    String hash;
    try {
      await _git.run(
        <String>['git', 'fetch', '--tags'],
        throwOnError: true,
        workingDirectory: workingDirectory,
      );
      final RunResult result = await _git.run(
        <String>['git', 'tag', '-l', '--sort=-v:refname'],
        throwOnError: true,
        workingDirectory: workingDirectory,
      );
      final List<String> tags = const LineSplitter().convert(result.stdout.trim());
      final String? latest = latestReleaseTag(tags);
      if (latest == null) {
        throwToolExit(
          'Unable to upgrade flutter-tvos: no release tags '
          '(v<flutter>-tvos.<version>) were found.\n'
          'Make sure your flutter-tvos checkout tracks the upstream repository.',
        );
      }
      tag = latest;
      // Peel to the underlying commit with `^{commit}`. Release tags may be
      // annotated (e.g. v3.44.1-tvos.1.2.0), and `git rev-parse <annotated-tag>`
      // returns the tag-object SHA, not the commit SHA. fetchCurrentVersion
      // reads `git rev-parse HEAD` (a commit SHA), so without peeling the
      // "already up to date" comparison would never match on a checkout sitting
      // exactly on an annotated release. `^{commit}` is a no-op for lightweight
      // tags.
      final RunResult revParse = await _git.run(
        <String>['git', 'rev-parse', '$tag^{commit}'],
        throwOnError: true,
        workingDirectory: workingDirectory,
      );
      hash = revParse.stdout.trim();
    } on ProcessException catch (e) {
      throwToolExit(
        'Unable to upgrade flutter-tvos: could not query git tags.\n${e.message}',
      );
    }
    return TvosVersion(hash: hash, tag: tag);
  }

  /// Resolves the commit the checkout is currently on, and its exact tag if any.
  Future<TvosVersion> fetchCurrentVersion() async {
    String hash;
    String? tag;
    try {
      final RunResult head = await _git.run(
        <String>['git', 'rev-parse', '--verify', 'HEAD'],
        throwOnError: true,
        workingDirectory: workingDirectory,
      );
      hash = head.stdout.trim();
    } on ProcessException catch (e) {
      throwToolExit(
        'Unable to upgrade flutter-tvos: could not determine the current '
        'revision of $workingDirectory.\n${e.message}',
      );
    }
    // An exact tag is best-effort; a development checkout legitimately has none.
    try {
      final RunResult describe = await _git.run(
        <String>['git', 'describe', '--exact-match', '--tags', 'HEAD'],
        workingDirectory: workingDirectory,
      );
      if (describe.exitCode == 0) {
        tag = describe.stdout.trim();
      }
    } on ProcessException {
      tag = null;
    }
    return TvosVersion(hash: hash, tag: tag);
  }

  Future<bool> _hasUncommittedChanges() async {
    // Fail *closed*: this is the only guard before `git reset --hard`, so if we
    // cannot determine the tree's status we must not report it clean. Mirrors
    // stock Flutter's UpgradeCommandRunner.hasUncommittedChanges.
    try {
      final RunResult result = await _git.run(
        <String>['git', 'status', '-s'],
        throwOnError: true,
        workingDirectory: workingDirectory,
      );
      return result.stdout.trim().isNotEmpty;
    } on ProcessException catch (e) {
      throwToolExit(
        'The tool could not verify the status of the flutter-tvos checkout in '
        '$workingDirectory. This may be due to git not being installed or an '
        'unexpected error. Ensure git is installed and in your PATH and try '
        'again, or re-run with --force to skip this check.\n${e.message}',
      );
    }
  }

  Future<void> attemptReset(String newRevision) async {
    try {
      await _git.run(
        <String>['git', 'reset', '--hard', newRevision],
        throwOnError: true,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (e) {
      throwToolExit(e.message, exitCode: e.errorCode);
    }
  }

  /// Re-invokes `flutter-tvos upgrade --continue` so the *new* version of the
  /// tool runs the second half (precache / pub get / doctor).
  Future<void> flutterUpgradeContinue() async {
    final int code = await globals.processUtils.stream(
      <String>[
        globals.fs.path.join('bin', 'flutter-tvos'),
        'upgrade',
        '--continue',
        '--no-version-check',
      ],
      workingDirectory: workingDirectory,
      allowReentrantFlutter: true,
      environment: Map<String, String>.of(globals.platform.environment),
    );
    if (code != 0) {
      throwToolExit(
        'flutter-tvos was upgraded to the new release, but finishing the upgrade '
        '(precache / doctor) failed. Your checkout is on the new version; re-run '
        '"flutter-tvos precache --force" and "flutter-tvos doctor" to complete it.',
        exitCode: code,
      );
    }
  }

  Future<void> runCommandSecondHalf() async {
    globals.persistentToolState?.setShouldRedisplayWelcomeMessage(false);
    // No explicit `pub get` here: the second half is re-invoked through
    // `bin/flutter-tvos`, whose bootstrap (`bin/internal/shared.sh`) already
    // runs a plain `flutter pub get` against the tool repo when the snapshot
    // stamp changes — which it always does after the reset to a new release.
    // Running `pub get --upgrade` again would only churn `pubspec.lock`, which
    // then trips the uncommitted-changes guard on the next upgrade.
    await precacheArtifacts();
    await runDoctor();
    globals.persistentToolState?.setShouldRedisplayWelcomeMessage(true);
  }

  /// Re-downloads the tvOS engine artifacts that match the new pinned version.
  Future<void> precacheArtifacts() async {
    globals.printStatus('');
    globals.printStatus('Upgrading engine...');
    final int code = await globals.processUtils.stream(
      <String>[
        globals.fs.path.join('bin', 'flutter-tvos'),
        '--no-color',
        '--no-version-check',
        'precache',
        '--force',
      ],
      workingDirectory: workingDirectory,
      allowReentrantFlutter: true,
      environment: Map<String, String>.of(globals.platform.environment),
    );
    if (code != 0) {
      throwToolExit(
        'The flutter-tvos checkout was upgraded, but re-downloading the tvOS '
        'engine artifacts for the new version failed. Re-run '
        '"flutter-tvos precache --force" once your network is available.',
        exitCode: code,
      );
    }
  }

  Future<void> runDoctor() async {
    globals.printStatus('');
    globals.printStatus('Running flutter-tvos doctor...');
    await globals.processUtils.stream(
      <String>[
        globals.fs.path.join('bin', 'flutter-tvos'),
        '--no-version-check',
        'doctor',
      ],
      workingDirectory: workingDirectory,
      allowReentrantFlutter: true,
    );
  }
}
