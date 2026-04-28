// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';

import 'tvos_project.dart';

class TvosApp extends ApplicationPackage {
  TvosApp({required super.id, required this.projectDirectory});

  final Directory projectDirectory;

  @override
  String get name => projectDirectory.basename;

  /// Returns the path to the app bundle for the given build mode and architecture.
  String bundlePath(BuildMode buildMode, {bool isSimulator = false}) {
    final configuration = (buildMode == BuildMode.debug) ? 'Debug' : 'Release';
    final platformSuffix = isSimulator ? 'appletvsimulator' : 'appletvos';

    // This matches the SYMROOT set in application.dart (build/tvos)
    return globals.fs.path.join(
      projectDirectory.parent.path,
      'build',
      'tvos',
      '$configuration-$platformSuffix',
      'Runner.app',
    );
  }

  static Future<TvosApp?> fromTvosProject(TvosProject project) async {
    if (!project.existsSync()) {
      return null;
    }

    // Try to find the bundle identifier in the project.pbxproj file
    final File projectFile = project.parent.directory
        .childDirectory('tvos')
        .childDirectory('Runner.xcodeproj')
        .childFile('project.pbxproj');

    String? bundleId;
    if (projectFile.existsSync()) {
      final String content = projectFile.readAsStringSync();
      final regex = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(.*?);');
      final Iterable<Match> matches = regex.allMatches(content);
      if (matches.isNotEmpty) {
        // Use the first match (usually the app's bundle ID)
        bundleId = matches.first.group(1)?.trim();
        if (bundleId != null &&
            bundleId.length >= 2 &&
            bundleId.startsWith('"') &&
            bundleId.endsWith('"')) {
          bundleId = bundleId.substring(1, bundleId.length - 1);
        }
      }
    }

    return TvosApp(
      id: bundleId ?? 'com.example.${project.parent.directory.basename}',
      projectDirectory: project.parent.directory.childDirectory('tvos'),
    );
  }
}

class TvosApplicationPackageFactory extends ApplicationPackageFactory {
  @override
  Future<ApplicationPackage?> getPackageForPlatform(
    TargetPlatform platform, {
    BuildInfo? buildInfo,
    File? applicationBinary,
  }) async {
    final FlutterProject project = FlutterProject.current();
    final tvosProject = TvosProject.fromFlutter(project);

    if (tvosProject.existsSync()) {
      return TvosApp.fromTvosProject(tvosProject);
    }
    return null;
  }
}
