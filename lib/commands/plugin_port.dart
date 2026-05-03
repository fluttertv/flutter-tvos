// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../plugin_porting/scaffolder.dart';
import '../plugin_porting/source_analyzer.dart';
import '../plugin_porting/templates.dart' show kDefaultLicenseHolder;

/// `flutter-tvos plugin port <source>` — scaffolds a federated `*_tvos`
/// package from an existing iOS or macOS plugin.
///
/// Phase 1 (this implementation): generates the directory skeleton with a
/// stub Swift class. Phases 2–7 layered on top progressively read the source
/// plugin, transform iOS API references, generate a porting report, and
/// support `--from-pub` / `--from-git` / `--include-example`. See
/// `docs/PLUGIN_PORTING.md` for the full plan.
class TvosPluginPortCommand extends FlutterCommand {
  TvosPluginPortCommand() {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Where to write the generated `*_tvos` package. Defaults to a '
            'sibling of <source> named `<plugin>_tvos`.',
      )
      ..addOption(
        'base-platform',
        defaultsTo: 'ios',
        allowed: <String>['ios', 'macos'],
        help:
            'Which existing platform implementation to model the port on. '
            "Default `ios`. Use `macos` when the source's macOS code is a "
            'closer fit for tvOS than its iOS code (often true for plugins '
            'that avoid UIKit-only APIs).',
      )
      ..addOption(
        'license-holder',
        defaultsTo: kDefaultLicenseHolder,
        help:
            'Copyright holder line baked into generated source files. Set '
            'this to your name or organisation when porting plugins you will '
            'maintain yourself.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help:
            'Overwrite the output directory if it already exists. Without '
            'this flag, the command refuses to clobber existing files.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Report what would be written without touching the filesystem. '
            'Useful for previewing the layout on a plugin you are not yet '
            'sure you want to port.',
      );
  }

  @override
  final String name = 'port';

  @override
  final String description =
      'Scaffold a federated `*_tvos` package from an existing iOS or macOS '
      'plugin directory.';

  @override
  final String category = 'Tools';

  @override
  String get invocation => 'flutter-tvos plugin port <source-dir> [options]';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final List<String> rest = argResults!.rest;
    if (rest.isEmpty) {
      throwToolExit(
        'No source directory supplied. See `flutter-tvos plugin port --help`.',
      );
    }
    if (rest.length > 1) {
      throwToolExit(
        'Too many positional arguments. Expected exactly one source directory; '
        'got ${rest.length} (${rest.join(', ')}).',
      );
    }

    final FileSystem fs = globals.fs;
    final Logger log = globals.logger;

    final Directory sourceDir = fs.directory(fs.path.absolute(rest.single));

    // Inspect the source. Fatal misconfigurations throw; the analyzer prints
    // any warnings via the supplied sink so the user sees them before any
    // file write happens.
    final analyzer = SourceAnalyzer(
      fileSystem: fs,
      warningSink: (String msg) => log.printWarning('  • $msg'),
    );

    final PluginSource source;
    try {
      source = analyzer.analyze(sourceDir, preferPlatform: stringArg('base-platform')!);
    } on PluginSourceError catch (e) {
      throwToolExit(e.message);
    }

    // Resolve the output directory. Default = sibling of source named after
    // the output package. Honours `--output` (path can be relative).
    final String? outputArg = stringArg('output');
    final Directory outputDir = outputArg != null
        ? fs.directory(fs.path.absolute(outputArg))
        : sourceDir.parent.childDirectory(source.outputPackageName);

    final bool dryRun = boolArg('dry-run');
    final bool force = boolArg('force');

    log.printStatus('Source plugin:    ${source.packageName}');
    log.printStatus('Source platform:  ${source.sourcePlatform} (${source.sourceLanguage.name})');
    log.printStatus('Plugin class:     ${source.pluginClass}');
    if (source.dartPluginClass != null) {
      log.printStatus('Dart class:       ${source.dartPluginClass}');
    }
    if (source.platformInterfacePackage != null) {
      log.printStatus('Platform iface:   ${source.platformInterfacePackage}');
    }
    log.printStatus('Output package:   ${source.outputPackageName}');
    log.printStatus('Output directory: ${outputDir.path}');
    if (dryRun) {
      log.printStatus('  (dry run — no files will be written)');
    }
    log.printStatus('');

    final scaffolder = Scaffolder(
      fileSystem: fs,
      logger: log,
      licenseHolder: stringArg('license-holder')!,
    );
    final ScaffoldResult result;
    try {
      result = scaffolder.scaffold(
        source: source,
        outputDirectory: outputDir,
        overwrite: force,
        dryRun: dryRun,
      );
    } on ScaffoldError catch (e) {
      throwToolExit(e.message);
    }

    if (dryRun) {
      log.printStatus('Would write ${result.writtenPaths.length} files:');
      for (final String path in result.writtenPaths) {
        log.printStatus('  $path');
      }
    } else {
      log.printStatus('Wrote ${result.writtenPaths.length} files into ${outputDir.path}.');
      log.printStatus('');
      log.printStatus('Next steps:');
      log.printStatus(
        '  1. Paste your iOS implementation into '
        'tvos/Classes/${source.pluginClass}.swift and remove imports/calls '
        'that are not available on tvOS.',
      );
      log.printStatus(
        "  2. Add `${source.outputPackageName}` to the plugin's example app "
        'pubspec, then run `flutter-tvos build tvos --simulator --debug` to '
        'verify.',
      );
      log.printStatus(
        '  3. Once you are happy, publish to pub.dev or push to your fork. '
        'Read `${outputDir.basename}/README.md` for the user-facing pitch.',
      );
    }

    return FlutterCommandResult.success();
  }
}
