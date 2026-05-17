// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../plugin_porting/example_porter.dart';
import '../plugin_porting/porting_result.dart'
    show FindingAction, PortingFinding;
import '../plugin_porting/scaffolder.dart';
import '../plugin_porting/source_analyzer.dart';
import '../plugin_porting/source_fetcher.dart';
import '../plugin_porting/templates.dart' show kDefaultLicenseHolder;
import 'tvos_runner.dart';

/// `flutter-tvos plugin port <source>` — scaffolds a federated `*_tvos`
/// package from an existing iOS or macOS plugin.
///
/// Reads the source plugin, then runs the Swift transformer (`.swift`) and
/// the Objective-C transformer (`.h/.m/.mm`): tvOS-incompatible imports are
/// stripped and unsupported method handlers stubbed via the compatibility
/// database, with a `PORTING_REPORT.md` summarising every change. Still to
/// come: `--include-example`, `--from-pub`, and `--from-git`.
class TvosPluginPortCommand extends FlutterCommand {
  TvosPluginPortCommand() {
    argParser
      ..addOption(
        'from-pub',
        help:
            'Port a package downloaded from pub.dev instead of a local '
            'directory, e.g. --from-pub url_launcher_ios. Mutually '
            'exclusive with a positional path and --from-git.',
      )
      ..addOption(
        'from-git',
        help:
            'Port a plugin from a git repository (cloned shallowly to a '
            'temp dir), e.g. --from-git https://github.com/foo/bar.git. '
            'Mutually exclusive with a positional path and --from-pub.',
      )
      ..addOption(
        'ref',
        help:
            'Git ref (branch/tag/sha) to check out. Only valid with '
            '--from-git.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'Where to write the generated `*_tvos` package. Defaults to a '
            'sibling of <source> named `<plugin>_tvos` (or the current '
            'directory for --from-pub / --from-git sources).',
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
        'include-example',
        negatable: false,
        help:
            "Also wire the source plugin's example/ app for tvOS: merge "
            '`dependency_overrides` so it resolves the generated `*_tvos` '
            'package, and append a run note to its README. Never writes '
            'into the generated package itself.',
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
      )
      ..addFlag(
        'allow-unbuildable',
        negatable: false,
        help:
            'Scaffold the package even when the porter determines it cannot '
            'compile on tvOS (the plugin uses APIs that do not exist on '
            'tvOS at type level). By default the command refuses and exits '
            'with an error instead of writing a package that will not '
            'build. Use this only if you intend to finish the port by hand.',
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
    final FileSystem fs = globals.fs;
    final Logger log = globals.logger;

    if (rest.length > 1) {
      throwToolExit(
        'Too many positional arguments. Expected at most one source '
        'directory; got ${rest.length} (${rest.join(', ')}).',
      );
    }

    final SourceSpec spec;
    try {
      spec = SourceSpec.parse(
        positional: rest.isEmpty ? null : rest.single,
        fromPub: stringArg('from-pub'),
        fromGit: stringArg('from-git'),
        ref: stringArg('ref'),
      );
    } on SourceFetchError catch (e) {
      throwToolExit(e.message);
    }

    // For --from-pub / --from-git the source is materialised under a temp
    // dir we must clean up no matter how the command exits.
    Directory? tempWork;
    final Directory sourceDir;
    if (spec.mode == FetchMode.localPath) {
      sourceDir = fs.directory(fs.path.absolute(spec.identifier));
      if (!sourceDir.existsSync()) {
        throwToolExit('Source directory does not exist: ${sourceDir.path}');
      }
    } else {
      tempWork = fs.systemTempDirectory.createTempSync('flutter_tvos_port_');
      try {
        sourceDir = await SourceFetcher(
          fileSystem: fs,
          processManager: globals.processManager,
          logger: log,
        ).resolve(spec, workDir: tempWork);
      } on SourceFetchError catch (e) {
        _safeDelete(tempWork);
        throwToolExit(e.message);
      }
    }

    try {
      return await _portResolvedSource(fs, log, sourceDir, fetched: tempWork != null);
    } finally {
      _safeDelete(tempWork);
    }
  }

  void _safeDelete(Directory? dir) {
    if (dir != null && dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort temp cleanup; never mask the real result.
      }
    }
  }

  Future<FlutterCommandResult> _portResolvedSource(
    FileSystem fs,
    Logger log,
    Directory sourceDir, {
    required bool fetched,
  }) async {
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
      if (e.advisory) {
        // Not a failure — the plugin simply needs no `*_tvos` package.
        log.printStatus(e.message);
        return FlutterCommandResult.success();
      }
      throwToolExit(e.message);
    }

    // Resolve the output directory. Default = sibling of source named
    // after the output package, EXCEPT for fetched sources whose sibling
    // is a temp dir we delete — those default to the current directory.
    // Honours `--output` (path can be relative).
    final String? outputArg = stringArg('output');
    final Directory outputDir = outputArg != null
        ? fs.directory(fs.path.absolute(outputArg))
        : fetched
            ? fs.currentDirectory.childDirectory(source.outputPackageName)
            : sourceDir.parent.childDirectory(source.outputPackageName);

    final bool dryRun = boolArg('dry-run');
    final bool force = boolArg('force');
    final bool emitReport = boolArg('report');
    final bool includeExample = boolArg('include-example');

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
    final bool allowUnbuildable = boolArg('allow-unbuildable');

    // Probe first (computes findings, writes nothing) so a plugin that
    // cannot compile on tvOS is rejected BEFORE any package is produced.
    // `taggedWithTodo` = a tvOS-unavailable API used at type / top-level
    // scope (not a stubbable method-channel handler): there is no
    // meaningful automatic tvOS port, and emitting the package would just
    // hand the developer something that fails at `xcodebuild`.
    final ScaffoldResult probe;
    try {
      probe = scaffolder.scaffold(
        source: source,
        outputDirectory: outputDir,
        overwrite: force,
        dryRun: true,
        emitReport: emitReport,
      );
    } on ScaffoldError catch (e) {
      throwToolExit(e.message);
    }

    final List<PortingFinding> blockingFindings = <PortingFinding>[
      for (final PortingFinding f in probe.findings)
        if (f.action == FindingAction.taggedWithTodo) f,
    ];
    final List<String> blockingApis = <String>{
      for (final PortingFinding f in blockingFindings) f.pattern.name,
    }.toList()
      ..sort();
    final bool willNotCompile = blockingApis.isNotEmpty;

    if (willNotCompile && !allowUnbuildable) {
      final StringBuffer b = StringBuffer()
        ..writeln('✗ ${source.packageName} cannot be ported to tvOS.')
        ..writeln()
        ..writeln(
          'It depends on APIs that do not exist on tvOS, used at type / '
          'top-level scope (not behind a method channel the porter can '
          'stub). A generated package would not compile, so none was '
          'written:')
        ..writeln();
      final Set<String> notedApis = <String>{};
      for (final String api in blockingApis) {
        final List<PortingFinding> hits = <PortingFinding>[
          for (final PortingFinding f in blockingFindings)
            if (f.pattern.name == api) f,
        ];
        for (final PortingFinding f in hits.take(3)) {
          b.writeln(
              '  • $api  ${f.fileRelativePath}:${f.line}  ‹${f.matchedText}›');
        }
        if (hits.length > 3) {
          b.writeln('    … and ${hits.length - 3} more $api reference(s)');
        }
        if (notedApis.add(api)) {
          b.writeln('      ${hits.first.pattern.note.split('\n').first}');
        }
      }
      b
        ..writeln()
        ..writeln(
          'These features have no tvOS equivalent — the plugin needs a '
          'hand-written tvOS implementation, or it simply has no tvOS '
          'support.')
        ..writeln()
        ..writeln(
          'Re-run with --dry-run to inspect the full report, or '
          '--allow-unbuildable to scaffold the partial package anyway for '
          'manual porting.');
      throwToolExit(b.toString());
    }

    final ScaffoldResult result;
    if (dryRun) {
      result = probe;
    } else {
      try {
        result = scaffolder.scaffold(
          source: source,
          outputDirectory: outputDir,
          overwrite: force,
          emitReport: emitReport,
        );
      } on ScaffoldError catch (e) {
        throwToolExit(e.message);
      }
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
      if (willNotCompile) {
        log.printWarning(
          '(dry run) NOT tvOS-buildable: uses ${blockingApis.join(', ')} '
          'at type level — no meaningful automatic tvOS port.',
        );
      }
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
      if (willNotCompile) {
        log.printWarning('');
        log.printWarning(
          '⚠️  NOT buildable on tvOS as-is. This plugin uses '
          '${blockingApis.join(', ')} at type / top-level scope — APIs '
          'that do not exist on tvOS. The porter cannot invent these '
          'types, so the generated package will NOT compile until you '
          'rewrite those sites by hand, or this plugin simply has no '
          'meaningful tvOS implementation. Details + every '
          '`// TODO(porter)` site are in '
          '${outputDir.basename}/PORTING_REPORT.md.',
        );
      } else if (result.reportPath != null) {
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

    if (source.ffiNativeAssets) {
      // The native skeleton already wrote example/lib + example/pubspec
      // (depending on `<base>` + `<base>_tvos: path: ../`). Render its
      // tvOS-only runner so it is immediately runnable — no fragile
      // upstream-monorepo example copy for the FFI case.
      final Directory exampleDir = outputDir.childDirectory('example');
      if (!dryRun && exampleDir.existsSync()) {
        await renderTvosRunner(
          fileSystem: fs,
          logger: log,
          templateRenderer: globals.templateRenderer,
          projectDirPath: exampleDir.path,
          name: '${source.basePackageName}_example',
          organization: 'com.example',
        );
        log.printStatus('');
        log.printStatus(
          'Runnable tvOS example at ${exampleDir.path}\n'
          '  cd ${exampleDir.path} && flutter-tvos run',
        );
      }
    } else if (includeExample && !dryRun) {
      await _generateExample(fs, log, source, outputDir);
    } else if (includeExample && dryRun) {
      log.printStatus('');
      log.printStatus(
        '(dry run) Would generate example/ from the `${source.basePackageName}` '
        'plugin (tvOS-only), depending on `${source.basePackageName}` + '
        '`${source.outputPackageName}: path: ../`.',
      );
    }

    return FlutterCommandResult.success();
  }

  /// Builds the federated example: fetch the app-facing plugin
  /// (`<base>`), reuse its real example app, make it tvOS-only, and point
  /// it at the generated `<base>_tvos` (mirrors flutter-tizen/plugins).
  Future<void> _generateExample(
    FileSystem fs,
    Logger log,
    PluginSource source,
    Directory outputDir,
  ) async {
    final Directory work =
        fs.systemTempDirectory.createTempSync('flutter_tvos_example_');
    try {
      final Directory baseDir = await SourceFetcher(
        fileSystem: fs,
        processManager: globals.processManager,
        logger: log,
      ).resolve(
        SourceSpec.parse(fromPub: source.basePackageName),
        workDir: work,
      );
      final String baseVersion = _pubspecVersion(baseDir) ?? '0.0.0';
      final ExamplePortResult ex = ExamplePorter(fileSystem: fs).port(
        basePluginDir: baseDir,
        outputPackageDir: outputDir,
        baseName: source.basePackageName,
        tvosPackageName: source.outputPackageName,
        baseVersion: baseVersion,
      );
      log.printStatus('');
      if (ex.skipped) {
        log.printWarning('--include-example skipped: ${ex.reason}');
        return;
      }
      await renderTvosRunner(
        fileSystem: fs,
        logger: log,
        templateRenderer: globals.templateRenderer,
        projectDirPath: ex.exampleDirectory!.path,
        name: '${source.basePackageName}_example',
        organization: 'com.example',
      );
      log.printStatus(
        'Generated tvOS-only example (${ex.copiedRelativePaths.length} files) '
        'in ${ex.exampleDirectory!.path} — depends on '
        '`${source.basePackageName}` + `${source.outputPackageName}: '
        'path: ../`.',
      );
    } on SourceFetchError catch (e) {
      log.printWarning('--include-example skipped: ${e.message}');
    } finally {
      _safeDelete(work);
    }
  }

  /// Reads `version:` from a pubspec directory, or `null`.
  String? _pubspecVersion(Directory dir) {
    final File p = dir.childFile('pubspec.yaml');
    if (!p.existsSync()) {
      return null;
    }
    for (final String line in p.readAsLinesSync()) {
      final RegExpMatch? m =
          RegExp(r'^version:\s*([^\s#]+)').firstMatch(line);
      if (m != null) {
        return m.group(1);
      }
    }
    return null;
  }
}
