// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools/executable.dart' show LoggerFactory;
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/commands/daemon.dart' show MachineOutputLogger, NotifyingLogger;

import 'tvos_device.dart' show TvosDevice;

/// Builds the tool's logger the way stock `flutter` does, with
/// [TvosCategoryRewritingLogger] added to the chain.
///
/// Stock builds its logger with `LoggerFactory.createLogger` (in
/// `flutter_tools/lib/executable.dart`), and parts of stock require the
/// result by type: `daemon` looks up a [NotifyingLogger] with `asLogger`,
/// `run --machine` a [MachineOutputLogger] the same way, and
/// `attach --machine` casts the logger itself to [MachineOutputLogger]. So the
/// mode logger has to be the outermost one, and ours goes directly beneath it.
///
/// The base of the chain (the stdout logger for the platform, with
/// [VerboseLogger] and [PrefixedErrorLogger] when asked for) is stock's own
/// factory called with every mode off. The daemon and machine branches that
/// follow repeat the end of `LoggerFactory.createLogger`, because the factory
/// gives no way to put a logger beneath them, and [MachineOutputLogger] is
/// `final`, so a tvOS subclass of it is not possible either. Stock's third
/// branch, for `widget-preview`, is left out: flutter-tvos has no such
/// command. `test/general/tvos_logger_test.dart` compares the chain this
/// builds with stock's for every combination of flags, and fails if a Flutter
/// update changes stock's branches or their order.
Logger createTvosLogger({
  required Terminal terminal,
  required Stdio stdio,
  required OutputPreferences outputPreferences,
  required bool verbose,
  required bool prefixedErrors,
  required bool machine,
  required bool daemon,
  required bool windows,
  StopwatchFactory stopwatchFactory = const StopwatchFactory(),
}) {
  final Logger base =
      LoggerFactory(
        terminal: terminal,
        stdio: stdio,
        outputPreferences: outputPreferences,
        stopwatchFactory: stopwatchFactory,
      ).createLogger(
        verbose: verbose,
        prefixedErrors: prefixedErrors,
        machine: false,
        daemon: false,
        windows: windows,
        widgetPreviews: false,
      );
  final Logger logger = TvosCategoryRewritingLogger(base);
  if (daemon) {
    return NotifyingLogger(verbose: verbose, parent: logger);
  }
  if (machine) {
    return MachineOutputLogger(parent: logger);
  }
  return logger;
}

/// A [Logger] decorator that rewrites the device-list category column from
/// `(mobile)` to `(tv)` on lines describing tvOS devices.
///
/// Why this exists: Flutter's `Device.descriptions` hard-codes the line as
/// `'${device.displayName} (${device.category})'` and `Category` is a sealed
/// `enum { web, desktop, mobile }` we can't extend without forking the SDK
/// (which the project explicitly forbids — see the "Flutter SDK is never
/// patched" rule). Rewriting the rendered line at the logger boundary is the
/// least invasive way to ship the cosmetic fix.
///
/// The rewrite only fires on lines that contain `• tvos •` (the third column
/// printed by `flutter-tvos devices` for our [TvosDevice], whose
/// `targetPlatformDisplayName` returns `'tvos'`). That makes it impossible
/// to accidentally rewrite an iPhone or anything else that happens to
/// contain the substring `(mobile)`. A line that is a JSON document (what
/// `--machine` output is made of) is never rewritten, even if it matches.
///
/// [createTvosLogger] places it beneath the daemon and machine loggers. In
/// `daemon` mode the [NotifyingLogger] above it turns status lines into
/// daemon events and does not pass them down, so there it rewrites nothing;
/// the daemon's device list is JSON in any case.
class TvosCategoryRewritingLogger extends DelegatingLogger {
  TvosCategoryRewritingLogger(super.delegate);

  // The third column is left-padded with spaces to align the table. Match
  // any whitespace around the bullet.
  static final RegExp _tvosLine = RegExp(r'•\s*tvos\s*•');

  String _rewrite(String message) {
    if (!_tvosLine.hasMatch(message) || _isJson(message)) {
      return message;
    }
    // Replace only the FIRST `(mobile)` — that's the category column. Any
    // later occurrence (e.g. inside a device name) is preserved. Pad with
    // trailing spaces so the next column stays vertically aligned with
    // other rows that still say `(mobile)`. `(mobile)` is 8 chars; `(tv)`
    // is 4, so 4 spaces of padding keeps the table square.
    return message.replaceFirst('(mobile)', '(tv)    ');
  }

  @override
  void printStatus(
    String message, {
    bool? emphasis,
    TerminalColor? color,
    bool? newline,
    int? indent,
    int? hangingIndent,
    bool? wrap,
  }) {
    super.printStatus(
      _rewrite(message),
      emphasis: emphasis,
      color: color,
      newline: newline,
      indent: indent,
      hangingIndent: hangingIndent,
      wrap: wrap,
    );
  }
}

bool _isJson(String message) {
  final String trimmed = message.trimLeft();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    return false;
  }
  try {
    json.decode(trimmed);
    return true;
  } on FormatException {
    return false;
  }
}
