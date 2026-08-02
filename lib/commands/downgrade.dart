// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import 'use.dart';

/// `flutter-tvos downgrade` — returns to the release switched away from.
///
/// Stock `DowngradeCommand` cannot be forwarded: it sets
/// `workingDirectory = Cache.flutterRoot` and runs `git reset --hard` there,
/// and `Cache.flutterRoot` is the *vendored SDK*. That breaks the
/// `flutter.version` ↔ engine-artifact pin the same way stock `upgrade` would,
/// which is why `TvosUpgradeCommand` exists. The next invocation's
/// `update_flutter()` restores the pin, so the damage is bounded — the user
/// just gets a silent revert plus a multi-minute re-bootstrap for nothing.
///
/// Like stock downgrade, this takes no version argument: it only undoes the
/// last switch. Use `flutter-tvos use <version>` to go somewhere specific.
class TvosDowngradeCommand extends TvosUseCommand {
  TvosDowngradeCommand({super.releases, super.toolState, super.runBootstrap});

  // Getters, not fields: overriding an inherited *field* shadows rather than
  // replaces it, which the analyzer flags and which reads as a bug waiting to
  // happen if TvosUseCommand ever reads its own `name`.
  @override
  String get name => 'downgrade';

  @override
  String get description =>
      'Return to the Flutter version this checkout was switched away from.';

  @override
  String get invocation => 'flutter-tvos downgrade';

  @override
  Future<FlutterCommandResult> runCommand() async {
    // Refuse a version argument, as stock `flutter downgrade` does. Silently
    // ignoring it is the dangerous shape: this command inherits `--force` from
    // TvosUseCommand, so `downgrade 3.32.8 --force` would discard the user's
    // uncommitted work and reset to the *recorded* tag rather than the one they
    // typed. `use` trains people that a version goes on the command line, which
    // makes the mistake likely rather than exotic.
    if (argResults!.rest.isNotEmpty) {
      throwToolExit(
        '"flutter-tvos downgrade" does not take a version; it returns to the '
        'one this checkout was switched away from.\n'
        'To go to a specific version, use:\n'
        '  flutter-tvos use ${argResults!.rest.first}',
        exitCode: 2,
      );
    }

    final String? previous = toolState.readPreviousTag();
    if (previous == null) {
      throwToolExit(
        'There is no previous flutter-tvos version recorded for this checkout, '
        'so there is nothing to go back to.\n'
        'Run "flutter-tvos versions" to see what is available, then '
        '"flutter-tvos use <version>".',
      );
    }
    return switchTo(previous);
  }
}
