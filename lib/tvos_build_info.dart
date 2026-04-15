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
  });

  final BuildInfo buildInfo;
  final String targetArch;

  /// Whether to build for the tvOS Simulator.
  final bool simulator;

  /// The Xcode SDK name for this build configuration.
  String get sdkName => simulator ? 'appletvsimulator' : 'appletvos';

  /// The Xcode destination for this build configuration.
  String get destination => simulator
      ? 'generic/platform=tvOS Simulator'
      : 'generic/platform=tvOS';
}
