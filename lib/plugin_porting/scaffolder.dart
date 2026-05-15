// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';

import 'report_emitter.dart';
import 'source_analyzer.dart';
import 'swift_porter.dart';
import 'templates.dart' as tmpl;

/// Writes the on-disk scaffolding for a `*_tvos` plugin package given an
/// already-analysed source plugin.
///
/// Phase 2 deliverable: native sources from the source plugin's
/// `<platform>/Classes/` are copied verbatim into the output's
/// `tvos/Classes/`. The user inherits their iOS implementation in place
/// rather than starting from an empty stub. Sibling `Resources/` (xib,
/// asset catalogs) are copied alongside.
///
/// When the source has no native files (rare — e.g. plugins where Pigeon
/// generates everything at build time), the scaffolder falls back to the
/// Phase-1 stub so the package still builds.
///
/// Phase 3+ adds a transformer pass that scans the copied sources for
/// iOS-only API references and stubs the matching method handlers.
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
  /// [ScaffoldResult] reporting which paths *would* have been written and
  /// the findings the Swift porter detected (so `--dry-run` can preview the
  /// report). When [overwrite] is false and [outputDirectory] already
  /// exists, throws. When [emitReport] is false, `PORTING_REPORT.md` is not
  /// written (the `--no-report` flag) — the code transform still runs.
  ScaffoldResult scaffold({
    required PluginSource source,
    required Directory outputDirectory,
    bool overwrite = false,
    bool dryRun = false,
    bool emitReport = true,
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
            .childFile('${source.outputPackageName}.podspec')
            .path,
        contents: tmpl.renderPodspec(source: source, licenseHolder: licenseHolder),
      ),
    ];

    // Native sources from the source plugin's <platform>/Classes/ go into
    // the output's tvos/Classes/. Phase 3: Swift files run through
    // [SwiftPorter] (iOS-only imports stripped, unsupported method handlers
    // stubbed); .h/.m/.mm are still copied verbatim (Phase 4 ports ObjC).
    // Falls back to the Phase-1 stub when the source has no native files.
    final Directory tvosClassesDir = outputDirectory.childDirectory('tvos').childDirectory('Classes');
    final List<_NativeCopy> allNative = _collectNativeCopies(source, tvosClassesDir);
    final List<_NativeCopy> nativeCopies = <_NativeCopy>[
      for (final _NativeCopy c in allNative)
        if (_fs.path.extension(c.source.path).toLowerCase() != '.swift') c,
    ];
    final List<_SwiftPort> swiftPorts = <_SwiftPort>[];
    final List<SwiftPortingResult> portResults = <SwiftPortingResult>[];
    final SwiftPorter porter = SwiftPorter();
    for (final _NativeCopy c in allNative) {
      if (_fs.path.extension(c.source.path).toLowerCase() != '.swift') {
        continue;
      }
      final String relInPackage =
          _fs.path.relative(c.destinationPath, from: outputDirectory.path);
      final SwiftPortingResult r = porter.port(
        c.source.readAsStringSync(),
        fileRelativePath: relInPackage,
      );
      portResults.add(r);
      swiftPorts.add(_SwiftPort(
        destinationPath: c.destinationPath,
        contents: r.transformed,
      ));
    }

    if (allNative.isEmpty) {
      // No copyable sources — emit the Phase-1 stubs so the package still
      // builds and the user has something to paste their iOS code into.
      plan.add(_Plan(
        path: tvosClassesDir.childFile('${source.pluginClass}.swift').path,
        contents: tmpl.renderSwiftStub(source: source, licenseHolder: licenseHolder),
      ));
      plan.add(_Plan(
        path: tvosClassesDir.childFile('${source.pluginClass}-Bridging-Header.h').path,
        contents: tmpl.renderBridgingHeader(source: source, licenseHolder: licenseHolder),
      ));
    }

    // Phase 2: copy <platform>/Resources/ if it exists (xib, asset
    // catalogs, etc). tvOS understands these formats unchanged.
    final Directory? resourcesSource = _resolveResourcesDir(source);
    final List<_NativeCopy> resourceCopies = resourcesSource == null
        ? const <_NativeCopy>[]
        : _collectResourceCopies(
            resourcesSource,
            outputDirectory.childDirectory('tvos').childDirectory('Resources'),
          );

    File? copiedLicense;
    if (source.licenseFile != null) {
      copiedLicense = outputDirectory.childFile('LICENSE');
    }

    // Phase 3: the porting report is generated alongside the package on
    // every run unless `--no-report` is passed. It is rendered from the
    // findings collected above so `--dry-run` can preview it too.
    final File? reportFile =
        emitReport ? outputDirectory.childFile('PORTING_REPORT.md') : null;
    final String? reportContents = reportFile == null
        ? null
        : const ReportEmitter().render(source: source, results: portResults);

    if (!dryRun) {
      for (final p in plan) {
        final File f = _fs.file(p.path)..parent.createSync(recursive: true);
        f.writeAsStringSync(p.contents);
        _log.printTrace('  wrote ${p.path}');
      }
      for (final s in swiftPorts) {
        final File f = _fs.file(s.destinationPath)..parent.createSync(recursive: true);
        f.writeAsStringSync(s.contents);
        _log.printTrace('  ported ${s.destinationPath}');
      }
      for (final c in <_NativeCopy>[...nativeCopies, ...resourceCopies]) {
        final File dst = _fs.file(c.destinationPath)..parent.createSync(recursive: true);
        c.source.copySync(dst.path);
        _log.printTrace('  copied ${c.source.path} → ${c.destinationPath}');
      }
      if (copiedLicense != null && source.licenseFile != null) {
        copiedLicense.parent.createSync(recursive: true);
        source.licenseFile!.copySync(copiedLicense.path);
        _log.printTrace('  copied LICENSE from ${source.licenseFile!.path}');
      }
      if (reportFile != null && reportContents != null) {
        reportFile.parent.createSync(recursive: true);
        reportFile.writeAsStringSync(reportContents);
        _log.printTrace('  wrote ${reportFile.path}');
      }
    }

    return ScaffoldResult(
      outputDirectory: outputDirectory,
      writtenPaths: <String>[
        for (final _Plan p in plan) p.path,
        for (final _SwiftPort s in swiftPorts) s.destinationPath,
        for (final _NativeCopy c in nativeCopies) c.destinationPath,
        for (final _NativeCopy c in resourceCopies) c.destinationPath,
        if (copiedLicense != null) copiedLicense.path,
        if (reportFile != null) reportFile.path,
      ],
      findings: <PortingFinding>[
        for (final SwiftPortingResult r in portResults) ...r.findings,
      ],
      reportPath: reportFile?.path,
      dryRun: dryRun,
    );
  }

  /// Walks the source's `<platform>/Classes/` directory and produces a list
  /// of (source-file → destination-path) pairs covering every Swift / ObjC
  /// source. Subdirectory structure is preserved relative to `Classes/`.
  ///
  /// Returns an empty list when the source has no copyable native files —
  /// caller falls back to writing a stub.
  List<_NativeCopy> _collectNativeCopies(PluginSource source, Directory destination) {
    if (!source.classesDirectory.existsSync()) {
      return const <_NativeCopy>[];
    }
    return _collectByExtension(
      source.classesDirectory,
      destination,
      const <String>{'.swift', '.h', '.m', '.mm'},
    );
  }

  /// Returns the source's `<platform>/Resources/` directory if it exists,
  /// otherwise null. The plugin's `pubspec.yaml` doesn't tell us where
  /// Resources live; we look in the conventional location next to the
  /// `Classes/` directory we already analysed.
  Directory? _resolveResourcesDir(PluginSource source) {
    final Directory candidate = source.classesDirectory.parent.childDirectory('Resources');
    return candidate.existsSync() ? candidate : null;
  }

  /// Walks a `Resources/` directory and produces copy plans for every file
  /// regardless of extension — Resources include arbitrary content (PNGs,
  /// xib bundles, asset catalogs, plist, etc.) that we can't filter.
  List<_NativeCopy> _collectResourceCopies(Directory sourceDir, Directory destinationDir) {
    return _collectByExtension(sourceDir, destinationDir, null);
  }

  /// Common helper used by both [_collectNativeCopies] and
  /// [_collectResourceCopies]. When [allowedExtensions] is null, every file
  /// is included; when it is a set, only files whose lowercased extension
  /// is in the set are copied.
  ///
  /// Subdirectory structure under [sourceDir] is preserved verbatim under
  /// [destinationDir].
  List<_NativeCopy> _collectByExtension(
    Directory sourceDir,
    Directory destinationDir,
    Set<String>? allowedExtensions,
  ) {
    final copies = <_NativeCopy>[];
    for (final FileSystemEntity entity in sourceDir.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      if (allowedExtensions != null) {
        final String ext = _fs.path.extension(entity.path).toLowerCase();
        if (!allowedExtensions.contains(ext)) {
          continue;
        }
      }
      final String relative = _fs.path.relative(entity.path, from: sourceDir.path);
      final String dst = _fs.path.join(destinationDir.path, relative);
      copies.add(_NativeCopy(source: entity, destinationPath: dst));
    }
    return copies;
  }
}

/// Returned from [Scaffolder.scaffold] so callers can summarise what happened
/// without re-walking the directory.
class ScaffoldResult {
  ScaffoldResult({
    required this.outputDirectory,
    required this.writtenPaths,
    required this.findings,
    required this.reportPath,
    required this.dryRun,
  });

  final Directory outputDirectory;
  final List<String> writtenPaths;

  /// Every [PortingFinding] the Swift porter produced across all ported
  /// sources. Empty when nothing tvOS-incompatible was detected. The
  /// command uses this to decide whether to print the "manual review
  /// required" banner.
  final List<PortingFinding> findings;

  /// Absolute path of the generated `PORTING_REPORT.md`, or `null` when
  /// `--no-report` suppressed it.
  final String? reportPath;

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

/// Represents a verbatim file copy from the source plugin into the output
/// `tvos/` directory tree. Used by Phase 2's native-source and resources
/// pass.
///
/// Kept distinct from [_Plan] (which renders content from a template
/// string) so the verbose-log lines can distinguish "wrote rendered X"
/// from "copied source file Y".
class _NativeCopy {
  _NativeCopy({required this.source, required this.destinationPath});
  final File source;
  final String destinationPath;
}

/// A Swift source that was run through [SwiftPorter]. Unlike [_NativeCopy]
/// the bytes written are the *transformed* content, not a verbatim copy —
/// so the verbose log can say "ported X" rather than "copied X".
class _SwiftPort {
  _SwiftPort({required this.destinationPath, required this.contents});
  final String destinationPath;
  final String contents;
}
