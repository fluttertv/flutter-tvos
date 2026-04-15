// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/targets/dart_plugin_registrant.dart';

class TvosBuildSystem extends FlutterBuildSystem {
  const TvosBuildSystem({
    required FileSystem fileSystem,
    required Platform platform,
    required Logger logger,
  }) : super(
         fileSystem: fileSystem,
         platform: platform,
         logger: logger,
       );

  @override
  Future<BuildResult> buildIncremental(
    Target target,
    Environment environment,
    BuildResult? previousBuild,
  ) {
    if (target is CompositeTarget) {
      target = CompositeTarget(target.dependencies
          .where((Target target) => target is! DartPluginRegistrantTarget)
          .toList());
    }
    return super.buildIncremental(target, environment, previousBuild);
  }
}
