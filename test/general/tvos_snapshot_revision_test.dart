// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show Process, ProcessResult;

import 'package:file/file.dart';
import 'package:file/local.dart';

import '../src/common.dart';

/// `tool_revision` in `bin/internal/shared.sh` decides whether the compiled
/// CLI snapshot is stale. Getting it wrong is uniquely nasty to debug,
/// because the CLI then runs the *previously compiled* snapshot: an edit
/// appears to do nothing and reproduces the identical failure byte for byte,
/// which reads as a wrong fix rather than a fix that never ran.
///
/// These drive the real function in a throwaway git repository.
void main() {
  const FileSystem fs = LocalFileSystem();
  late Directory root;

  String revision() {
    final ProcessResult r = Process.runSync('bash', <String>[
      '-c',
      r'BIN_DIR="$PWD/bin"; ROOT_DIR="$PWD"; source bin/internal/shared.sh >/dev/null 2>&1; tool_revision',
    ], workingDirectory: root.path);
    expect(r.exitCode, 0, reason: 'tool_revision failed: ${r.stderr}');
    return (r.stdout as String).trim();
  }

  void git(List<String> args) {
    final ProcessResult r = Process.runSync('git', args, workingDirectory: root.path);
    expect(r.exitCode, 0, reason: 'git ${args.join(' ')} failed: ${r.stderr}');
  }

  void write(String relative, String contents) {
    root.childFile(relative).parent.createSync(recursive: true);
    root.childFile(relative).writeAsStringSync(contents);
  }

  String head() {
    final ProcessResult r =
        Process.runSync('git', <String>['rev-parse', 'HEAD'], workingDirectory: root.path);
    return (r.stdout as String).trim();
  }

  setUp(() {
    final Directory created =
        fs.systemTempDirectory.createTempSync('tvos_revision_test.');
    addTearDown(() => created.deleteSync(recursive: true));
    // Resolved, not as created. The harness's filesystem guard compares paths
    // lexically against the system temp directory, and on macOS /var is a
    // symlink to /private/var -- so the unresolved path is judged to be
    // outside the very temp directory it is inside.
    root = fs.directory(created.resolveSymbolicLinksSync());
    // The function under test, verbatim from this checkout.
    write('bin/internal/shared.sh',
        fs.file('bin/internal/shared.sh').readAsStringSync());
    write('lib/thing.dart', 'void main() {}\n');
    write('bin/flutter_tvos.dart', 'void main() {}\n');
    write('pubspec.yaml', 'name: flutter_tvos\n');
    write('README.md', 'docs\n');
    git(<String>['init', '-q']);
    git(<String>['config', 'user.email', 'test@example.com']);
    git(<String>['config', 'user.name', 'test']);
    git(<String>['add', '.']);
    git(<String>['commit', '-q', '-m', 'initial']);
  });

  testWithoutContext('a clean checkout returns the bare HEAD sha', () {
    // The common case, and the one that must not change: anyone who is not
    // editing the CLI should see exactly what they saw before.
    expect(revision(), head());
    expect(revision().length, 40);
  });

  testWithoutContext('an edit under lib/ changes the revision', () {
    // The bug this fixes. HEAD alone cannot see uncommitted work, so the
    // snapshot was never rebuilt and the edit silently did not run.
    final String before = revision();
    write('lib/thing.dart', 'void main() { print("changed"); }\n');
    expect(revision(), isNot(before));
  });

  testWithoutContext('an edit under bin/ changes the revision', () {
    final String before = revision();
    write('bin/flutter_tvos.dart', 'void main() { print("changed"); }\n');
    expect(revision(), isNot(before));
  });

  testWithoutContext('a new untracked source changes the revision', () {
    // Adding a file is as much a source change as editing one, and a diff
    // alone would not see it -- which is why the status output is hashed too.
    final String before = revision();
    write('lib/added.dart', 'void main() {}\n');
    expect(revision(), isNot(before));
  });

  testWithoutContext('two different edits to one file do not collide', () {
    // Hashing only names and statuses would give these the same revision, and
    // the second edit would run against the first one's snapshot.
    write('lib/thing.dart', 'void main() { print("a"); }\n');
    final String a = revision();
    write('lib/thing.dart', 'void main() { print("b"); }\n');
    expect(revision(), isNot(a));
  });

  testWithoutContext('the revision is deterministic, not a nonce', () {
    // It has to be stable across calls, or every invocation recompiles.
    write('lib/thing.dart', 'void main() { print("changed"); }\n');
    expect(revision(), revision());
  });

  testWithoutContext('reverting an edit restores the clean revision', () {
    final String clean = revision();
    write('lib/thing.dart', 'void main() { print("changed"); }\n');
    expect(revision(), isNot(clean));
    write('lib/thing.dart', 'void main() {}\n');
    expect(revision(), clean);
  });

  testWithoutContext('edits outside the snapshot do not force a recompile', () {
    // A README or a test does not go into the snapshot; recompiling for them
    // would make every documentation edit cost a rebuild.
    final String before = revision();
    write('README.md', 'different docs\n');
    write('test/some_test.dart', 'void main() {}\n');
    expect(revision(), before);
  });

  testWithoutContext('committing the edit returns to a bare sha', () {
    write('lib/thing.dart', 'void main() { print("committed"); }\n');
    final String dirty = revision();
    expect(dirty.length, greaterThan(40), reason: 'a dirty tree carries a suffix');
    git(<String>['add', '.']);
    git(<String>['commit', '-q', '-m', 'second']);
    expect(revision(), head());
    expect(revision().length, 40);
    expect(revision(), isNot(dirty));
  });
}
