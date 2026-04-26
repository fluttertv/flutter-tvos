// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/commands/create.dart';
import 'package:flutter_tools/src/commands/create_base.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/ios/code_signing.dart';
import 'package:flutter_tools/src/template.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

class TvosCreateCommand extends CreateCommand {
  TvosCreateCommand({
    required super.verboseHelp,
  });

  @override
  Future<FlutterCommandResult> runCommand() async {
    // Generate standard flutter project structure
    final FlutterCommandResult exitCode = await super.runCommand();
    if (exitCode != FlutterCommandResult.success()) {
      return exitCode;
    }

    final String projectDirPath = argResults!.rest.first;
    final String name = stringArg('project-name') ?? globals.fs.path.basename(projectDirPath);
    final String templateType = stringArg('template') ?? 'app';

    if (templateType == 'plugin') {
      return _createPlugin(projectDirPath, name);
    }

    return _createApp(projectDirPath, name);
  }

  Future<FlutterCommandResult> _createApp(String projectDirPath, String name) async {
    final String tvosTemplatePath = globals.fs.path.join(
      Cache.flutterRoot!,
      '..',
      'templates',
      'app',
      'swift',
      'tvos.tmpl',
    );
    final Directory templateDir = globals.fs.directory(tvosTemplatePath);
    final Directory targetDir = globals.fs.directory(projectDirPath).childDirectory('tvos');

    if (templateDir.existsSync() && !targetDir.existsSync()) {
      // Mirror Flutter's iOS template flow: read --org, build the bundle
      // identifier via CreateBase.createUTIIdentifier, and auto-detect a
      // signing-capable development team from the keychain. Hard-coded
      // 'com.example.<name>' would diverge from `flutter create` behaviour.
      final String organization = await getOrganization();
      final String tvosIdentifier = CreateBase.createUTIIdentifier(organization, name);
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

      globals.logger.printStatus('Generating tvOS application...');
      final Template template = Template(
        templateDir,
        templateDir,
        fileSystem: globals.fs,
        logger: globals.logger,
        templateRenderer: globals.templateRenderer,
      );

      template.render(
        targetDir,
        <String, Object>{
          'organization': organization,
          'projectName': name,
          'titleCaseProjectName': name.substring(0, 1).toUpperCase() + name.substring(1),
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
          'hasTvosDevelopmentTeam': developmentTeam != null && developmentTeam.isNotEmpty,
          'tvosDevelopmentTeam': developmentTeam ?? '',
        },
      );

      final File podfileSrc = templateDir.childFile('Podfile');
      if (podfileSrc.existsSync()) {
        podfileSrc.copySync(targetDir.childFile('Podfile').path);
      }
    }

    return FlutterCommandResult.success();
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

      final Template template = Template(
        templateDir,
        templateDir,
        fileSystem: globals.fs,
        logger: globals.logger,
        templateRenderer: globals.templateRenderer,
      );

      template.render(
        targetDir,
        <String, Object>{
          'projectName': name,
          'pluginClass': pluginClass,
          'description': 'A new Flutter tvOS plugin project.',
        },
      );
    }

    // Patch pubspec.yaml to add tvOS platform declaration
    _patchPluginPubspec(projectDirPath, name);

    return FlutterCommandResult.success();
  }

  /// Adds tvOS platform entry to the plugin's pubspec.yaml.
  void _patchPluginPubspec(String projectDirPath, String name) {
    final File pubspecFile = globals.fs.file(
      globals.fs.path.join(projectDirPath, 'pubspec.yaml'),
    );

    if (!pubspecFile.existsSync()) return;

    String content = pubspecFile.readAsStringSync();

    // Convert name to plugin class
    final String pluginClass = name
        .split('_')
        .map((String part) => part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1))
        .join();

    // Add tvOS platform under flutter.plugin.platforms if not already present
    if (!content.contains('tvos:')) {
      // Find the platforms section and add tvOS
      final RegExp platformsRegex = RegExp(r'(platforms:\s*\n)', multiLine: true);
      final Match? match = platformsRegex.firstMatch(content);
      if (match != null) {
        final String insertion = '${match.group(0)}'
            '        tvos:\n'
            '          pluginClass: $pluginClass\n';
        content = content.replaceFirst(match.group(0)!, insertion);
        pubspecFile.writeAsStringSync(content);
        globals.logger.printStatus('Added tvOS platform to pubspec.yaml');
      }
    }
  }
}

