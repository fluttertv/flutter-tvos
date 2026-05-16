// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';

/// Builds a federated `*_tvos` package's `example/` the way
/// flutter-tizen/plugins does: reuse the **app-facing** plugin's real
/// example app (its `lib/`, assets, deps) so it actually demonstrates
/// and exercises the plugin — then make it tvOS-only and point it at
/// the freshly generated platform implementation.
///
/// The resulting `example/pubspec.yaml` depends on BOTH:
///
/// ```yaml
/// dependencies:
///   <base>: ^<version>          # the API the example code imports
///   <base>_tvos:                # the federated impl under test
///     path: ../
/// ```
///
/// Non-tvOS platform folders from the upstream example are dropped; the
/// caller renders `tvos/` on top. Pure FileSystem work — unit-testable.
class ExamplePorter {
  ExamplePorter({required FileSystem fileSystem}) : _fs = fileSystem;

  final FileSystem _fs;

  /// Top-level entries in the upstream example we never copy: other
  /// platforms and throwaway/build state.
  static const Set<String> _skipTopLevel = <String>{
    'android', 'ios', 'macos', 'linux', 'windows', 'web',
    '.dart_tool', 'build', '.idea', '.git',
  };
  static const Set<String> _skipFiles = <String>{
    'pubspec.lock', '.flutter-plugins', '.flutter-plugins-dependencies',
    '.metadata',
  };

  /// Copies `<basePluginDir>/example` into `<outputPackageDir>/example`
  /// (tvOS-only) and rewrites its pubspec to the dual-dependency form.
  ///
  /// Returns a skipped result (never throws) when the app-facing plugin
  /// ships no usable example.
  ExamplePortResult port({
    required Directory basePluginDir,
    required Directory outputPackageDir,
    required String baseName,
    required String tvosPackageName,
    required String baseVersion,
  }) {
    final Directory src = basePluginDir.childDirectory('example');
    if (!src.existsSync() ||
        !src.childDirectory('lib').existsSync() ||
        !src.childFile('pubspec.yaml').existsSync()) {
      return ExamplePortResult.skipped(
        '$baseName ships no usable example/ (no lib/ or pubspec.yaml); '
        'skipping example generation.',
      );
    }

    final Directory dst = outputPackageDir.childDirectory('example');
    if (dst.existsSync()) {
      dst.deleteSync(recursive: true);
    }
    dst.createSync(recursive: true);

    final List<String> copied = <String>[];
    for (final FileSystemEntity entity in src.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final String rel = _fs.path.relative(entity.path, from: src.path);
      final List<String> parts = _fs.path.split(rel);
      if (_skipTopLevel.contains(parts.first)) {
        continue;
      }
      if (_skipFiles.contains(_fs.path.basename(rel)) ||
          _fs.path.basename(rel).endsWith('.iml')) {
        continue;
      }
      final File out = _fs.file(_fs.path.join(dst.path, rel))
        ..parent.createSync(recursive: true);
      entity.copySync(out.path);
      copied.add(rel);
    }

    final File pubspec = dst.childFile('pubspec.yaml');
    pubspec.writeAsStringSync(
      _rewritePubspec(
        pubspec.readAsStringSync(),
        baseName: baseName,
        baseVersion: baseVersion,
        tvosPackageName: tvosPackageName,
      ),
    );

    return ExamplePortResult(
      skipped: false,
      reason: null,
      exampleDirectory: dst,
      copiedRelativePaths: copied,
    );
  }

  /// Forces the example to depend on the app-facing plugin (pinned to the
  /// resolved version) and the local federated impl, replacing any
  /// existing entries for those two names (the upstream monorepo example
  /// often points `<base>` at a sibling `path:` that won't exist here).
  String _rewritePubspec(
    String pubspec, {
    required String baseName,
    required String baseVersion,
    required String tvosPackageName,
  }) {
    final List<String> lines = pubspec.split('\n');
    final int depsIdx = lines.indexWhere(
      (String l) => RegExp(r'^dependencies:\s*$').hasMatch(l),
    );
    if (depsIdx == -1) {
      // No dependencies block — append a complete one.
      final String sep = pubspec.endsWith('\n') ? '' : '\n';
      return '$pubspec$sep\ndependencies:\n'
          '  flutter:\n    sdk: flutter\n'
          '  $baseName: ^$baseVersion\n'
          '  $tvosPackageName:\n    path: ../\n';
    }

    // Find the end of the dependencies block (next col-0 line).
    int end = lines.length;
    for (var i = depsIdx + 1; i < lines.length; i++) {
      final String l = lines[i];
      if (l.isNotEmpty && !l.startsWith(' ') && !l.startsWith('\t')) {
        end = i;
        break;
      }
    }

    bool isManagedKey(String line) {
      final RegExpMatch? m = RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line);
      return m != null &&
          (m.group(1) == baseName || m.group(1) == tvosPackageName);
    }

    final List<String> kept = <String>[];
    for (var i = depsIdx + 1; i < end; i++) {
      if (isManagedKey(lines[i])) {
        // Skip this key and its indented continuation lines.
        var j = i + 1;
        while (j < end &&
            lines[j].startsWith('    ') &&
            lines[j].trim().isNotEmpty) {
          j++;
        }
        i = j - 1;
        continue;
      }
      kept.add(lines[i]);
    }

    final List<String> rebuilt = <String>[
      ...lines.sublist(0, depsIdx + 1),
      '  $baseName: ^$baseVersion',
      '  $tvosPackageName:',
      '    path: ../',
      ...kept,
      ...lines.sublist(end),
    ];
    return rebuilt.join('\n');
  }
}

/// Outcome of [ExamplePorter.port].
class ExamplePortResult {
  ExamplePortResult({
    required this.skipped,
    required this.reason,
    required this.exampleDirectory,
    required this.copiedRelativePaths,
  });

  ExamplePortResult.skipped(String this.reason)
      : skipped = true,
        exampleDirectory = null,
        copiedRelativePaths = const <String>[];

  final bool skipped;
  final String? reason;
  final Directory? exampleDirectory;
  final List<String> copiedRelativePaths;
}
