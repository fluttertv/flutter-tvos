// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/terminal.dart';

/// A [Logger] decorator that rewrites the device-list category column from
/// `(mobile)` to `(tv)` on lines describing tvOS devices.
///
/// Why this exists: Flutter's [Device.descriptions] hard-codes the line as
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
/// contain the substring `(mobile)`.
class TvosCategoryRewritingLogger extends DelegatingLogger {
  TvosCategoryRewritingLogger(super.delegate);

  // The third column is left-padded with spaces to align the table. Match
  // any whitespace around the bullet.
  static final RegExp _tvosLine = RegExp(r'•\s*tvos\s*•');

  String _rewrite(String message) {
    if (!_tvosLine.hasMatch(message)) return message;
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
