// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';

import 'source_analyzer.dart';
import 'templates.dart' as tmpl;

/// Writes the on-disk scaffolding for a `*_tvos` plugin package given an
/// already-analysed source plugin.
///
/// Phase 1 deliverable: writes the package skeleton with stub content.
/// Phase 2+ extends [scaffold] to also copy native source files into
/// `tvos/Classes/` (verbatim or transformed).
class Scaffolder {
  Scaffolder({
    required FileSystem fileSystem,
    required Logger logger,
    required this.licenseHolder,
  }) : _fs = fileSystem,
       _log = logger;

  final FileSystem _fs;
  final Logger _log;
  final String licenseHolder;

  /// Generates [source]'s tvOS scaffold into [outputDirectory].
  ///
  /// When [dryRun] is true no files are written; the call still produces a
  /// [ScaffoldResult] reporting which paths *would* have been written. When
  /// [overwrite] is false and [outputDirectory] already exists, throws.
  ScaffoldResult scaffold({
    required PluginSource source,
    required Directory outputDirectory,
    bool overwrite = false,
    bool dryRun = false,
  }) {
    if (outputDirectory.existsSync() && !dryRun) {
      if (!overwrite) {
        throw ScaffoldError(
          'Output directory already exists: ${outputDirectory.path}\n'
          'Pass `--force` to overwrite, or `--output <other-dir>` to write elsewhere.',
        );
      }
      outputDirectory.deleteSync(recursive: true);
    }

    final plan = <_Plan>[
      _Plan(
        path: outputDirectory.childFile('pubspec.yaml').path,
        contents: tmpl.renderPubspec(source: source, licenseHolder: licenseHolder),
      ),
      _Plan(
        path: outputDirectory.childFile('README.md').path,
        contents: tmpl.renderReadme(source: source, licenseHolder: licenseHolder),
      ),
      _Plan(
        path: outputDirectory.childFile('CHANGELOG.md').path,
        contents: tmpl.renderChangelog(source: source),
      ),
      _Plan(
        path: outputDirectory.childFile('analysis_options.yaml').path,
        contents: tmpl.renderAnalysisOptions(),
      ),
      _Plan(
        path: outputDirectory.childFile('.gitignore').path,
        contents: tmpl.renderGitignore(),
      ),
      _Plan(
        path: outputDirectory.childDirectory('lib').childFile('${source.outputPackageName}.dart').path,
        contents: tmpl.renderDartEntry(source: source, licenseHolder: licenseHolder),
      ),
      _Plan(
        path: outputDirectory
            .childDirectory('test')
            .childFile('${source.outputPackageName}_test.dart')
            .path,
        contents: tmpl.renderTestStub(source: source, licenseHolder: licenseHolder),
      ),
      _Plan(
        path: outputDirectory
            .childDirectory('tvos')
            .childDirectory('Classes')
            .childFile('${source.pluginClass}.swift')
            .path,
        contents: tmpl.renderSwiftStub(source: source, licenseHolder: licenseHolder),
      ),
      _Plan(
        path: outputDirectory
            .childDirectory('tvos')
            .childDirectory('Classes')
            .childFile('${source.pluginClass}-Bridging-Header.h')
            .path,
        contents: tmpl.renderBridgingHeader(source: source, licenseHolder: licenseHolder),
      ),
      _Plan(
        path: outputDirectory
            .childDirectory('tvos')
            .childFile('${source.outputPackageName}.podspec')
            .path,
        contents: tmpl.renderPodspec(source: source, licenseHolder: licenseHolder),
      ),
    ];

    File? copiedLicense;
    if (source.licenseFile != null) {
      copiedLicense = outputDirectory.childFile('LICENSE');
    }

    if (!dryRun) {
      for (final p in plan) {
        final File f = _fs.file(p.path)..parent.createSync(recursive: true);
        f.writeAsStringSync(p.contents);
        _log.printTrace('  wrote ${p.path}');
      }
      if (copiedLicense != null && source.licenseFile != null) {
        copiedLicense.parent.createSync(recursive: true);
        source.licenseFile!.copySync(copiedLicense.path);
        _log.printTrace('  copied LICENSE from ${source.licenseFile!.path}');
      }
    }

    return ScaffoldResult(
      outputDirectory: outputDirectory,
      writtenPaths: <String>[for (final _Plan p in plan) p.path, if (copiedLicense != null) copiedLicense.path],
      dryRun: dryRun,
    );
  }
}

/// Returned from [Scaffolder.scaffold] so callers can summarise what happened
/// without re-walking the directory.
class ScaffoldResult {
  ScaffoldResult({
    required this.outputDirectory,
    required this.writtenPaths,
    required this.dryRun,
  });

  final Directory outputDirectory;
  final List<String> writtenPaths;
  final bool dryRun;
}

class ScaffoldError implements Exception {
  ScaffoldError(this.message);
  final String message;
  @override
  String toString() => 'ScaffoldError: $message';
}

class _Plan {
  _Plan({required this.path, required this.contents});
  final String path;
  final String contents;
}
