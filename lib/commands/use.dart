// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tvos_releases.dart';

/// Runs one bootstrap step in the switched-to checkout, returning its exit
/// code. Injectable so tests do not shell out.
typedef BootstrapRunner = Future<int> Function(List<String> args);

/// `flutter-tvos use <version>` — switches the toolchain to another release.
///
/// Each supported Flutter version is a release line of this repo: the tag
/// carries the CLI source ported to that version's `flutter_tools` API *and*
/// the pinned SDK revision and engine-artifact tag. So switching is a
/// `git checkout --force --detach` to the tag; `bin/internal/shared.sh` then re-checks-out
/// the vendored SDK and recompiles the tool snapshot on the next invocation,
/// with no extra work here.
class TvosUseCommand extends FlutterCommand {
  TvosUseCommand({TvosReleases? releases, BootstrapRunner? runBootstrap})
    : _releases = releases,
      _runBootstrap = runBootstrap {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Discard uncommitted changes in the flutter-tvos checkout and switch anyway.',
    );
  }

  final TvosReleases? _releases;
  final BootstrapRunner? _runBootstrap;

  /// Cache.flutterRoot points at the vendored `flutter/` SDK; its parent is the
  /// flutter-tvos repo root, where `.git` and `bin/flutter-tvos` live. Prefer
  /// the injected [_releases]' own working directory when present, so a test
  /// that supplies a fake repo root sees that root echoed back in messages
  /// rather than the real checkout `testUsingContext` seeds `Cache.flutterRoot`
  /// with.
  String get _repoRoot =>
      _releases?.workingDirectory ?? globals.fs.directory(Cache.flutterRoot).parent.path;

  TvosReleases get releases => _releases ?? TvosReleases(workingDirectory: _repoRoot);


  @override
  String get name => 'use';

  @override
  String get description =>
      'Switch this flutter-tvos checkout to another Flutter version. '
      'Run "flutter-tvos versions" to see what is available.';

  // Same category as `upgrade`, so the four version-management commands sit
  // together in `--help` instead of splitting across two sections. 'Tools' is
  // not a FlutterCommandCategory constant at all — the real one is
  // 'Tools & Devices' — so the literal was quietly making its own group.
  @override
  String get category => FlutterCommandCategory.sdk;

  @override
  String get invocation => 'flutter-tvos use <version>';

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults!.rest.length != 1) {
      throwToolExit(
        'Specify exactly one version, e.g. "flutter-tvos use 3.32.8".\n'
        'Run "flutter-tvos versions" to see what is available.',
      );
    }

    final TvosRelease target = await releases.resolve(argResults!.rest.single);
    final TvosVersion current = await releases.current();

    // Before the dirty-tree guard on purpose: someone with local edits who
    // names the version they are already on should not be refused an
    // operation that would do nothing.
    if (current.tag == target.tag) {
      globals.printStatus('flutter-tvos is already on ${target.flutterVersion} (${target.tag}).');
      return FlutterCommandResult.success();
    }

    if (!boolArg('force') && await releases.hasUncommittedChanges()) {
      throwToolExit(
        'Your flutter-tvos checkout in $_repoRoot has uncommitted changes.\n'
        'Commit or stash them first, or re-run with --force to discard them '
        'and switch anyway.',
      );
    }

    globals.printStatus(
      'Switching flutter-tvos ${current.label} -> ${target.flutterVersion} (${target.tag})...',
    );

    await releases.checkout(target.hash!);

    _printRecovery(current);

    // Everything past here runs the *target* line's toolchain, which this
    // process cannot become. Shell out, and own the error message: if the
    // target fails to build there is no working `flutter-tvos` left to print
    // it. That is also why the switch does not finish through a `--continue`
    // round-trip the way `upgrade` does — it would put the message in the
    // mouth of the process that just failed to exist.
    //
    // The probe runs first because this invocation is what makes shared.sh
    // re-checkout the SDK, re-run pub get and recompile the snapshot. It is
    // also network-heavy, so a non-zero exit does NOT prove the source is
    // broken — the message says what was observed and lets the user decide.
    final int bootstrapCode = await _bootstrapOrStranded(<String>['--version'], target);
    if (bootstrapCode != 0) {
      throwToolExit(
        'Switched to ${target.flutterVersion} (${target.tag}), but setting up its '
        'toolchain did not finish.\n'
        'Its first run fetches the Flutter SDK and runs "pub get", so a network '
        'failure and a release line that does not build look the same here.\n'
        'Retry with "flutter-tvos --version". If that keeps failing, return to '
        'where you were with the command above.',
      );
    }

    final int code = await _bootstrapOrStranded(<String>['precache', '--force'], target);
    if (code != 0) {
      throwToolExit(
        'Switched to ${target.flutterVersion} (${target.tag}) and the toolchain '
        'builds, but downloading the engine artifacts failed.\n'
        'Your checkout is on the new version and "flutter-tvos" works, so you can '
        'finish with "flutter-tvos precache --force", or go back with '
        '"flutter-tvos downgrade".',
      );
    }

    final int doctorCode = await _bootstrapOrStranded(<String>['doctor'], target);
    if (doctorCode != 0) {
      globals.printWarning(
        'Switched to ${target.flutterVersion}, but "flutter-tvos doctor" reported problems.',
      );
    }

    globals.printStatus('');
    globals.printStatus('Now on Flutter ${target.flutterVersion} (${target.tag}).');
    return FlutterCommandResult.success();
  }

  Future<int> _bootstrap(List<String> args) {
    final BootstrapRunner runner =
        _runBootstrap ??
        (List<String> a) => globals.processUtils.stream(
          <String>[
            globals.fs.path.join('bin', 'flutter-tvos'),
            '--no-color',
            '--no-version-check',
            ...a,
          ],
          workingDirectory: _repoRoot,
          allowReentrantFlutter: true,
          environment: Map<String, String>.of(globals.platform.environment),
        );
    return runner(args);
  }

  /// [_bootstrap], but a process that cannot even be spawned is reported as the
  /// stranding it is rather than as a raw exception dump.
  ///
  /// `processUtils.stream` throws instead of returning non-zero when the
  /// executable is missing or not executable — which is precisely what an old
  /// or half-written release line looks like. Without this the checkout has
  /// already moved and the one message carrying the way back never prints.
  Future<int> _bootstrapOrStranded(List<String> args, TvosRelease target) async {
    try {
      return await _bootstrap(args);
    } on ProcessException catch (e) {
      throwToolExit(
        'Switched to ${target.flutterVersion} (${target.tag}), but '
        '"bin/flutter-tvos" could not be run there.\n$e\n'
        'Return to where you were with the command above.',
      );
    }
  }

  /// Prints the way back, as a single unwrapped line, the moment the checkout
  /// moves.
  ///
  /// Unconditional and early by design. What follows takes minutes, and a
  /// Ctrl-C or a dropped session would otherwise kill this process before it
  /// could say anything — in the one state where the user has no working
  /// `flutter-tvos` left to ask.
  ///
  /// `wrap: false` is not cosmetic. printStatus word-wraps to the terminal
  /// width, and a wrapped `git … --hard <tag>` pastes as a `git checkout
  /// --force --detach` with no revision: git fails, or worse succeeds against
  /// a stray argument, and the user believes they recovered when they did not.
  void _printRecovery(TvosVersion previous) {
    final String back = previous.tag ?? previous.hash;
    globals.printStatus('');
    globals.printStatus('If anything goes wrong, return to where you were with:');
    globals.printStatus(
      '  git -C $_repoRoot checkout --force --detach $back',
      wrap: false,
    );
    globals.printStatus('');
  }
}
