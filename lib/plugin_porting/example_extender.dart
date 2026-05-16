// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';

import 'source_analyzer.dart';

/// `--include-example` support.
///
/// Most plugin authors test changes through the plugin's own `example/`
/// app. Adding tvOS to that app makes a fresh port immediately runnable.
/// This extender owns the deterministic, side-effecting edits to the
/// SOURCE plugin's `example/` (never the generated `*_tvos` package):
///
///   1. validate `example/` (has `lib/main.dart` and a Flutter pubspec),
///   2. merge `dependency_overrides` so the example resolves the source
///      `*_ios` and the freshly generated `*_tvos` from local paths,
///   3. append a one-line "run on tvOS" note to `example/README.md`.
///
/// Generating `example/tvos/` itself is delegated: it goes through the
/// existing `flutter-tvos create` template subsystem (on-disk templates,
/// signing detection), which is not reproducible under an in-memory test
/// filesystem. [ExampleExtendResult.createCommand] is the exact command
/// to run for that step; the porter surfaces it to the user.
class ExampleExtender {
  ExampleExtender({required FileSystem fileSystem}) : _fs = fileSystem;

  final FileSystem _fs;

  /// Marker appended to `example/README.md`. Used to keep the append
  /// idempotent across repeated ports.
  static const String readmeNote = 'On tvOS: run `flutter-tvos run`.';

  /// Mutates [source]'s `example/` so it can run on tvOS against the
  /// just-generated package at [outputPackageDir].
  ///
  /// Never throws for an unusable example — returns a skipped result with
  /// a human reason so a missing/odd example doesn't fail the whole port.
  /// When [dryRun] is true nothing is written; the result still reports
  /// what *would* change.
  ExampleExtendResult extend({
    required PluginSource source,
    required Directory outputPackageDir,
    bool dryRun = false,
  }) {
    final Directory exampleDir = source.directory.childDirectory('example');
    if (!exampleDir.existsSync()) {
      return ExampleExtendResult.skipped(
        'No example/ directory in ${source.packageName}; nothing to extend.',
      );
    }
    final File mainDart =
        exampleDir.childDirectory('lib').childFile('main.dart');
    final File examplePubspec = exampleDir.childFile('pubspec.yaml');
    if (!mainDart.existsSync() || !examplePubspec.existsSync()) {
      return ExampleExtendResult.skipped(
        'example/ is missing lib/main.dart or pubspec.yaml; skipping '
        '--include-example.',
      );
    }

    final String relSource =
        _fs.path.relative(source.directory.path, from: exampleDir.path);
    final String relTvos =
        _fs.path.relative(outputPackageDir.path, from: exampleDir.path);

    final String originalPubspec = examplePubspec.readAsStringSync();
    final String newPubspec = _mergeDependencyOverrides(
      originalPubspec,
      <String, String>{
        source.packageName: relSource,
        source.outputPackageName: relTvos,
      },
    );

    final File readme = exampleDir.childFile('README.md');
    final String originalReadme =
        readme.existsSync() ? readme.readAsStringSync() : '';
    final bool readmeNeedsNote = !originalReadme.contains(readmeNote);
    final String newReadme = readmeNeedsNote
        ? '${originalReadme.trimRight()}\n\n$readmeNote\n'
        : originalReadme;

    final List<String> wrote = <String>[];
    if (newPubspec != originalPubspec) {
      wrote.add(examplePubspec.path);
    }
    if (readmeNeedsNote) {
      wrote.add(readme.path);
    }

    if (!dryRun) {
      if (newPubspec != originalPubspec) {
        examplePubspec.writeAsStringSync(newPubspec);
      }
      if (readmeNeedsNote) {
        readme.writeAsStringSync(newReadme);
      }
    }

    // The `tvos/` scaffold itself is produced by the existing create
    // template subsystem — surfaced as a command, not run here.
    final String createCommand =
        'cd ${exampleDir.path} && flutter-tvos create --org com.example '
        '--project-name ${source.basePackageName}_example .';

    return ExampleExtendResult(
      skipped: false,
      reason: null,
      exampleDirectory: exampleDir,
      writtenPaths: wrote,
      createCommand: createCommand,
      dryRun: dryRun,
    );
  }

  /// Inserts `path:` overrides for [overrides] (name → path) under a
  /// `dependency_overrides:` block, creating the block if absent and
  /// skipping names already present (idempotent across re-ports).
  String _mergeDependencyOverrides(
    String pubspec,
    Map<String, String> overrides,
  ) {
    final StringBuffer entries = StringBuffer();
    for (final MapEntry<String, String> e in overrides.entries) {
      // Already overridden? Leave the user's version alone.
      if (RegExp('^  ${RegExp.escape(e.key)}:', multiLine: true)
          .hasMatch(pubspec)) {
        continue;
      }
      entries
        ..writeln('  ${e.key}:')
        ..writeln('    path: ${e.value}');
    }
    if (entries.isEmpty) {
      return pubspec;
    }

    final RegExp blockHeader =
        RegExp(r'^dependency_overrides:[ \t]*\n', multiLine: true);
    final Match? header = blockHeader.firstMatch(pubspec);
    if (header != null) {
      // Insert right after the existing header line.
      return pubspec.replaceRange(
        header.end,
        header.end,
        entries.toString(),
      );
    }
    final String sep = pubspec.endsWith('\n') ? '' : '\n';
    return '$pubspec${sep}\ndependency_overrides:\n$entries';
  }
}

/// Outcome of [ExampleExtender.extend].
class ExampleExtendResult {
  ExampleExtendResult({
    required this.skipped,
    required this.reason,
    required this.exampleDirectory,
    required this.writtenPaths,
    required this.createCommand,
    required this.dryRun,
  });

  ExampleExtendResult.skipped(String this.reason)
      : skipped = true,
        exampleDirectory = null,
        writtenPaths = const <String>[],
        createCommand = null,
        dryRun = false;

  /// True when the example couldn't be extended (missing/odd example).
  /// Not an error — the port still succeeds.
  final bool skipped;

  /// Why it was skipped, or `null` when [skipped] is false.
  final String? reason;

  /// The located `example/` directory, or `null` when skipped.
  final Directory? exampleDirectory;

  /// Files written (or that would be written under `--dry-run`).
  final List<String> writtenPaths;

  /// Exact `flutter-tvos create` command to generate `example/tvos/`, or
  /// `null` when skipped.
  final String? createCommand;

  final bool dryRun;
}
