// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';

import 'native_skeleton.dart';
import 'objc_porter.dart';
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

    // dart:ffi / native-assets source → emit a native federated skeleton
    // (Swift method channel over the platform interface) instead of
    // copying an FFI implementation the tvOS toolchain can't build.
    if (source.ffiNativeAssets) {
      final Map<String, String> files = const NativeSkeleton()
          .files(source: source, licenseHolder: licenseHolder);
      final List<String> written = <String>[];
      String? reportPath;
      for (final MapEntry<String, String> e in files.entries) {
        if (!emitReport && e.key == 'PORTING_REPORT.md') {
          continue;
        }
        final File f = _fs.file(_fs.path.join(outputDirectory.path, e.key));
        written.add(f.path);
        if (e.key == 'PORTING_REPORT.md') {
          reportPath = f.path;
        }
        if (!dryRun) {
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(e.value);
          _log.printTrace('  wrote ${f.path}');
        }
      }
      return ScaffoldResult(
        outputDirectory: outputDirectory,
        writtenPaths: written,
        findings: const <PortingFinding>[],
        prunedDartFiles: const <String>[],
        reportPath: reportPath,
        dryRun: dryRun,
      );
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

    // Swift Package Manager manifest (Flutter 3.44+ default), generated
    // alongside the podspec so the plugin works with either dependency
    // manager. A single SwiftPM target can't mix languages, so this is only
    // emitted for Swift plugins (and the Swift-stub fallback when the source
    // has no native code); Objective-C / mixed plugins stay CocoaPods-only.
    if (source.sourceLanguage == SourceLanguage.swift ||
        source.sourceLanguage == SourceLanguage.unknown) {
      plan.add(
        _Plan(
          path: outputDirectory.childDirectory('tvos').childFile('Package.swift').path,
          contents: tmpl.renderPackageSwift(source: source),
        ),
      );
    }

    // The federated Dart implementation. The source plugin's `lib/`
    // already extends the platform interface and talks to the SAME
    // method channel the native side registers — and we keep that
    // channel name unchanged — so the upstream Dart code works on tvOS
    // verbatim. Copy it (rewriting `package:<src>` self-imports to the
    // output package) instead of hand-writing a guessed stub that would
    // not compile. Falls back to the templated stub when the source has
    // no Dart `lib/` (rare).
    final List<String> prunedDartFiles = <String>[];
    plan.addAll(_dartLibPlans(
      source,
      outputDirectory,
      licenseHolder,
      prunedDartFiles,
    ));

    // Native sources from the source plugin's <platform>/Classes/ go into
    // the output's tvos/Classes/. Swift files run through [SwiftPorter] and
    // Objective-C `.h/.m/.mm` through [ObjcPorter] (iOS-only imports
    // stripped, unsupported method handlers stubbed). Anything else is
    // copied verbatim. Falls back to the Phase-1 stub when the source has
    // no native files at all.
    final Directory tvosClassesDir = outputDirectory.childDirectory('tvos').childDirectory('Classes');
    final List<_NativeCopy> allNative = _collectNativeCopies(source, tvosClassesDir);
    const Set<String> swiftExt = <String>{'.swift'};
    const Set<String> objcExt = <String>{'.h', '.m', '.mm'};
    final List<_NativeCopy> nativeCopies = <_NativeCopy>[
      for (final _NativeCopy c in allNative)
        if (!swiftExt.contains(_fs.path.extension(c.source.path).toLowerCase()) &&
            !objcExt.contains(_fs.path.extension(c.source.path).toLowerCase()))
          c,
    ];
    final List<_PortedFile> portedFiles = <_PortedFile>[];
    final List<PortingResult> portResults = <PortingResult>[];
    final SwiftPorter swiftPorter = SwiftPorter();
    final ObjcPorter objcPorter = ObjcPorter();
    for (final _NativeCopy c in allNative) {
      final String ext = _fs.path.extension(c.source.path).toLowerCase();
      final bool isSwift = swiftExt.contains(ext);
      final bool isObjc = objcExt.contains(ext);
      if (!isSwift && !isObjc) {
        continue;
      }
      final String relInPackage =
          _fs.path.relative(c.destinationPath, from: outputDirectory.path);
      final String src = c.source.readAsStringSync();
      final PortingResult r = isSwift
          ? swiftPorter.port(src, fileRelativePath: relInPackage)
          : objcPorter.port(src, fileRelativePath: relInPackage);
      portResults.add(r);
      portedFiles.add(_PortedFile(
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
        : const ReportEmitter().render(
            source: source,
            results: portResults,
            prunedDartFiles: prunedDartFiles,
          );

    if (!dryRun) {
      for (final p in plan) {
        final File f = _fs.file(p.path)..parent.createSync(recursive: true);
        f.writeAsStringSync(p.contents);
        _log.printTrace('  wrote ${p.path}');
      }
      for (final s in portedFiles) {
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
        for (final _PortedFile s in portedFiles) s.destinationPath,
        for (final _NativeCopy c in nativeCopies) c.destinationPath,
        for (final _NativeCopy c in resourceCopies) c.destinationPath,
        if (copiedLicense != null) copiedLicense.path,
        if (reportFile != null) reportFile.path,
      ],
      findings: <PortingFinding>[
        for (final PortingResult r in portResults) ...r.findings,
      ],
      prunedDartFiles: prunedDartFiles,
      reportPath: reportFile?.path,
      dryRun: dryRun,
    );
  }

  /// Copies the source plugin's Dart `lib/` into the output package,
  /// rewriting `package:<src>/…` self-imports to the output package and
  /// renaming the conventional entry `lib/<src>.dart` →
  /// `lib/<out>.dart` (so Flutter's federated registrant can import it
  /// and find `dartPluginClass`). Falls back to the templated stub when
  /// the source ships no Dart `lib/`.
  ///
  /// **Prunes cross-platform Dart that tvOS will never run.** Upstream
  /// `_plus`-style packages bundle Linux/Windows/Web/macOS federated
  /// implementations alongside the iOS one — none of which compile on
  /// tvOS (they import `package:web`, `flutter_web_plugins`, `win32`,
  /// `package:nm`, etc.) and none of which are reachable at runtime in
  /// a tvOS app (the registrar loads only the tvOS plugin class). The
  /// porter drops files matching non-Apple platform suffixes and
  /// well-known platform-specific subdirectories, then scrubs the
  /// remaining files' `import`/`export` directives so nothing points at
  /// the dropped paths. Apple-shared sources (entry, `_ios*`, generic
  /// `src/messages.g.dart`, etc.) are preserved verbatim. Paths the
  /// pruner dropped are reported as [ScaffoldResult.prunedDartFiles].
  List<_Plan> _dartLibPlans(
    PluginSource source,
    Directory outputDirectory,
    String licenseHolder,
    List<String> prunedRelPaths,
  ) {
    final Directory srcLib = source.directory.childDirectory('lib');
    final Directory dstLib = outputDirectory.childDirectory('lib');
    List<_Plan> stub() => <_Plan>[
          _Plan(
            path: dstLib.childFile('${source.outputPackageName}.dart').path,
            contents:
                tmpl.renderDartEntry(source: source, licenseHolder: licenseHolder),
          ),
        ];
    if (!srcLib.existsSync()) {
      return stub();
    }

    // Pass 1: enumerate every .dart file relative to `lib/` and split it
    // into kept vs. pruned. `rel` is the path inside `lib/`; the entry
    // file rename to `<out>.dart` happens later when emitting plans, so
    // pruning decisions are made on the un-renamed source path.
    final List<String> keptRel = <String>[];
    final List<String> droppedRel = <String>[];
    for (final FileSystemEntity e in srcLib.listSync(recursive: true)) {
      if (e is! File || _fs.path.extension(e.path).toLowerCase() != '.dart') {
        continue;
      }
      final String rel = _fs.path
          .relative(e.path, from: srcLib.path)
          .replaceAll(r'\', '/');
      if (_isCrossPlatformDart(rel)) {
        droppedRel.add(rel);
      } else {
        keptRel.add(rel);
      }
    }
    prunedRelPaths.addAll(droppedRel..sort());

    // Pre-compute the set of pruned-file *destination* paths relative to
    // `lib/` so the sanitiser can match `import './src/foo_linux.dart'`
    // and `import 'package:<out>/src/foo_linux.dart'` against it.
    final Set<String> droppedSet = droppedRel.toSet();

    final List<_Plan> plans = <_Plan>[];
    for (final String rel in keptRel) {
      final File srcFile = _fs.file(_fs.path.join(srcLib.path, rel));
      final String destRel = rel == '${source.packageName}.dart'
          ? '${source.outputPackageName}.dart'
          : rel;
      String content = srcFile.readAsStringSync().replaceAll(
            'package:${source.packageName}/',
            'package:${source.outputPackageName}/',
          );
      if (droppedSet.isNotEmpty) {
        content = _scrubReferencesToDropped(
          source: content,
          fromRel: rel,
          droppedRelPaths: droppedSet,
          srcPackageName: source.packageName,
          outPackageName: source.outputPackageName,
        );
      }
      plans.add(_Plan(
        path: _fs.path.join(dstLib.path, destRel),
        contents: content,
      ));
    }
    return plans.isEmpty ? stub() : plans;
  }

  /// True for a Dart file under `lib/` whose path/name marks it as a
  /// non-Apple platform-specific implementation we don't want shipped in
  /// the `_tvos` federated package.
  ///
  /// Two signals — either is sufficient:
  /// - A path segment names a non-Apple platform we don't ship for
  ///   (`web`, `web_impl`, `windows`, `linux`, `android`).
  /// - The basename ends in a non-Apple platform suffix
  ///   (`_linux.dart`, `_windows.dart`, `_web.dart`, `_android.dart`,
  ///   `_macos.dart`, `_osx.dart`, optionally with a `_plugin` tail), or
  ///   `_io_plugin.dart` (the `wakelock_plus` convention for the
  ///   non-web/non-platform-specific fallback that fans out to Linux/
  ///   macOS/Windows).
  ///
  /// `_ios*` is deliberately kept — `IosDeviceInfo`, `AVFoundation*` and
  /// similar Apple-shared classes are usable on tvOS (UIKit/UIDevice/
  /// AVFoundation exist there).
  bool _isCrossPlatformDart(String relPath) {
    final String normalized = relPath.toLowerCase().replaceAll(r'\', '/');
    const Set<String> nonApplePathSegments = <String>{
      'web',
      'web_impl',
      'windows',
      'linux',
      'android',
    };
    for (final String segment in normalized.split('/')) {
      if (nonApplePathSegments.contains(segment)) {
        return true;
      }
    }
    final String base = normalized.split('/').last;
    final RegExp suffix = RegExp(
      r'_(linux|windows|web|android|macos|osx|io)(?:_plugin)?\.dart$',
    );
    return suffix.hasMatch(base);
  }

  /// Removes any `import` / `export` directive in [source] whose target
  /// path resolves to one of the [droppedRelPaths]. Handles three forms:
  ///
  /// 1. Plain relative: `import 'src/foo_linux.dart';`
  /// 2. Self-package: `import 'package:<out>/src/foo_linux.dart';`
  ///    (already rewritten from `package:<src>/...` by the caller — we
  ///    also match the unrewritten form as a safety net).
  /// 3. Conditional: `export 'src/foo_io.dart' if (dart.library.js_interop) 'src/foo_web.dart';`
  ///    — if either branch points at a dropped file the whole directive
  ///    is removed (a half-conditional has no meaning).
  ///
  /// Removed directives become `// (pruned)` comment placeholders so
  /// line numbers in user-visible source stay stable.
  String _scrubReferencesToDropped({
    required String source,
    required String fromRel,
    required Set<String> droppedRelPaths,
    required String srcPackageName,
    required String outPackageName,
  }) {
    if (droppedRelPaths.isEmpty) {
      return source;
    }

    // Normalise a path captured from an import/export literal into the
    // same "relative-to-lib/" form droppedRelPaths uses. Returns null
    // when the literal targets something outside `lib/` (e.g. an
    // `import 'package:foo/bar.dart';` where `foo` isn't this package).
    String? resolveToLibRel(String literal) {
      final String trimmed = literal.trim();
      // package: form — only ours counts.
      const String pkgPrefix = 'package:';
      if (trimmed.startsWith(pkgPrefix)) {
        final String rest = trimmed.substring(pkgPrefix.length);
        final int slash = rest.indexOf('/');
        if (slash < 0) {
          return null;
        }
        final String pkg = rest.substring(0, slash);
        if (pkg != outPackageName && pkg != srcPackageName) {
          return null;
        }
        return rest.substring(slash + 1);
      }
      // Relative form — resolve against the importer's directory.
      final String fromDir = fromRel.contains('/')
          ? fromRel.substring(0, fromRel.lastIndexOf('/'))
          : '';
      final List<String> parts = <String>[
        if (fromDir.isNotEmpty) ...fromDir.split('/'),
        ...trimmed.split('/'),
      ];
      final List<String> stack = <String>[];
      for (final String part in parts) {
        if (part.isEmpty || part == '.') {
          continue;
        }
        if (part == '..') {
          if (stack.isNotEmpty) {
            stack.removeLast();
          }
          continue;
        }
        stack.add(part);
      }
      return stack.join('/');
    }

    // One regex covers `import 'X';`, `export 'X';`, `part 'X';`, and the
    // conditional form with up to one `if (...) 'Y'` fork.
    // `part of 'parent.dart'` is intentionally excluded: the `of` keyword
    // sits between `part` and the opening quote, so it does not match
    // `(import|export|part)\s+(['"])`.
    final RegExp directive = RegExp(
      r"""^(\s*)(import|export|part)\s+(['"])([^'"]+)\3"""
      r"""(\s+if\s*\(\s*[^)]*\)\s+(['"])([^'"]+)\6)?"""
      r"""([^;\n]*);?\s*$""",
      multiLine: true,
    );

    return source.replaceAllMapped(directive, (Match m) {
      final String primary = m.group(4)!;
      final String? fallback = m.group(7);
      bool targetsDropped(String? literal) {
        if (literal == null) {
          return false;
        }
        final String? resolved = resolveToLibRel(literal);
        return resolved != null && droppedRelPaths.contains(resolved);
      }

      if (!targetsDropped(primary) && !targetsDropped(fallback)) {
        return m.group(0)!;
      }
      // Preserve indentation so blank-line padding in the file is stable.
      final String indent = m.group(1) ?? '';
      return '$indent// (pruned by flutter-tvos plugin port: '
          'cross-platform Dart not used on tvOS)';
    });
  }

  /// Walks the source's `<platform>/Classes/` directory and produces a list
  /// of (source-file → destination-path) pairs covering every Swift / ObjC
  /// source. Subdirectory structure is preserved relative to `Classes/`.
  ///
  /// Returns an empty list when the source has no copyable native files —
  /// caller falls back to writing a stub.
  ///
  /// For a *modular* multi-target SwiftPM package (see
  /// [PluginSource.isMultiTargetSpm]) every sibling target under the
  /// shared `Sources/` directory is copied — preserving each target's
  /// internal structure under `Classes/<target>/…` so the targets'
  /// quoted/relative `#import "…/Foo.h"` paths keep resolving and the
  /// generated podspec can collapse them into one CocoaPods module
  /// exactly the way the upstream package's own podspec does. The
  /// macOS-only platform target is dropped: tvOS shares UIKit with iOS,
  /// so the `<pkg>_ios` target is the right sibling to keep.
  List<_NativeCopy> _collectNativeCopies(PluginSource source, Directory destination) {
    const Set<String> nativeExt = <String>{'.swift', '.h', '.m', '.mm'};
    if (source.isMultiTargetSpm) {
      final Directory root = source.spmSourcesRoot!;
      if (!root.existsSync()) {
        return const <_NativeCopy>[];
      }
      final copies = <_NativeCopy>[];
      for (final FileSystemEntity target in root.listSync()) {
        if (target is! Directory) {
          continue;
        }
        final String name = _fs.path.basename(target.path);
        if (_isMacosOnlyTarget(name)) {
          // macOS-only target (AppKit/Cocoa, CVDisplayLink, …) — not
          // tvOS-compatible. tvOS takes the iOS sibling instead.
          _log.printTrace('  skipping macOS-only SwiftPM target: $name');
          continue;
        }
        copies.addAll(_collectByExtension(
          target,
          destination.childDirectory(name),
          nativeExt,
        ));
      }
      return copies;
    }
    if (!source.classesDirectory.existsSync()) {
      return const <_NativeCopy>[];
    }
    return _collectByExtension(
      source.classesDirectory,
      destination,
      nativeExt,
    );
  }

  /// True for a SwiftPM target whose code is macOS-only — by the
  /// `flutter/packages` convention these targets are suffixed `_macos`
  /// (or, rarely, `_osx`). They use AppKit/Cocoa and macOS-only display
  /// link APIs the tvOS toolchain can't build; the matching `_ios`
  /// sibling is UIKit-based and is what tvOS uses.
  bool _isMacosOnlyTarget(String targetDirName) {
    final String n = targetDirName.toLowerCase();
    return n.endsWith('_macos') || n.endsWith('_osx');
  }

  /// Returns the source's `<platform>/Resources/` directory if it exists,
  /// otherwise null. The plugin's `pubspec.yaml` doesn't tell us where
  /// Resources live; we look in the conventional location next to the
  /// `Classes/` directory we already analysed.
  Directory? _resolveResourcesDir(PluginSource source) {
    // Legacy layout: `<platform>/Resources/` next to `<platform>/Classes/`.
    // SwiftPM layout: `Sources/<target>/Resources/` *inside* the target
    // directory (declared via `.process("Resources")` in Package.swift).
    for (final Directory candidate in <Directory>[
      source.classesDirectory.parent.childDirectory('Resources'),
      source.classesDirectory.childDirectory('Resources'),
    ]) {
      if (candidate.existsSync()) {
        return candidate;
      }
    }
    return null;
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
      // SPM manifests are not plugin code and must not land in the
      // podspec's `Classes/` glob.
      final String base = _fs.path.basename(entity.path);
      if (base == 'Package.swift' || base == 'Package.resolved') {
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
    required this.prunedDartFiles,
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

  /// Source-relative paths (under the upstream package's `lib/`) of
  /// Dart files the porter dropped because they target a non-Apple
  /// platform (Linux / Windows / Web / macOS / Android). Empty for
  /// Apple-only source plugins. The report's "Cross-platform Dart
  /// pruned" section is rendered from this list.
  final List<String> prunedDartFiles;

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

/// A native source run through [SwiftPorter] or [ObjcPorter]. Unlike
/// [_NativeCopy] the bytes written are the *transformed* content, not a
/// verbatim copy — so the verbose log says "ported X" not "copied X".
class _PortedFile {
  _PortedFile({required this.destinationPath, required this.contents});
  final String destinationPath;
  final String contents;
}
