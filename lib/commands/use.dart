// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

import '../tvos_releases.dart';
import '../tvos_tool_state.dart';

/// Runs one bootstrap step in the switched-to checkout, returning its exit
/// code. Injectable so tests do not shell out.
typedef BootstrapRunner = Future<int> Function(List<String> args);

/// `flutter-tvos use <version>` — switches the toolchain to another release.
///
/// Each supported Flutter version is a release line of this repo: the tag
/// carries the CLI source ported to that version's `flutter_tools` API *and*
/// the pinned SDK revision and engine-artifact tag. So switching is a
/// `git reset --hard` to the tag; `bin/internal/shared.sh` then re-checks-out
/// the vendored SDK and recompiles the tool snapshot on the next invocation,
/// with no extra work here.
class TvosUseCommand extends FlutterCommand {
  TvosUseCommand({TvosReleases? releases, TvosToolState? toolState, BootstrapRunner? runBootstrap})
    : _releases = releases,
      _toolState = toolState,
      _runBootstrap = runBootstrap {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Discard uncommitted changes in the flutter-tvos checkout and switch anyway.',
    );
  }

  final TvosReleases? _releases;
  final TvosToolState? _toolState;
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

  TvosToolState get toolState =>
      _toolState ?? TvosToolState(repoRoot: _repoRoot, fileSystem: globals.fs);

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
    return switchTo(argResults!.rest.single);
  }

  /// Everything after argument parsing. `downgrade` reuses this with the tag it
  /// read from the tool state instead of a command-line argument.
  @protected
  Future<FlutterCommandResult> switchTo(String selector) async {
    final TvosRelease target = await releases.resolve(selector);
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

    if (current.tag != null) {
      toolState.writePreviousTag(current.tag!);
    }
    await releases.checkout(target.hash!);

    // Everything past here runs the *target* line's toolchain, which this
    // process cannot become. Shell out, and own the error message: if the
    // target fails to build there is no working `flutter-tvos` left to print
    // it. This is also why the switch does not finish through a `--continue`
    // round-trip the way `upgrade` does — that would put the message in the
    // mouth of the process that just failed to exist.
    // Probe the toolchain before asking it to do anything real. This first
    // invocation is what makes shared.sh re-checkout the SDK, re-run pub get
    // and recompile the snapshot, so it fails exactly when the target line
    // does not build — which is the case the user cannot recover from with
    // this tool. Telling the two apart matters: a precache that fails on a
    // flaky download is not a broken toolchain, and advising someone to reset
    // their checkout over it would be wrong as well as alarming.
    final int bootstrapCode = await _bootstrap(<String>['--version']);
    if (bootstrapCode != 0) {
      _throwStranded(target, current);
    }

    final int code = await _bootstrap(<String>['precache', '--force']);
    if (code != 0) {
      throwToolExit(
        'Switched to ${target.flutterVersion} (${target.tag}) and the toolchain '
        'builds, but downloading the engine artifacts failed.\n'
        'Your checkout is on the new version; finish with:\n'
        '  flutter-tvos precache --force',
      );
    }

    final int doctorCode = await _bootstrap(<String>['doctor']);
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
          <String>[globals.fs.path.join('bin', 'flutter-tvos'), '--no-version-check', ...a],
          workingDirectory: _repoRoot,
          allowReentrantFlutter: true,
          environment: Map<String, String>.of(globals.platform.environment),
        );
    return runner(args);
  }

  /// The checkout has moved but its toolchain will not build, so no
  /// `flutter-tvos` command can run — including the one that would undo this.
  /// The way back has to be a plain git command the user can paste.
  Never _throwStranded(TvosRelease target, TvosVersion previous) {
    final String back = previous.tag ?? previous.hash;
    throwToolExit(
      'Switched to ${target.flutterVersion}, but the toolchain failed to build for it.\n'
      'Your checkout is on ${target.tag}; the flutter-tvos command will not work '
      'until this is resolved.\n\n'
      'To return to the version you came from:\n'
      '  git -C $_repoRoot reset --hard $back',
    );
  }
}
