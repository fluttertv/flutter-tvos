// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Drift detection for what the package says about itself in four files:
// pubspec.yaml, the podspec, the Swift package manifest and the README.
//
// flutter-tvos builds this plugin through Swift Package Manager, because it
// ships a tvos/Package.swift, so the manifest's platform is the floor an app
// really gets. The podspec's is what a CocoaPods build enforces, and the
// README's is what a reader is told. They have drifted before: the podspec
// and the README moved to tvOS 15.0 while Package.swift stayed at 13, and the
// podspec's version stayed at 1.1.0 for four releases
// (fluttertv/flutter-tvos#110).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // `flutter test` runs with the package root as its working directory.
  String only(String path, RegExp pattern) {
    final List<RegExpMatch> matches =
        pattern.allMatches(File(path).readAsStringSync()).toList();
    expect(matches, hasLength(1),
        reason: '$path should match ${pattern.pattern} exactly once');
    return matches.single.group(1)!;
  }

  const String podspec = 'tvos/flutter_tvos.podspec';

  String version() =>
      only('pubspec.yaml', RegExp(r'^version:\s*(\S+)\s*$', multiLine: true));

  test('the podspec carries the version in pubspec.yaml', () {
    expect(only(podspec, RegExp(r"s\.version\s*=\s*'([^']+)'")), version());
  });

  test('the README installs the version in pubspec.yaml', () {
    expect(
        only('README.md',
            RegExp(r'^\s*flutter_tvos: \^(\S+)\s*$', multiLine: true)),
        version());
  });

  test('Swift Package Manager, CocoaPods and the README state one tvOS floor',
      () {
    // `.tvOS(.v15)` and `.tvOS("15.0")` are the same floor.
    final RegExpMatch platform = RegExp(r'\.tvOS\((?:\.v(\d+)|"([\d.]+)")\)')
        .allMatches(File('tvos/Package.swift').readAsStringSync())
        .single;
    final String swiftPackage = platform.group(2) ?? '${platform.group(1)}.0';

    final String podDeploymentTarget =
        only(podspec, RegExp(r"s\.tvos\.deployment_target\s*=\s*'([^']+)'"));
    expect(only(podspec, RegExp(r"s\.platform\s*=\s*:tvos,\s*'([^']+)'")),
        podDeploymentTarget);
    expect(swiftPackage, podDeploymentTarget,
        reason: 'tvos/Package.swift and the podspec disagree');
    expect(only('README.md', RegExp(r'tvOS ([\d.]+)\+ deployment target')),
        podDeploymentTarget,
        reason: 'the README and the podspec disagree');
  });
}
