// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show Process, ProcessResult;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_tvos/tvos_releases.dart';

import '../src/common.dart';

/// Verifies against real git, not a fake.
///
/// `TvosReleases.list` and the shipped `upgrade` both rely on
/// `--sort=-v:refname` putting our tags newest-first, and a fake process
/// manager cannot check that — it would just replay whatever order we assumed.
/// git's `versionsort.suffix` can change how the `-tvos.N` suffix is ranked, so
/// the assumption is worth one real-git test.
void main() {
  test('git sorts flutter-tvos release tags newest-first', () async {
    // A real directory, because git needs one. `const LocalFileSystem()` from
    // package:file/local.dart is how test/general/tvos_app_bundle_test.dart
    // already reaches the real file system in this suite.
    const fs = LocalFileSystem();
    final Directory repo = fs.systemTempDirectory.createTempSync('tvos_sort_test.');
    addTearDown(() => repo.deleteSync(recursive: true));

    Future<ProcessResult> git(List<String> args) =>
        Process.run('git', args, workingDirectory: repo.path);

    await git(<String>['init', '--quiet']);
    await git(<String>['config', 'user.email', 'test@example.com']);
    await git(<String>['config', 'user.name', 'Test']);
    await git(<String>['commit', '--allow-empty', '-m', 'base', '--quiet']);

    // Deliberately created out of order, so a no-op sort would fail this test.
    for (final String tag in <String>[
      'v3.44.5-tvos.1.3.3',
      'v3.32.8-tvos.1.0.0',
      'v3.44.7-tvos.1.4.2',
      'v3.44.5-tvos.1.4.0',
      'nightly',
    ]) {
      await git(<String>['tag', tag]);
    }

    final ProcessResult result = await git(<String>['tag', '-l', '--sort=-v:refname']);
    final List<String> tags = (result.stdout as String)
        .trim()
        .split('\n')
        .map((String s) => s.trim())
        .toList();
    final List<TvosRelease> releases =
        tags.map(TvosRelease.parse).whereType<TvosRelease>().toList();

    expect(releases.map((TvosRelease r) => r.tag), <String>[
      'v3.44.7-tvos.1.4.2',
      'v3.44.5-tvos.1.4.0', // newer tool version of the same Flutter version
      'v3.44.5-tvos.1.3.3',
      'v3.32.8-tvos.1.0.0',
    ]);
  });
}
