// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tvos/tvos_build_info.dart';

import '../src/common.dart';

void main() {
  testWithoutContext('TvosBuildInfo.sdkName returns appletvsimulator for simulator builds', () {
    const TvosBuildInfo buildInfo = TvosBuildInfo(
      BuildInfo.debug,
      targetArch: 'arm64',
      simulator: true,
    );
    expect(buildInfo.sdkName, equals('appletvsimulator'));
  });

  testWithoutContext('TvosBuildInfo.sdkName returns appletvos for device builds', () {
    const TvosBuildInfo buildInfo = TvosBuildInfo(
      BuildInfo.debug,
      targetArch: 'arm64',
      simulator: false,
    );
    expect(buildInfo.sdkName, equals('appletvos'));
  });

  testWithoutContext('TvosBuildInfo.destination returns simulator destination', () {
    const TvosBuildInfo buildInfo = TvosBuildInfo(
      BuildInfo.debug,
      targetArch: 'arm64',
      simulator: true,
    );
    expect(buildInfo.destination, equals('generic/platform=tvOS Simulator'));
  });

  testWithoutContext('TvosBuildInfo.destination returns device destination', () {
    const TvosBuildInfo buildInfo = TvosBuildInfo(
      BuildInfo.release,
      targetArch: 'arm64',
      simulator: false,
    );
    expect(buildInfo.destination, equals('generic/platform=tvOS'));
  });

  testWithoutContext('TvosBuildInfo defaults to non-simulator', () {
    const TvosBuildInfo buildInfo = TvosBuildInfo(
      BuildInfo.debug,
      targetArch: 'arm64',
    );
    expect(buildInfo.simulator, isFalse);
    expect(buildInfo.sdkName, equals('appletvos'));
  });
}
