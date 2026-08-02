// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/build_targets.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/build_targets.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tvos/executable.dart';

import '../src/common.dart';
import '../src/context.dart';

/// What `flutter-tvos` does and does not expose.
///
/// The absence of `channel` is the load-bearing half. Stock `ChannelCommand`
/// operates on `Cache.flutterRoot` — the vendored SDK — and moving it breaks
/// the `flutter.version` to engine-artifact pin, the same hazard that made
/// `upgrade` and `downgrade` need tvOS-specific overrides. If a merge ever
/// re-adds it, every other test in this suite still passes.
void main() {
  /// Several commands read `globals` in their constructors, so the list cannot
  /// be produced outside a context.
  final overrides = <Type, Generator>{
    BuildSystem: () => FlutterBuildSystem(
      fileSystem: globals.fs,
      logger: globals.logger,
      platform: globals.platform,
    ),
    BuildTargets: () => const BuildTargetsImpl(),
  };

  List<FlutterCommand> build() => tvosCommands(verbose: false, verboseHelp: false);

  Set<String> buildNames() => build().map((FlutterCommand c) => c.name).toSet();

  testUsingContext('registers the version-selection commands', () {
    expect(buildNames(), containsAll(<String>['versions', 'use', 'upgrade', 'downgrade']));
  }, overrides: overrides);

  testUsingContext('does not register channel', () {
    expect(buildNames(), isNot(contains('channel')));
  }, overrides: overrides);

  testUsingContext('downgrade is the tvOS override, not the stock command', () {
    final FlutterCommand downgrade = build().firstWhere(
      (FlutterCommand c) => c.name == 'downgrade',
    );
    expect(downgrade.runtimeType.toString(), 'TvosDowngradeCommand');
  }, overrides: overrides);

  testUsingContext('upgrade is the tvOS override, not the stock command', () {
    final FlutterCommand upgrade = build().firstWhere((FlutterCommand c) => c.name == 'upgrade');
    expect(upgrade.runtimeType.toString(), 'TvosUpgradeCommand');
  }, overrides: overrides);

  testUsingContext('registers no command twice', () {
    final List<FlutterCommand> commands = build();
    expect(buildNames().length, commands.length);
  }, overrides: overrides);
}
