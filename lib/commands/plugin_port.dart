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
import '../plugin_porting/swift_porter.dart' show FindingAction;
import '../plugin_porting/templates.dart' show kDefaultLicenseHolder;

/// `flutter-tvos plugin port <source>` — scaffolds a federated `*_tvos`
/// package from an existing iOS or macOS plugin.
///
/// Phases 1–3 (this implementation): reads the source plugin, copies its
/// native sources, runs the Swift transformer (strips tvOS-incompatible
/// imports, stubs unsupported method handlers via the compatibility
/// database) and writes `PORTING_REPORT.md`. Phases 4–7 layer on the
/// Objective-C transformer, `--include-example`, and `--from-pub` /
/// `--from-git`. See `docs/PLUGIN_PORTING.md` for the full plan.
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
      )
      ..addFlag(
        'report',
        defaultsTo: true,
        help:
            'Write PORTING_REPORT.md alongside the package. Pass --no-report '
            'to skip it; the Swift transform (import stripping, handler '
            'stubbing) still runs either way.',
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
    final bool emitReport = boolArg('report');

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
        emitReport: emitReport,
      );
    } on ScaffoldError catch (e) {
      throwToolExit(e.message);
    }

    final int stubbed = result.findings
        .where((f) => f.action == FindingAction.stubbedMethod)
        .length;
    final int strippedImports = result.findings
        .where((f) => f.action == FindingAction.importStripped)
        .length;
    final int needsReview = result.findings
        .where((f) =>
            f.action == FindingAction.flagged ||
            f.action == FindingAction.taggedWithTodo)
        .length;
    final bool anyFindings = result.findings.isNotEmpty;

    if (dryRun) {
      log.printStatus('Would write ${result.writtenPaths.length} files:');
      for (final String path in result.writtenPaths) {
        log.printStatus('  $path');
      }
      log.printStatus('');
      log.printStatus(
        'Porter would strip $strippedImports import(s), stub $stubbed '
        'method(s), and flag $needsReview item(s) for manual review.',
      );
    } else {
      log.printStatus('Wrote ${result.writtenPaths.length} files into ${outputDir.path}.');
      log.printStatus('');
      log.printStatus(
        'Porter stripped $strippedImports iOS-only import(s), stubbed '
        '$stubbed method handler(s), and flagged $needsReview item(s) for '
        'manual review.',
      );
      log.printStatus('');
      log.printStatus('Next steps:');
      log.printStatus(
        '  1. Review tvos/Classes/ — the source plugin was copied and '
        'ported automatically. Stubbed handlers are marked with '
        '`// TODO(porter)`.',
      );
      log.printStatus(
        "  2. Add `${source.outputPackageName}` to the plugin's example app "
        'pubspec, then run `flutter-tvos build tvos --simulator --debug` to '
        'verify the registrant compiles.',
      );
      log.printStatus(
        '  3. Once you are happy, publish to pub.dev or push to your fork. '
        'Read `${outputDir.basename}/README.md` for the user-facing pitch.',
      );
      log.printStatus('');
      if (result.reportPath != null) {
        if (anyFindings) {
          log.printStatus(
            'Manual review required. Read '
            '${outputDir.basename}/PORTING_REPORT.md before publishing.',
          );
        } else {
          log.printStatus(
            'No tvOS-incompatible APIs detected. See '
            '${outputDir.basename}/PORTING_REPORT.md for the full report.',
          );
        }
      }
    }

    return FlutterCommandResult.success();
  }
}
