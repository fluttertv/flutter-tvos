// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/create_base.dart';
import 'package:flutter_tools/src/template.dart';

/// Renders the bundled `tvos/` Xcode runner template into
/// [projectDirPath]. Extracted from `TvosCreateCommand` so the plugin
/// porter can drop a `tvos/` runner into a copied example app too,
/// without re-running `flutter create`.
///
/// No-op when the template is missing or `tvos/` already exists.
/// [developmentTeam] is only relevant for on-device signing (left null
/// for example apps).
Future<void> renderTvosRunner({
  required FileSystem fileSystem,
  required Logger logger,
  required TemplateRenderer templateRenderer,
  required String projectDirPath,
  required String name,
  required String organization,
  String? developmentTeam,
}) async {
  final String tvosTemplatePath = fileSystem.path.join(
    Cache.flutterRoot!,
    '..',
    'templates',
    'app',
    'swift',
    'tvos.tmpl',
  );
  final Directory templateDir = fileSystem.directory(tvosTemplatePath);
  final Directory targetDir =
      fileSystem.directory(projectDirPath).childDirectory('tvos');
  if (!templateDir.existsSync() || targetDir.existsSync()) {
    return;
  }

  final String tvosIdentifier =
      CreateBase.createUTIIdentifier(organization, name);
  logger.printStatus('Generating tvOS runner...');
  final Template template = Template(
    templateDir,
    templateDir,
    fileSystem: fileSystem,
    logger: logger,
    templateRenderer: templateRenderer,
  );
  template.render(targetDir, <String, Object>{
    'organization': organization,
    'projectName': name,
    'titleCaseProjectName':
        name.substring(0, 1).toUpperCase() + name.substring(1),
    'tvosIdentifier': tvosIdentifier,
    'withRootModule': true,
    'withPlatformChannelPluginHook': true,
    'withPluginHook': true,
    'withFfiPluginHook': true,
    'withFfiPackage': true,
    'withSwiftPackageManager': true,
    'swiftPackageManagerEnabled': true,
    'cocoapodsEnabled': true,
    'pluginClass': 'DummyPlugin',
    'pluginClassSnakeCase': 'dummy_plugin',
    'pluginProjectName': 'dummy_plugin',
    'hasTvosDevelopmentTeam':
        developmentTeam != null && developmentTeam.isNotEmpty,
    'tvosDevelopmentTeam': developmentTeam ?? '',
  });
  final File podfileSrc = templateDir.childFile('Podfile');
  if (podfileSrc.existsSync()) {
    podfileSrc.copySync(targetDir.childFile('Podfile').path);
  }
}
