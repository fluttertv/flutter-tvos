// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tvos/tvos_device_discovery.dart';
import 'package:flutter_tvos/tvos_doctor.dart';

import '../src/common.dart';
import '../src/fakes.dart';

void main() {
  late TvosDeviceDiscovery discovery;

  setUp(() {
    final workflow = TvosWorkflow(
      operatingSystemUtils: FakeOperatingSystemUtils(hostPlatform: HostPlatform.darwin_arm64),
    );
    discovery = TvosDeviceDiscovery(tvosWorkflow: workflow, logger: BufferLogger.test());
  });

  testWithoutContext('supportsPlatform reflects workflow capability', () {
    expect(discovery.supportsPlatform, isTrue);
    expect(discovery.canListAnything, isTrue);
  });

  testWithoutContext('wellKnownIds is empty', () {
    expect(discovery.wellKnownIds, isEmpty);
  });

  testWithoutContext('getDiagnostics returns empty list', () async {
    expect(await discovery.getDiagnostics(), isEmpty);
  });
}
