// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/runner/flutter_command.dart';

import 'plugin_port.dart';

/// `flutter-tvos plugin …` — umbrella command. Mirrors how upstream Flutter
/// nests sub-tools (`flutter pub …`, `flutter build …`).
///
/// The umbrella itself does not run business logic; it only registers
/// subcommands. Today the only subcommand is `port`. As we add more
/// (`flutter-tvos plugin publish`, `flutter-tvos plugin lint`), they live
/// alongside `port` here.
class TvosPluginCommand extends FlutterCommand {
  // ignore: avoid_unused_constructor_parameters
  TvosPluginCommand({required bool verboseHelp}) {
    // `verboseHelp` is part of the umbrella signature so adding subcommands
    // that DO use it (a future `flutter-tvos plugin lint`, say) doesn't
    // require touching the call site in `executable.dart`. Today only `port`
    // is wired in, and `port` doesn't take verbose-help options of its own.
    addSubcommand(TvosPluginPortCommand());
  }

  @override
  final String name = 'plugin';

  @override
  final String description =
      'Authoring helpers for tvOS plugins. Sub-commands: `port` to scaffold a '
      'federated `*_tvos` package from an existing iOS or macOS plugin.';

  @override
  final String category = 'Tools';

  @override
  Future<FlutterCommandResult> runCommand() async {
    // FlutterCommand routes to subcommands automatically when one is supplied;
    // this body only fires when the user runs `flutter-tvos plugin` with no
    // subcommand. Print the same help banner as `--help` and exit cleanly.
    printUsage();
    return FlutterCommandResult.success();
  }
}
