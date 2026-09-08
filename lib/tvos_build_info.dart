// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/build_info.dart';

/// Build configuration for tvOS targets.
class TvosBuildInfo {
  const TvosBuildInfo(
    this.buildInfo, {
    required this.targetArch,
    this.simulator = false,
    this.codesign = true,
  });

  final BuildInfo buildInfo;
  final String targetArch;

  /// Whether to build for the tvOS Simulator.
  final bool simulator;

  /// Whether to sign a physical-device build.
  ///
  /// False disables signing entirely, producing a binary that compiles and
  /// links but cannot be installed on hardware. That is the point: a CI machine
  /// with no certificate can still prove the app builds and that the symbols it
  /// needs made it into the Mach-O. Ignored for simulator builds, which are
  /// never signed against a team.
  final bool codesign;

  /// The Xcode SDK name for this build configuration.
  String get sdkName => simulator ? 'appletvsimulator' : 'appletvos';

  /// The Xcode destination for this build configuration.
  String get destination => simulator ? 'generic/platform=tvOS Simulator' : 'generic/platform=tvOS';
}
