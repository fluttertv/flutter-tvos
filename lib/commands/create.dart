// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/create.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/ios/code_signing.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/template.dart';

import 'tvos_app_scaffold.dart';
import 'tvos_runner.dart';

class TvosCreateCommand extends CreateCommand {
  TvosCreateCommand({required super.verboseHelp}) {
    // Internal only. Users say `--platforms=tvos`; the argv shim in
    // executable.dart rewrites that to this flag because upstream
    // Flutter's `--platforms` parser rejects `tvos`. Hidden so it never
    // appears in `--help` as a thing to type.
    argParser.addFlag('tvos-only', negatable: false, hide: true);
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    final String projectDirPath = argResults!.rest.first;
    final String name =
        stringArg('project-name') ?? globals.fs.path.basename(projectDirPath);
    final String templateType = stringArg('template') ?? 'app';

    // tvOS-only app: build the shared scaffold + tvos/ ourselves. We do
    // NOT delegate to upstream `flutter create` (it can't target tvos and
    // would force an unwanted iOS/Android app), so nothing is generated
    // then stripped — the project is tvOS-only by construction.
    if (boolArg('tvos-only') && templateType != 'plugin') {
      globals.logger.printStatus('Generating tvOS-only project...');
      TvosAppScaffold(globals.fs).write(projectDirPath, name);
      await _renderTvosRunner(projectDirPath, name);
      globals.logger.printStatus(
        'Created tvOS-only project (shared app + tvos/, no other platforms).',
      );
      return FlutterCommandResult.success();
    }

    // Standard path: real `flutter create` (all/requested platforms),
    // then add `tvos/` alongside.
    final FlutterCommandResult exitCode = await super.runCommand();
    if (exitCode != FlutterCommandResult.success()) {
      return exitCode;
    }
    if (templateType == 'plugin') {
      return _createPlugin(projectDirPath, name);
    }
    return _createApp(projectDirPath, name);
  }

  Future<FlutterCommandResult> _createApp(String projectDirPath, String name) async {
    await _renderTvosRunner(projectDirPath, name);
    return FlutterCommandResult.success();
  }

  /// Renders the `tvos/` Xcode runner into [projectDirPath], detecting the
  /// org and (for on-device signing) a development team the way
  /// `flutter create` does. Delegates the template work to the shared
  /// [renderTvosRunner] so the plugin porter can reuse it.
  Future<void> _renderTvosRunner(String projectDirPath, String name) async {
    final String organization = await getOrganization();
    final String? developmentTeam = await getCodeSigningIdentityDevelopmentTeam(
      processManager: globals.processManager,
      platform: globals.platform,
      logger: globals.logger,
      config: globals.config,
      terminal: globals.terminal,
      fileSystem: globals.fs,
      fileSystemUtils: globals.fsUtils,
      plistParser: globals.plistParser,
    );
    await renderTvosRunner(
      fileSystem: globals.fs,
      logger: globals.logger,
      templateRenderer: globals.templateRenderer,
      projectDirPath: projectDirPath,
      name: name,
      organization: organization,
      developmentTeam: developmentTeam,
    );
  }

  Future<FlutterCommandResult> _createPlugin(String projectDirPath, String name) async {
    final String pluginTemplatePath = globals.fs.path.join(
      Cache.flutterRoot!,
      '..',
      'templates',
      'plugin',
      'swift',
      'tvos.tmpl',
    );
    final Directory templateDir = globals.fs.directory(pluginTemplatePath);
    final Directory targetDir = globals.fs.directory(projectDirPath).childDirectory('tvos');

    if (!templateDir.existsSync()) {
      globals.logger.printError('tvOS plugin template not found at ${templateDir.path}');
      return FlutterCommandResult.fail();
    }

    if (!targetDir.existsSync()) {
      globals.logger.printStatus('Generating tvOS plugin...');

      // Convert name to plugin class: my_plugin → MyPlugin
      final String pluginClass = name
          .split('_')
          .map((String part) => part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1))
          .join();

      final template = Template(
        templateDir,
        templateDir,
        fileSystem: globals.fs,
        logger: globals.logger,
        templateRenderer: globals.templateRenderer,
      );

      template.render(targetDir, <String, Object>{
        'projectName': name,
        'pluginClass': pluginClass,
        'description': 'A new Flutter tvOS plugin project.',
      });
    }

    // Patch pubspec.yaml to add tvOS platform declaration
    _patchPluginPubspec(projectDirPath, name);

    return FlutterCommandResult.success();
  }

  /// Adds tvOS platform entry to the plugin's pubspec.yaml.
  void _patchPluginPubspec(String projectDirPath, String name) {
    final File pubspecFile = globals.fs.file(globals.fs.path.join(projectDirPath, 'pubspec.yaml'));

    if (!pubspecFile.existsSync()) {
      return;
    }

    String content = pubspecFile.readAsStringSync();

    // Convert name to plugin class
    final String pluginClass = name
        .split('_')
        .map((String part) => part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1))
        .join();

    // Add tvOS platform under flutter.plugin.platforms if not already present
    if (!content.contains('tvos:')) {
      // Find the platforms section and add tvOS
      final platformsRegex = RegExp(r'(platforms:\s*\n)', multiLine: true);
      final Match? match = platformsRegex.firstMatch(content);
      if (match != null) {
        final insertion =
            '${match.group(0)}'
            '        tvos:\n'
            '          pluginClass: $pluginClass\n';
        content = content.replaceFirst(match.group(0)!, insertion);
        pubspecFile.writeAsStringSync(content);
        globals.logger.printStatus('Added tvOS platform to pubspec.yaml');
      }
    }
  }
}
