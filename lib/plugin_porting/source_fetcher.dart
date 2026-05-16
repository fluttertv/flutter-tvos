// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart' show ProcessResult;
import 'package:flutter_tools/src/base/logger.dart';
import 'package:process/process.dart';

/// Where the source plugin comes from.
enum FetchMode {
  /// A directory already on disk (the default positional argument).
  localPath,

  /// A package downloaded from pub.dev (`--from-pub <name>`).
  pub,

  /// A git repository cloned on demand (`--from-git <url> [--ref X]`).
  git,
}

/// Pure, validated description of `--from-pub` / `--from-git` / positional
/// source arguments. Construction is the single place the
/// mutually-exclusive rules live, so it unit-tests without any I/O.
class SourceSpec {
  SourceSpec._(this.mode, this.identifier, this.ref);

  /// Validates the three input forms. Exactly one of [positional],
  /// [fromPub], [fromGit] must be set; [ref] is only valid with
  /// [fromGit]. Throws [SourceFetchError] with an actionable message
  /// otherwise.
  factory SourceSpec.parse({
    String? positional,
    String? fromPub,
    String? fromGit,
    String? ref,
  }) {
    String? norm(String? s) => (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    positional = norm(positional);
    fromPub = norm(fromPub);
    fromGit = norm(fromGit);
    ref = norm(ref);

    final int count =
        (positional != null ? 1 : 0) + (fromPub != null ? 1 : 0) + (fromGit != null ? 1 : 0);
    if (count == 0) {
      throw SourceFetchError(
        'No source given. Pass a plugin directory, or --from-pub <name>, '
        'or --from-git <url>.',
      );
    }
    if (count > 1) {
      throw SourceFetchError(
        'Pass exactly one source: a directory, --from-pub, or --from-git '
        '(not more than one).',
      );
    }
    if (ref != null && fromGit == null) {
      throw SourceFetchError('--ref is only valid together with --from-git.');
    }
    if (fromGit != null) {
      return SourceSpec._(FetchMode.git, fromGit, ref);
    }
    if (fromPub != null) {
      return SourceSpec._(FetchMode.pub, fromPub, null);
    }
    return SourceSpec._(FetchMode.localPath, positional!, null);
  }

  final FetchMode mode;

  /// Directory path (local), package name (pub), or clone URL (git).
  final String identifier;

  /// Git ref to check out, or `null`. Only meaningful for [FetchMode.git].
  final String? ref;

  /// Repo/package basename used to name the checkout directory, e.g.
  /// `https://github.com/foo/url_launcher.git` → `url_launcher`.
  String get derivedName {
    if (mode == FetchMode.pub) {
      return identifier;
    }
    var last = identifier.split('/').where((String s) => s.isNotEmpty).last;
    if (last.endsWith('.git')) {
      last = last.substring(0, last.length - 4);
    }
    return last.isEmpty ? 'source' : last;
  }

  /// `git clone` argv targeting [destPath]. Shallow; honours [ref].
  List<String> gitCloneArgs(String destPath) => <String>[
        'git',
        'clone',
        '--depth',
        '1',
        if (ref != null) ...<String>['--branch', ref!],
        identifier,
        destPath,
      ];
}

/// Resolves a [SourceSpec] to an on-disk directory the rest of the porter
/// can analyse. `localPath` returns immediately; `git`/`pub` shell out.
class SourceFetcher {
  SourceFetcher({
    required FileSystem fileSystem,
    required ProcessManager processManager,
    required Logger logger,
  })  : _fs = fileSystem,
        _pm = processManager,
        _log = logger;

  final FileSystem _fs;
  final ProcessManager _pm;
  final Logger _log;

  /// Returns the source directory for [spec]. For remote modes the content
  /// is materialised under [workDir] (caller owns cleanup of that dir).
  Future<Directory> resolve(SourceSpec spec, {required Directory workDir}) async {
    switch (spec.mode) {
      case FetchMode.localPath:
        final Directory d = _fs.directory(_fs.path.absolute(spec.identifier));
        if (!d.existsSync()) {
          throw SourceFetchError('Source directory does not exist: ${d.path}');
        }
        return d;
      case FetchMode.git:
        return _fetchGit(spec, workDir);
      case FetchMode.pub:
        return _fetchPub(spec, workDir);
    }
  }

  Future<Directory> _fetchGit(SourceSpec spec, Directory workDir) async {
    final Directory dest = workDir.childDirectory(spec.derivedName);
    _log.printStatus('Cloning ${spec.identifier}'
        '${spec.ref != null ? ' @ ${spec.ref}' : ''} …');
    final ProcessResult r = await _pm.run(
      spec.gitCloneArgs(dest.path),
      workingDirectory: workDir.path,
    );
    if (r.exitCode != 0) {
      throw SourceFetchError(
        'git clone failed (exit ${r.exitCode}):\n${r.stderr}',
      );
    }
    if (!dest.existsSync()) {
      throw SourceFetchError(
        'git clone reported success but ${dest.path} is missing.',
      );
    }
    return dest;
  }

  Future<Directory> _fetchPub(SourceSpec spec, Directory workDir) async {
    // pub has no "download one package's source" command, so resolve it
    // through a throwaway probe project and read the resolved location
    // out of package_config.json.
    final Directory probe = workDir.childDirectory('_pub_probe')
      ..createSync(recursive: true);
    probe.childFile('pubspec.yaml').writeAsStringSync('''
name: _flutter_tvos_port_probe
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  ${spec.identifier}: any
''');
    _log.printStatus('Fetching ${spec.identifier} from pub.dev …');
    final ProcessResult r = await _pm.run(
      <String>['dart', 'pub', 'get'],
      workingDirectory: probe.path,
    );
    if (r.exitCode != 0) {
      throw SourceFetchError(
        '`dart pub get` failed for ${spec.identifier} (exit ${r.exitCode}):\n'
        '${r.stderr}',
      );
    }
    final File cfg = probe
        .childDirectory('.dart_tool')
        .childFile('package_config.json');
    if (!cfg.existsSync()) {
      throw SourceFetchError(
        'pub did not write package_config.json; cannot locate '
        '${spec.identifier}.',
      );
    }
    final Directory resolved = _packageRoot(cfg, spec.identifier);
    if (!resolved.existsSync()) {
      throw SourceFetchError(
        'Resolved ${spec.identifier} to ${resolved.path}, which does not '
        'exist.',
      );
    }
    return resolved;
  }

  /// Reads `package_config.json` and returns the on-disk root directory of
  /// [packageName]. `rootUri` is relative to the `.dart_tool/` directory
  /// per the package-config spec.
  Directory _packageRoot(File packageConfig, String packageName) {
    final Object? decoded = jsonDecode(packageConfig.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw SourceFetchError('Malformed package_config.json.');
    }
    final Object? packages = decoded['packages'];
    if (packages is! List<Object?>) {
      throw SourceFetchError('package_config.json has no packages list.');
    }
    for (final Object? p in packages) {
      if (p is Map<String, Object?> && p['name'] == packageName) {
        final String rootUri = (p['rootUri'] ?? '') as String;
        final Uri base = packageConfig.parent.uri;
        final Uri resolved = base.resolveUri(Uri.parse(rootUri));
        return _fs.directory(
          resolved.scheme == 'file' ? resolved.toFilePath() : resolved.path,
        );
      }
    }
    throw SourceFetchError(
      '${packageName} not found in package_config.json — does it exist on '
      'pub.dev?',
    );
  }
}

/// Thrown for any invalid source argument or failed fetch. Carries a
/// user-facing message; the command turns it into a clean tool exit.
class SourceFetchError implements Exception {
  SourceFetchError(this.message);
  final String message;
  @override
  String toString() => 'SourceFetchError: $message';
}
