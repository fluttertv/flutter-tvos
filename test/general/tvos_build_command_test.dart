// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tvos/commands/build.dart';

import '../src/common.dart';

/// What `flutter-tvos build` offers, and — the load-bearing half — what it does
/// not.
///
/// `TvosBuildCommand` used to extend upstream's `BuildCommand`, which put eleven
/// platform subcommands of its own into the help: aar, apk, appbundle, bundle,
/// ios, ios-framework, ipa, macos, macos-framework, swift-package and web. On a
/// tvOS toolchain several are actively wrong — `build ios` would build an iOS
/// app against an engine compiled for tvOS.
///
/// Nothing else in the suite notices if that inheritance comes back. A Flutter
/// upgrade that reinstates `extends BuildCommand` leaves every other test
/// passing and quietly puts `build apk` back on offer.
void main() {
  test('registers tvos and nothing else', () {
    final command = TvosBuildCommand(logger: BufferLogger.test(), verboseHelp: false);

    expect(command.subcommands.keys, <String>['tvos']);
  });

  test('does not offer upstream platform builds', () {
    final command = TvosBuildCommand(logger: BufferLogger.test(), verboseHelp: false);

    expect(
      command.subcommands.keys,
      isNot(
        anyElement(
          isIn(<String>[
            'apk',
            'appbundle',
            'aar',
            'ios',
            'ios-framework',
            'ipa',
            'macos',
            'macos-framework',
            'swift-package',
            'web',
          ]),
        ),
      ),
    );
  });

  test('does not offer bundle', () {
    // Nominally platform-neutral, actually not: BundleBuilder resolves
    // globals.buildTargets.copyFlutterBundle, and executable.dart registers
    // upstream's BuildTargetsImpl — so it runs upstream's CopyFlutterBundle
    // chain rather than TvosCopyFlutterBundle, producing a bundle with no
    // `*_tvos` plugin registration. --target-platform has no tvos value and
    // defaults to android-arm.
    final command = TvosBuildCommand(logger: BufferLogger.test(), verboseHelp: false);

    expect(command.subcommands.keys, isNot(contains('bundle')));
  });
}
