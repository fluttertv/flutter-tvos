# CLI Version Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user switch the flutter-tvos toolchain between supported Flutter versions with `flutter-tvos versions` and `flutter-tvos use <version>`.

**Architecture:** Each supported Flutter version is a release line of this repo, tagged `v<flutter>-tvos.<tool>`; the tag carries both the CLI source ported to that version's `flutter_tools` API and the two pin files. Switching is therefore a `git reset --hard` to a tag, after which the existing `bin/internal/shared.sh` bootstrap re-checks-out the vendored SDK and recompiles the tool snapshot on its own. Tag knowledge moves out of `TvosUpgradeCommandRunner` into a standalone `TvosReleases` service that the new commands share.

**Tech Stack:** Dart, `package:flutter_tools` (private `src/` imports), `test` + `FakeProcessManager` from the vendored Flutter test harness.

**Spec:** `docs/superpowers/specs/2026-08-02-cli-version-selection-design.md`

## Global Constraints

- Target line is Flutter **3.44.7** (`main`). The separate 3.32.8 CLI port is downstream work and out of scope here.
- Copyright header on every new file, matching existing files verbatim:
  `// Copyright 2026 The FlutterTV Authors. All rights reserved.` / `// Use of this source code is governed by a BSD-style license that can be` / `// found in the LICENSE file.`
- Release tag shape is exactly `v<major>.<minor>.<patch>-tvos.<major>.<minor>.<patch>`. Both halves have three numeric parts.
- `ProcessUtils` is injectable on every type that shells out to git, so tests drive git through `FakeProcessManager` with no repository present. Production callers omit it and fall back to `globals.processUtils`.
- Tag lists are always **newest-first**, produced by `git tag -l --sort=-v:refname`. Code that collapses or picks "newest" relies on this ordering; Task 3 pins it.
- Never treat an unverifiable git state as safe. If `git status` cannot be queried, fail closed rather than assuming the tree is clean.
- Run tests with: `bin/flutter-tvos test test/general/<file>` from the repo root.
- Do not restructure `TvosUpgradeCommand`'s two-phase `--continue` flow. Task 8 changes only where it gets tags from.

---

### Task 1: `TvosRelease` — parse and group release tags

Pure logic, no git. This is the vocabulary every later task uses.

**Files:**
- Create: `lib/tvos_releases.dart`
- Test: `test/general/tvos_releases_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `TvosRelease` with fields `String tag`, `String flutterVersion`, `String toolVersion`, `String? hash`; statics `TvosRelease.tagPattern` (`RegExp`), `TvosRelease.parse(String) -> TvosRelease?`, `TvosRelease.collapseToNewestPerFlutterVersion(List<TvosRelease>) -> List<TvosRelease>`; instance method `withHash(String) -> TvosRelease`.

- [ ] **Step 1: Write the failing test**

Create `test/general/tvos_releases_test.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/tvos_releases.dart';

import '../src/common.dart';

void main() {
  group('TvosRelease.parse', () {
    test('splits a release tag into its Flutter and tool versions', () {
      final TvosRelease? r = TvosRelease.parse('v3.44.7-tvos.1.4.2');
      expect(r, isNotNull);
      expect(r!.tag, 'v3.44.7-tvos.1.4.2');
      expect(r.flutterVersion, '3.44.7');
      expect(r.toolVersion, '1.4.2');
      expect(r.hash, isNull);
    });

    test('trims surrounding whitespace', () {
      expect(TvosRelease.parse('  v3.44.7-tvos.1.4.2  ')!.tag, 'v3.44.7-tvos.1.4.2');
    });

    test('returns null for anything that is not a release tag', () {
      expect(TvosRelease.parse('nightly'), isNull);
      expect(TvosRelease.parse('latest'), isNull);
      expect(TvosRelease.parse('v3.44.1'), isNull); // plain Flutter-style tag
      expect(TvosRelease.parse('tvos.1.2.0'), isNull); // no v<flutter> prefix
      expect(TvosRelease.parse('v3.44.1-tvos.1.2'), isNull); // tool needs 3 parts
      expect(TvosRelease.parse('3.44.1-tvos.1.2.0'), isNull); // no leading v
      expect(TvosRelease.parse('v3.44.1-ios.1.2.0'), isNull); // wrong infix
    });

    test('accepts multi-digit version components', () {
      final TvosRelease? r = TvosRelease.parse('v10.0.0-tvos.12.34.56');
      expect(r!.flutterVersion, '10.0.0');
      expect(r.toolVersion, '12.34.56');
    });
  });

  group('TvosRelease.collapseToNewestPerFlutterVersion', () {
    // Newest-first, as `git tag -l --sort=-v:refname` produces. Mirrors the
    // real tag list, which has two tool releases for several Flutter versions.
    List<TvosRelease> parseAll(List<String> tags) =>
        tags.map(TvosRelease.parse).whereType<TvosRelease>().toList();

    test('keeps one entry per Flutter version, at its newest tool release', () {
      final List<TvosRelease> collapsed = TvosRelease.collapseToNewestPerFlutterVersion(
        parseAll(<String>[
          'v3.44.7-tvos.1.4.2',
          'v3.44.5-tvos.1.4.0',
          'v3.44.5-tvos.1.3.3',
          'v3.32.8-tvos.1.0.0',
        ]),
      );

      expect(collapsed.map((TvosRelease r) => r.tag), <String>[
        'v3.44.7-tvos.1.4.2',
        'v3.44.5-tvos.1.4.0',
        'v3.32.8-tvos.1.0.0',
      ]);
    });

    test('preserves input order', () {
      final List<TvosRelease> collapsed = TvosRelease.collapseToNewestPerFlutterVersion(
        parseAll(<String>['v3.44.7-tvos.1.4.2', 'v3.32.8-tvos.1.0.0']),
      );
      expect(collapsed.first.flutterVersion, '3.44.7');
      expect(collapsed.last.flutterVersion, '3.32.8');
    });

    test('returns an empty list for empty input', () {
      expect(TvosRelease.collapseToNewestPerFlutterVersion(<TvosRelease>[]), isEmpty);
    });
  });

  group('TvosRelease.withHash', () {
    test('attaches a commit without altering the other fields', () {
      final TvosRelease r = TvosRelease.parse('v3.32.8-tvos.1.0.0')!.withHash('cafebabe');
      expect(r.hash, 'cafebabe');
      expect(r.tag, 'v3.32.8-tvos.1.0.0');
      expect(r.flutterVersion, '3.32.8');
      expect(r.toolVersion, '1.0.0');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/flutter-tvos test test/general/tvos_releases_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:flutter_tvos/tvos_releases.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `lib/tvos_releases.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:meta/meta.dart';

/// A flutter-tvos release: one tagged point that pins a Flutter version, its
/// matching engine artifacts, and the CLI source ported to that version's
/// `flutter_tools` API.
@immutable
class TvosRelease {
  const TvosRelease({
    required this.tag,
    required this.flutterVersion,
    required this.toolVersion,
    this.hash,
  });

  /// The full tag, e.g. `v3.44.7-tvos.1.4.2`.
  final String tag;

  /// The Flutter version this release pins, e.g. `3.44.7`.
  final String flutterVersion;

  /// The flutter-tvos tool version, e.g. `1.4.2`.
  final String toolVersion;

  /// The commit the tag points at, once resolved. Null until [withHash].
  final String? hash;

  /// Matches flutter-tvos release tags, capturing both version halves.
  static final RegExp tagPattern = RegExp(r'^v(\d+\.\d+\.\d+)-tvos\.(\d+\.\d+\.\d+)$');

  /// Parses [tag], or returns null when it is not a release tag. Non-release
  /// tags in the repo (`nightly`, plain `v3.44.1`) are expected and ignored
  /// rather than treated as errors.
  static TvosRelease? parse(String tag) {
    final String trimmed = tag.trim();
    final RegExpMatch? match = tagPattern.firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    return TvosRelease(
      tag: trimmed,
      flutterVersion: match.group(1)!,
      toolVersion: match.group(2)!,
    );
  }

  /// One entry per Flutter version, keeping the first occurrence of each.
  ///
  /// [releases] must be newest-first (`git tag -l --sort=-v:refname`), so the
  /// first occurrence is the newest tool release for that Flutter version —
  /// which is also what a bare selector like `use 3.44.5` resolves to, so the
  /// list shows exactly what the user would get.
  static List<TvosRelease> collapseToNewestPerFlutterVersion(List<TvosRelease> releases) {
    final seen = <String>{};
    final result = <TvosRelease>[];
    for (final TvosRelease release in releases) {
      if (seen.add(release.flutterVersion)) {
        result.add(release);
      }
    }
    return result;
  }

  TvosRelease withHash(String hash) => TvosRelease(
    tag: tag,
    flutterVersion: flutterVersion,
    toolVersion: toolVersion,
    hash: hash,
  );

  @override
  bool operator ==(Object other) =>
      other is TvosRelease && other.tag == tag && other.hash == hash;

  @override
  int get hashCode => Object.hash(tag, hash);

  @override
  String toString() => tag;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/flutter-tvos test test/general/tvos_releases_test.dart`
Expected: PASS, 8 tests

- [ ] **Step 5: Commit**

```bash
git add lib/tvos_releases.dart test/general/tvos_releases_test.dart
git commit -m "Add TvosRelease: parse and group flutter-tvos release tags

Capture groups on the tag pattern, so a tag yields its Flutter and tool
versions rather than just matching. collapseToNewestPerFlutterVersion is
what the versions listing needs: four of the nine tagged Flutter versions
have two tool releases, so an ungrouped list would show the same Flutter
version twice."
```

---

### Task 2: `TvosReleases` — git-backed discovery and checkout

**Files:**
- Create: `lib/tvos_releases.dart` (append to the file from Task 1 — move `TvosVersion` here too)
- Modify: `lib/commands/upgrade.dart` — delete the `TvosVersion` class, re-export it
- Test: `test/general/tvos_releases_test.dart` (append)

**Interfaces:**
- Consumes: `TvosRelease` from Task 1.
- Produces: `TvosVersion` (moved here, fields `String hash`, `String? tag`, getters `hashShort`, `label`); `TvosReleases({required String workingDirectory, ProcessUtils? processUtils})` with `Future<List<TvosRelease>> list({bool fetch = true})`, `Future<TvosVersion> current()`, `Future<TvosRelease> resolve(String selector)`, `Future<bool> hasUncommittedChanges()`, `Future<void> checkout(String hash)`.

`TvosVersion` moves out of `upgrade.dart` because `current()` returns it and `tvos_releases.dart` must not import a command. `upgrade.dart` re-exports it so `test/general/tvos_upgrade_test.dart`, which imports `TvosVersion` from there, keeps compiling untouched.

- [ ] **Step 1: Write the failing test**

Append to `test/general/tvos_releases_test.dart` (add these imports at the top of the file):

```dart
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';

import '../src/context.dart';
import '../src/fake_process_manager.dart';
```

and these groups inside `main()`:

```dart
  group('TvosReleases.list', () {
    late FakeProcessManager processManager;
    late TvosReleases releases;

    setUp(() {
      processManager = FakeProcessManager.empty();
      releases = TvosReleases(
        workingDirectory: '/repo',
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      );
    });

    test('fetches then lists, dropping non-release tags', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'nightly\nv3.44.7-tvos.1.4.2\nv3.44.1\nv3.32.8-tvos.1.0.0\n',
        ),
      ]);

      final List<TvosRelease> result = await releases.list();

      expect(result.map((TvosRelease r) => r.tag), <String>[
        'v3.44.7-tvos.1.4.2',
        'v3.32.8-tvos.1.0.0',
      ]);
      expect(processManager, hasNoRemainingExpectations);
    });

    test('skips the fetch when asked not to', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'v3.44.7-tvos.1.4.2\n',
        ),
      ]);

      final List<TvosRelease> result = await releases.list(fetch: false);

      expect(result.single.tag, 'v3.44.7-tvos.1.4.2');
      expect(processManager, hasNoRemainingExpectations);
    });

    testUsingContext('a failed fetch warns and falls back to local tags', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'fetch', '--tags'],
          exitCode: 128,
          stderr: 'fatal: unable to access remote',
        ),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'v3.44.7-tvos.1.4.2\n',
        ),
      ]);

      final List<TvosRelease> result = await releases.list();

      // The whole point: offline discovery still yields what git already has.
      expect(result.single.tag, 'v3.44.7-tvos.1.4.2');
      expect(processManager, hasNoRemainingExpectations);
    });

    test('returns an empty list when the repo has no release tags', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'nightly\n',
        ),
      ]);

      expect(await releases.list(), isEmpty);
    });
  });

  group('TvosReleases.resolve', () {
    late FakeProcessManager processManager;
    late TvosReleases releases;

    setUp(() {
      processManager = FakeProcessManager.empty();
      releases = TvosReleases(
        workingDirectory: '/repo',
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      );
    });

    void stubTagList() {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(command: <String>['git', 'fetch', '--tags']),
        const FakeCommand(
          command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
          stdout: 'v3.44.7-tvos.1.4.2\n'
              'v3.44.5-tvos.1.4.0\n'
              'v3.44.5-tvos.1.3.3\n'
              'v3.32.8-tvos.1.0.0\n',
        ),
      ]);
    }

    test('a bare Flutter version picks its newest tool release', () async {
      stubTagList();
      processManager.addCommand(
        const FakeCommand(
          command: <String>['git', 'rev-parse', 'v3.44.5-tvos.1.4.0^{commit}'],
          stdout: 'cafebabecafebabecafebabecafebabecafebabe\n',
        ),
      );

      final TvosRelease r = await releases.resolve('3.44.5');

      expect(r.tag, 'v3.44.5-tvos.1.4.0');
      expect(r.hash, 'cafebabecafebabecafebabecafebabecafebabe');
    });

    test('an exact tag resolves to itself, not the newest for that version', () async {
      stubTagList();
      processManager.addCommand(
        const FakeCommand(
          command: <String>['git', 'rev-parse', 'v3.44.5-tvos.1.3.3^{commit}'],
          stdout: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n',
        ),
      );

      final TvosRelease r = await releases.resolve('v3.44.5-tvos.1.3.3');

      expect(r.tag, 'v3.44.5-tvos.1.3.3');
      expect(r.hash, 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef');
    });

    test('an unknown version exits with the available versions listed', () async {
      stubTagList();

      await expectToolExitLater(
        releases.resolve('3.99.0'),
        allOf(contains('3.99.0'), contains('3.44.7'), contains('3.32.8')),
      );
    });

    test('a tag-shaped selector that does not exist also lists alternatives', () async {
      stubTagList();

      await expectToolExitLater(
        releases.resolve('v3.44.5-tvos.9.9.9'),
        contains('3.44.5'),
      );
    });
  });

  group('TvosReleases git state', () {
    late FakeProcessManager processManager;
    late TvosReleases releases;

    setUp(() {
      processManager = FakeProcessManager.empty();
      releases = TvosReleases(
        workingDirectory: '/repo',
        processUtils: ProcessUtils(
          processManager: processManager,
          logger: BufferLogger.test(),
        ),
      );
    });

    test('current() reports the tag when HEAD is exactly on one', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
          stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
        ),
        const FakeCommand(
          command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
          stdout: 'v3.44.7-tvos.1.4.2\n',
        ),
      ]);

      final TvosVersion v = await releases.current();

      expect(v.tag, 'v3.44.7-tvos.1.4.2');
      expect(v.label, 'v3.44.7-tvos.1.4.2');
    });

    test('current() falls back to the short hash on an untagged commit', () async {
      processManager.addCommands(<FakeCommand>[
        const FakeCommand(
          command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
          stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
        ),
        const FakeCommand(
          command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
          exitCode: 128,
        ),
      ]);

      final TvosVersion v = await releases.current();

      expect(v.tag, isNull);
      expect(v.label, 'aaaabbbbcc');
    });

    test('hasUncommittedChanges is true for a dirty tree', () async {
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ' M lib/foo.dart\n'),
      );
      expect(await releases.hasUncommittedChanges(), isTrue);
    });

    test('hasUncommittedChanges is false for a clean tree', () async {
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ''),
      );
      expect(await releases.hasUncommittedChanges(), isFalse);
    });

    test('hasUncommittedChanges fails closed when git cannot be queried', () async {
      // Never report "clean" for a tree we could not inspect: this is the only
      // guard before `git reset --hard`.
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'status', '-s'], exitCode: 127),
      );
      await expectToolExitLater(
        releases.hasUncommittedChanges(),
        contains('could not verify'),
      );
    });

    test('checkout resets hard to the given commit', () async {
      processManager.addCommand(
        const FakeCommand(command: <String>['git', 'reset', '--hard', 'cafebabe']),
      );
      await releases.checkout('cafebabe');
      expect(processManager, hasNoRemainingExpectations);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/flutter-tvos test test/general/tvos_releases_test.dart`
Expected: FAIL — `Undefined name 'TvosReleases'` and `Undefined class 'TvosVersion'`

- [ ] **Step 3: Write minimal implementation**

Append to `lib/tvos_releases.dart`, and add these imports at the top of that file:

```dart
import 'dart:convert';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
```

```dart
/// A resolved point in the flutter-tvos git history.
@immutable
class TvosVersion {
  const TvosVersion({required this.hash, required this.tag});

  /// Full git commit hash.
  final String hash;

  /// The exact release tag at this commit, or null if the commit is not
  /// tagged (e.g. a development checkout on a branch).
  final String? tag;

  String get hashShort => hash.length >= 10 ? hash.substring(0, 10) : hash;

  /// Human label: the tag when present, otherwise the short hash.
  String get label => tag ?? hashShort;
}

/// Knows which flutter-tvos releases exist and how to move the checkout
/// between them. Deliberately knows nothing about commands.
class TvosReleases {
  /// [processUtils] is injectable so tests can drive the git queries with a
  /// `FakeProcessManager` without standing up Zone DI; production callers omit
  /// it and fall back to [globals.processUtils].
  TvosReleases({required this.workingDirectory, ProcessUtils? processUtils})
    : _processUtils = processUtils;

  /// The flutter-tvos checkout root — where `.git` and `bin/flutter-tvos` live.
  final String workingDirectory;

  final ProcessUtils? _processUtils;

  ProcessUtils get _git => _processUtils ?? globals.processUtils;

  /// All release tags, newest first.
  ///
  /// The fetch is best-effort: with no network we still list what git already
  /// has, which is also still checkout-able. Failing the whole command because
  /// the remote is unreachable would make the tool useless offline for no gain.
  Future<List<TvosRelease>> list({bool fetch = true}) async {
    if (fetch) {
      try {
        await _git.run(<String>[
          'git',
          'fetch',
          '--tags',
        ], throwOnError: true, workingDirectory: workingDirectory);
      } on ProcessException catch (e) {
        globals.printWarning(
          'Could not reach the flutter-tvos remote; showing the releases '
          'already known locally.\n${e.message}',
        );
      }
    }

    final RunResult result = await _git.run(<String>[
      'git',
      'tag',
      '-l',
      '--sort=-v:refname',
    ], throwOnError: true, workingDirectory: workingDirectory);

    return const LineSplitter()
        .convert(result.stdout.trim())
        .map(TvosRelease.parse)
        .whereType<TvosRelease>()
        .toList();
  }

  /// Resolves a user-supplied selector to a release with its commit.
  ///
  /// Accepts a bare Flutter version (`3.32.8`), which picks the newest tool
  /// release for it, or an exact tag (`v3.32.8-tvos.1.0.0`). Anything else is
  /// an error listing the alternatives — no prefix guessing, because guessing
  /// wrong here silently checks out a version the user did not ask for.
  Future<TvosRelease> resolve(String selector) async {
    final String wanted = selector.trim();
    final List<TvosRelease> releases = await list();
    final bool selectorIsTag = TvosRelease.parse(wanted) != null;

    TvosRelease? match;
    for (final TvosRelease release in releases) {
      final bool hit = selectorIsTag
          ? release.tag == wanted
          : release.flutterVersion == wanted;
      if (hit) {
        // The list is newest-first, so the first hit for a bare version is its
        // newest tool release.
        match = release;
        break;
      }
    }

    if (match == null) {
      final String available = TvosRelease.collapseToNewestPerFlutterVersion(releases)
          .map((TvosRelease r) => '  ${r.flutterVersion}')
          .join('\n');
      throwToolExit(
        'No flutter-tvos release matches "$selector".\n\n'
        '${available.isEmpty ? 'No releases are known locally. Check your network connection.' : 'Available versions:\n$available'}',
      );
    }

    return match.withHash(await peelToCommit(match.tag));
  }

  /// Resolves the commit the checkout is currently on, and its exact tag if any.
  Future<TvosVersion> current() async {
    String hash;
    String? tag;
    try {
      final RunResult head = await _git.run(<String>[
        'git',
        'rev-parse',
        '--verify',
        'HEAD',
      ], throwOnError: true, workingDirectory: workingDirectory);
      hash = head.stdout.trim();
    } on ProcessException catch (e) {
      throwToolExit(
        'Unable to determine the current flutter-tvos version: could not read '
        'HEAD in $workingDirectory.\n${e.message}',
      );
    }

    try {
      final RunResult described = await _git.run(<String>[
        'git',
        'describe',
        '--tags',
        '--exact-match',
        'HEAD',
      ], throwOnError: true, workingDirectory: workingDirectory);
      tag = described.stdout.trim();
    } on ProcessException {
      // Not on a tag — a development checkout. Not an error.
      tag = null;
    }

    return TvosVersion(hash: hash, tag: tag);
  }

  Future<bool> hasUncommittedChanges() async {
    // Fail *closed*: this is the only guard before `git reset --hard`, so if we
    // cannot determine the tree's status we must not report it clean.
    try {
      final RunResult result = await _git.run(<String>[
        'git',
        'status',
        '-s',
      ], throwOnError: true, workingDirectory: workingDirectory);
      return result.stdout.trim().isNotEmpty;
    } on ProcessException catch (e) {
      throwToolExit(
        'The tool could not verify the status of the flutter-tvos checkout in '
        '$workingDirectory. Ensure git is installed and in your PATH and try '
        'again, or re-run with --force to skip this check.\n${e.message}',
      );
    }
  }

  Future<void> checkout(String hash) async {
    try {
      await _git.run(<String>[
        'git',
        'reset',
        '--hard',
        hash,
      ], throwOnError: true, workingDirectory: workingDirectory);
    } on ProcessException catch (e) {
      throwToolExit(e.message, exitCode: e.errorCode);
    }
  }

  /// Peels an annotated tag to its commit. `git rev-parse <annotated-tag>`
  /// returns the tag-object SHA, which would never equal a `rev-parse HEAD`
  /// result; `^{commit}` is a no-op for lightweight tags.
  ///
  /// Public because Task 8's `upgrade` needs to peel a tag it already has,
  /// without paying for a second `list()` and its `git fetch`.
  Future<String> peelToCommit(String tag) async {
    try {
      final RunResult result = await _git.run(<String>[
        'git',
        'rev-parse',
        '$tag^{commit}',
      ], throwOnError: true, workingDirectory: workingDirectory);
      return result.stdout.trim();
    } on ProcessException catch (e) {
      throwToolExit('Could not resolve the commit for $tag.\n${e.message}');
    }
  }
}
```

Now delete the `TvosVersion` class from `lib/commands/upgrade.dart` (the `@immutable class TvosVersion { ... }` block and its doc comment), remove the now-unused `import 'package:meta/meta.dart';` if nothing else in that file uses it, and add near the top of the file:

```dart
import 'package:flutter_tvos/tvos_releases.dart';

export 'package:flutter_tvos/tvos_releases.dart' show TvosVersion;
```

The re-export keeps `test/general/tvos_upgrade_test.dart` compiling: it imports `TvosVersion` from `package:flutter_tvos/commands/upgrade.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/flutter-tvos test test/general/tvos_releases_test.dart test/general/tvos_upgrade_test.dart`
Expected: PASS — the new file's tests plus the existing upgrade tests, which must be unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/tvos_releases.dart lib/commands/upgrade.dart test/general/tvos_releases_test.dart
git commit -m "Add TvosReleases: git-backed release discovery and checkout

Tag knowledge moves out of the upgrade command so versions, use and
downgrade can share it. TvosVersion moves with it, since current() returns
one and tvos_releases.dart must not import a command; upgrade.dart
re-exports it so the existing test keeps compiling.

The fetch in list() is best-effort. Offline, git still knows every tag it
has ever fetched and can still check them out, so failing the command over
an unreachable remote would cost the user that capability for nothing."
```

---

### Task 3: Pin the tag sort order against real git

Both `resolve` (Task 2) and the shipped `upgrade` assume `git tag -l --sort=-v:refname` returns newest-first for our tag shape. Nothing pins that, and git's `versionsort.suffix` configuration can change how a `-tvos.N` suffix ranks.

**Files:**
- Test: `test/general/tvos_releases_sort_test.dart` (create)

**Interfaces:**
- Consumes: `TvosRelease` from Task 1.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Create `test/general/tvos_releases_sort_test.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show Process, ProcessResult;

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
```

A `MemoryFileSystem` cannot stand in here — the whole point is to ask real git a question a fake would only echo back.

- [ ] **Step 2: Run test to verify it fails or passes for the right reason**

Run: `bin/flutter-tvos test test/general/tvos_releases_sort_test.dart`
Expected: PASS. This test documents an existing external behaviour rather than driving new code, so it should pass on first run — that is the point. If it FAILS, git is ordering our tags differently than assumed and both `resolve` and the shipped `upgrade` have a latent bug: stop and report before continuing the plan.

- [ ] **Step 3: Commit**

```bash
git add test/general/tvos_releases_sort_test.dart
git commit -m "Pin the git tag sort order with a real-git test

list() and the shipped upgrade both assume --sort=-v:refname returns our
tags newest-first, including two tool releases of the same Flutter version
in the right order. A fake process manager cannot verify that; it replays
whatever order the test author assumed. git's versionsort.suffix can change
how the -tvos.N suffix ranks, so this runs against real git."
```

---

### Task 4: `TvosToolState` — remember where we switched from

**Files:**
- Create: `lib/tvos_tool_state.dart`
- Test: `test/general/tvos_tool_state_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `TvosToolState({required String repoRoot, required FileSystem fileSystem})` with `String? readPreviousTag()` and `void writePreviousTag(String tag)`.

- [ ] **Step 1: Write the failing test**

Create `test/general/tvos_tool_state_test.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tvos/tvos_tool_state.dart';

import '../src/common.dart';

void main() {
  late FileSystem fileSystem;
  late TvosToolState state;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    fileSystem.directory('/repo/.git').createSync(recursive: true);
    state = TvosToolState(repoRoot: '/repo', fileSystem: fileSystem);
  });

  test('reads back what it wrote', () {
    state.writePreviousTag('v3.44.7-tvos.1.4.2');
    expect(state.readPreviousTag(), 'v3.44.7-tvos.1.4.2');
  });

  test('stores the tag inside .git, so it survives git reset --hard', () {
    state.writePreviousTag('v3.44.7-tvos.1.4.2');
    // .git is not part of the worktree, so reset --hard cannot touch it, and
    // it is never committed. bin/cache would not do: shared.sh deletes it on
    // every version change.
    expect(fileSystem.file('/repo/.git/flutter-tvos-previous').existsSync(), isTrue);
  });

  test('returns null when nothing has been recorded', () {
    expect(state.readPreviousTag(), isNull);
  });

  test('returns null for an empty or whitespace-only file', () {
    fileSystem.file('/repo/.git/flutter-tvos-previous').writeAsStringSync('  \n');
    expect(state.readPreviousTag(), isNull);
  });

  test('overwrites a previous entry rather than appending', () {
    state.writePreviousTag('v3.44.5-tvos.1.4.0');
    state.writePreviousTag('v3.44.7-tvos.1.4.2');
    expect(state.readPreviousTag(), 'v3.44.7-tvos.1.4.2');
  });

  test('a write that fails does not throw', () {
    // A checkout whose .git is a file, not a directory — git worktrees and
    // submodules do this. Losing the downgrade breadcrumb is a degraded
    // experience; aborting the switch over it would be worse.
    final FileSystem fs = MemoryFileSystem.test();
    fs.file('/wt/.git').createSync(recursive: true);
    final TvosToolState worktreeState = TvosToolState(repoRoot: '/wt', fileSystem: fs);

    expect(() => worktreeState.writePreviousTag('v3.44.7-tvos.1.4.2'), returnsNormally);
    expect(worktreeState.readPreviousTag(), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/flutter-tvos test test/general/tvos_tool_state_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:flutter_tvos/tvos_tool_state.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `lib/tvos_tool_state.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

/// Remembers the release a checkout was switched away from, so `downgrade`
/// knows where to go back to.
///
/// Stored at `.git/flutter-tvos-previous`. Three constraints pick that
/// location and only it satisfies all three: the file must survive
/// `git reset --hard` (so not a tracked path), must survive `shared.sh`
/// deleting `bin/cache` on every version change (so not there), and must be
/// per-checkout — which rules out `~/.config/flutter/`, since users wanting
/// concurrent versions are told to clone twice and a global file would have
/// one clone's downgrade jump to the other's history.
class TvosToolState {
  TvosToolState({required this.repoRoot, required FileSystem fileSystem})
    : _fileSystem = fileSystem;

  /// The flutter-tvos checkout root.
  final String repoRoot;

  final FileSystem _fileSystem;

  File get _file => _fileSystem
      .directory(repoRoot)
      .childDirectory('.git')
      .childFile('flutter-tvos-previous');

  /// The tag switched away from, or null if none was recorded or it cannot be
  /// read.
  String? readPreviousTag() {
    try {
      final File file = _file;
      if (!file.existsSync()) {
        return null;
      }
      final String contents = file.readAsStringSync().trim();
      return contents.isEmpty ? null : contents;
    } on FileSystemException catch (e) {
      globals.printTrace('Could not read the previous flutter-tvos tag: $e');
      return null;
    }
  }

  /// Records [tag]. Never throws: a `.git` that is a file rather than a
  /// directory (worktrees, submodules) costs the user `downgrade`, which is a
  /// far smaller loss than aborting a switch that is otherwise fine.
  void writePreviousTag(String tag) {
    try {
      _file.writeAsStringSync('$tag\n');
    } on FileSystemException catch (e) {
      globals.printTrace('Could not record the previous flutter-tvos tag: $e');
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/flutter-tvos test test/general/tvos_tool_state_test.dart`
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add lib/tvos_tool_state.dart test/general/tvos_tool_state_test.dart
git commit -m "Add TvosToolState: record the release a checkout switched from

Kept in .git/flutter-tvos-previous. It has to survive git reset --hard and
shared.sh wiping bin/cache, and it has to be per-checkout: the design tells
users wanting concurrent versions to clone twice, so a global ~/.config
file would have downgrade in one clone jump to the other's history.

Write failures are swallowed. On a checkout whose .git is a file the user
loses downgrade; aborting an otherwise-fine switch would cost more."
```

---

### Task 5: `flutter-tvos versions`

**Files:**
- Create: `lib/commands/versions.dart`
- Modify: `lib/executable.dart` — register the command
- Test: `test/general/tvos_versions_command_test.dart`

**Interfaces:**
- Consumes: `TvosReleases`, `TvosRelease`, `TvosVersion` from Task 2.
- Produces: `TvosVersionsCommand({TvosReleases? releases})`, command name `versions`.

- [ ] **Step 1: Write the failing test**

Create `test/general/tvos_versions_command_test.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tvos/commands/versions.dart';
import 'package:flutter_tvos/tvos_releases.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';

void main() {
  late FakeProcessManager processManager;
  late BufferLogger logger;
  late TvosReleases releases;

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    releases = TvosReleases(
      workingDirectory: '/repo',
      processUtils: ProcessUtils(processManager: processManager, logger: logger),
    );
  });

  void stubTagsAndHead({String headTag = 'v3.44.7-tvos.1.4.2'}) {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: 'v3.44.7-tvos.1.4.2\n'
            'v3.44.5-tvos.1.4.0\n'
            'v3.44.5-tvos.1.3.3\n'
            'v3.32.8-tvos.1.0.0\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      FakeCommand(
        command: const <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        stdout: '$headTag\n',
      ),
    ]);
  }

  testUsingContext('lists one line per Flutter version at its newest tool release', () async {
    stubTagsAndHead();
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    final String out = logger.statusText;
    expect(out, contains('3.44.7'));
    expect(out, contains('3.44.5'));
    expect(out, contains('3.32.8'));
    // 1.3.3 is the older tool release of 3.44.5 and must be collapsed away.
    expect(out, isNot(contains('1.3.3')));
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('marks exactly one line as current', () async {
    stubTagsAndHead();
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    expect('(current)'.allMatches(logger.statusText).length, 1);
    expect(
      logger.statusText.split('\n').firstWhere((String l) => l.contains('(current)')),
      contains('3.44.7'),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('marks nothing current when HEAD is untagged', () async {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: 'v3.44.7-tvos.1.4.2\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        exitCode: 128,
      ),
    ]);
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    expect(logger.statusText, isNot(contains('(current)')));
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('--all shows every release tag ungrouped', () async {
    stubTagsAndHead();
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions', '--all']);

    expect(logger.statusText, contains('v3.44.5-tvos.1.4.0'));
    expect(logger.statusText, contains('v3.44.5-tvos.1.3.3'));
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('says so when no releases are known', () async {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(command: <String>['git', 'tag', '-l', '--sort=-v:refname'], stdout: ''),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        exitCode: 128,
      ),
    ]);
    final command = TvosVersionsCommand(releases: releases);

    await createTestCommandRunner(command).run(<String>['versions']);

    expect(logger.statusText, contains('No flutter-tvos releases'));
  }, overrides: <Type, Generator>{Logger: () => logger});
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/flutter-tvos test test/general/tvos_versions_command_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:flutter_tvos/commands/versions.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `lib/commands/versions.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tvos/tvos_releases.dart';

/// `flutter-tvos versions` — lists the Flutter versions this toolchain can be
/// switched to, marking the one in use.
class TvosVersionsCommand extends FlutterCommand {
  TvosVersionsCommand({TvosReleases? releases}) : _releases = releases {
    argParser.addFlag(
      'all',
      negatable: false,
      help: 'Show every release tag instead of one line per Flutter version.',
    );
  }

  final TvosReleases? _releases;

  /// Cache.flutterRoot points at the vendored `flutter/` SDK; its parent is the
  /// flutter-tvos repo root, where `.git` and `bin/flutter-tvos` live.
  TvosReleases get releases =>
      _releases ??
      TvosReleases(workingDirectory: globals.fs.directory(Cache.flutterRoot).parent.path);

  @override
  final String name = 'versions';

  @override
  final String description =
      'List the Flutter versions this flutter-tvos checkout can be switched to.';

  @override
  final String category = 'Tools';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final List<TvosRelease> all = await releases.list();
    final TvosVersion current = await releases.current();

    if (all.isEmpty) {
      globals.printStatus(
        'No flutter-tvos releases are known. If this checkout was cloned '
        'without tags, run "git fetch --tags".',
      );
      return FlutterCommandResult.success();
    }

    final bool showAll = boolArg('all');
    final List<TvosRelease> shown = showAll
        ? all
        : TvosRelease.collapseToNewestPerFlutterVersion(all);

    for (final TvosRelease release in shown) {
      final bool isCurrent = release.tag == current.tag;
      globals.printStatus(
        '  ${release.flutterVersion.padRight(9)}'
        '${release.tag.padRight(24)}'
        '${isCurrent ? '(current)' : ''}'.trimRight(),
      );
    }

    if (!showAll) {
      globals.printStatus('');
      globals.printStatus('Switch with "flutter-tvos use <version>".');
    }

    return FlutterCommandResult.success();
  }
}
```

Register it in `lib/executable.dart`, in the "Commands extended for tvOS" section next to `TvosUpgradeCommand`:

```dart
      TvosVersionsCommand(),
```

and add the import alongside the other `package:flutter_tvos/commands/...` imports:

```dart
import 'package:flutter_tvos/commands/versions.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/flutter-tvos test test/general/tvos_versions_command_test.dart`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add lib/commands/versions.dart lib/executable.dart test/general/tvos_versions_command_test.dart
git commit -m "Add flutter-tvos versions

One line per Flutter version at its newest tool release, which is what a
bare selector resolves to, so the list shows what you would actually get.
--all is there because four of the nine tagged Flutter versions have two
tool releases and sometimes the tool version is the thing you need."
```

---

### Task 6: `flutter-tvos use <version>`

The switch, including the recovery path when the target toolchain will not build.

**Files:**
- Create: `lib/commands/use.dart`
- Modify: `lib/executable.dart` — register the command
- Test: `test/general/tvos_use_command_test.dart`

**Interfaces:**
- Consumes: `TvosReleases`, `TvosRelease`, `TvosVersion` (Task 2); `TvosToolState` (Task 4).
- Produces: `TvosUseCommand({TvosReleases? releases, TvosToolState? toolState})`, command name `use`.

- [ ] **Step 1: Write the failing test**

Create `test/general/tvos_use_command_test.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tvos/commands/use.dart';
import 'package:flutter_tvos/tvos_releases.dart';
import 'package:flutter_tvos/tvos_tool_state.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';

void main() {
  late FakeProcessManager processManager;
  late BufferLogger logger;
  late FileSystem fileSystem;
  late TvosReleases releases;
  late TvosToolState toolState;

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    fileSystem = MemoryFileSystem.test();
    fileSystem.directory('/repo/.git').createSync(recursive: true);
    releases = TvosReleases(
      workingDirectory: '/repo',
      processUtils: ProcessUtils(processManager: processManager, logger: logger),
    );
    toolState = TvosToolState(repoRoot: '/repo', fileSystem: fileSystem);
  });

  const String tagList = 'v3.44.7-tvos.1.4.2\n'
      'v3.44.5-tvos.1.4.0\n'
      'v3.32.8-tvos.1.0.0\n';

  /// resolve() -> current() ordering, matching TvosUseCommand.
  void stubResolveThenCurrent({
    required String targetTag,
    required String targetHash,
    String headTag = 'v3.44.7-tvos.1.4.2',
  }) {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: tagList,
      ),
      FakeCommand(
        command: <String>['git', 'rev-parse', '$targetTag^{commit}'],
        stdout: '$targetHash\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      FakeCommand(
        command: const <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        stdout: '$headTag\n',
      ),
    ]);
  }

  testUsingContext('is a no-op when already on the requested version', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.44.7-tvos.1.4.2',
      targetHash: 'aaaabbbbccccddddeeeeffff0000111122223333',
    );
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await createTestCommandRunner(command).run(<String>['use', '3.44.7']);

    expect(logger.statusText, contains('already on'));
    expect(processManager, hasNoRemainingExpectations);
    // No reset, and no breadcrumb written for a switch that did not happen.
    expect(toolState.readPreviousTag(), isNull);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('the already-on-target check runs before the dirty-tree guard', () async {
    // A user with local edits who names the version they are already on must
    // not be refused an operation that would do nothing. If the guard ran
    // first this test would fail with a tool exit, and `git status` would be
    // consumed from the fake.
    stubResolveThenCurrent(
      targetTag: 'v3.44.7-tvos.1.4.2',
      targetHash: 'aaaabbbbccccddddeeeeffff0000111122223333',
    );
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await createTestCommandRunner(command).run(<String>['use', '3.44.7']);

    expect(logger.statusText, contains('already on'));
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('refuses a dirty checkout and names --force', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommand(
      const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ' M lib/foo.dart\n'),
    );
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.32.8']),
      allOf(contains('uncommitted changes'), contains('--force')),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('records the previous tag before resetting', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ''),
      const FakeCommand(
        command: <String>[
          'git',
          'reset',
          '--hard',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      toolState: toolState,
      runBootstrap: (_) async => 0,
    );

    await createTestCommandRunner(command).run(<String>['use', '3.32.8']);

    expect(toolState.readPreviousTag(), 'v3.44.7-tvos.1.4.2');
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('prints the recovery command when the target will not build', () async {
    stubResolveThenCurrent(
      targetTag: 'v3.32.8-tvos.1.0.0',
      targetHash: 'cafebabecafebabecafebabecafebabecafebabe',
    );
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ''),
      const FakeCommand(
        command: <String>[
          'git',
          'reset',
          '--hard',
          'cafebabecafebabecafebabecafebabecafebabe',
        ],
      ),
    ]);
    final command = TvosUseCommand(
      releases: releases,
      toolState: toolState,
      runBootstrap: (_) async => 1, // the target toolchain fails to build
    );

    // Past the reset the user cannot run `flutter-tvos` at all, so the message
    // must carry the literal git command that undoes it.
    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.32.8']),
      allOf(
        contains('git -C /repo reset --hard v3.44.7-tvos.1.4.2'),
        contains('3.32.8'),
      ),
    );
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('an unknown version exits without touching the checkout', () async {
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: tagList,
      ),
    ]);
    final command = TvosUseCommand(releases: releases, toolState: toolState);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['use', '3.99.0']),
      contains('3.99.0'),
    );
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/flutter-tvos test test/general/tvos_use_command_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:flutter_tvos/commands/use.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `lib/commands/use.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tvos/tvos_releases.dart';
import 'package:flutter_tvos/tvos_tool_state.dart';

/// Runs one bootstrap step in the switched-to checkout, returning its exit
/// code. Injectable so tests do not shell out.
typedef BootstrapRunner = Future<int> Function(List<String> args);

/// `flutter-tvos use <version>` — switches the toolchain to another release.
///
/// Each supported Flutter version is a release line of this repo: the tag
/// carries the CLI source ported to that version's `flutter_tools` API *and*
/// the pinned SDK revision and engine-artifact tag. So switching is a
/// `git reset --hard` to the tag; `bin/internal/shared.sh` then re-checks-out
/// the vendored SDK and recompiles the tool snapshot on the next invocation,
/// with no extra work here.
class TvosUseCommand extends FlutterCommand {
  TvosUseCommand({TvosReleases? releases, TvosToolState? toolState, BootstrapRunner? runBootstrap})
    : _releases = releases,
      _toolState = toolState,
      _runBootstrap = runBootstrap {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Discard uncommitted changes in the flutter-tvos checkout and switch anyway.',
    );
  }

  final TvosReleases? _releases;
  final TvosToolState? _toolState;
  final BootstrapRunner? _runBootstrap;

  /// Cache.flutterRoot points at the vendored `flutter/` SDK; its parent is the
  /// flutter-tvos repo root, where `.git` and `bin/flutter-tvos` live.
  String get _repoRoot => globals.fs.directory(Cache.flutterRoot).parent.path;

  TvosReleases get releases => _releases ?? TvosReleases(workingDirectory: _repoRoot);

  TvosToolState get toolState =>
      _toolState ?? TvosToolState(repoRoot: _repoRoot, fileSystem: globals.fs);

  @override
  final String name = 'use';

  @override
  final String description =
      'Switch this flutter-tvos checkout to another Flutter version. '
      'Run "flutter-tvos versions" to see what is available.';

  @override
  final String category = 'Tools';

  @override
  String get invocation => 'flutter-tvos use <version>';

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults!.rest.length != 1) {
      throwToolExit(
        'Specify exactly one version, e.g. "flutter-tvos use 3.32.8".\n'
        'Run "flutter-tvos versions" to see what is available.',
      );
    }
    final String selector = argResults!.rest.single;

    final TvosRelease target = await releases.resolve(selector);
    final TvosVersion current = await releases.current();

    // Before the dirty-tree guard on purpose: someone with local edits who
    // names the version they are already on should not be refused an
    // operation that would do nothing.
    if (current.tag == target.tag) {
      globals.printStatus('flutter-tvos is already on ${target.flutterVersion} (${target.tag}).');
      return FlutterCommandResult.success();
    }

    if (!boolArg('force') && await releases.hasUncommittedChanges()) {
      throwToolExit(
        'Your flutter-tvos checkout in $_repoRoot has uncommitted changes.\n'
        'Commit or stash them first, or re-run with --force to discard them '
        'and switch anyway.',
      );
    }

    globals.printStatus(
      'Switching flutter-tvos ${current.label} -> ${target.flutterVersion} (${target.tag})...',
    );

    if (current.tag != null) {
      toolState.writePreviousTag(current.tag!);
    }
    await releases.checkout(target.hash!);

    // Everything past here runs the *target* line's toolchain, which this
    // process cannot become. Shell out, and own the error message: if the
    // target fails to build there is no working `flutter-tvos` left to print
    // it. This is also why the switch does not finish through a `--continue`
    // round-trip the way `upgrade` does — that would put the message in the
    // mouth of the process that just failed to exist.
    final int code = await _bootstrap(<String>['precache', '--force']);
    if (code != 0) {
      _throwStranded(target, current);
    }

    final int doctorCode = await _bootstrap(<String>['doctor']);
    if (doctorCode != 0) {
      globals.printWarning(
        'Switched to ${target.flutterVersion}, but "flutter-tvos doctor" reported problems.',
      );
    }

    globals.printStatus('');
    globals.printStatus('Now on Flutter ${target.flutterVersion} (${target.tag}).');
    return FlutterCommandResult.success();
  }

  Future<int> _bootstrap(List<String> args) {
    final BootstrapRunner runner =
        _runBootstrap ??
        (List<String> a) => globals.processUtils.stream(
          <String>[globals.fs.path.join('bin', 'flutter-tvos'), '--no-version-check', ...a],
          workingDirectory: _repoRoot,
          allowReentrantFlutter: true,
          environment: Map<String, String>.of(globals.platform.environment),
        );
    return runner(args);
  }

  /// The checkout has moved but its toolchain will not build, so no
  /// `flutter-tvos` command can run — including the one that would undo this.
  /// The way back has to be a plain git command the user can paste.
  Never _throwStranded(TvosRelease target, TvosVersion previous) {
    final String back = previous.tag ?? previous.hash;
    throwToolExit(
      'Switched to ${target.flutterVersion}, but the toolchain failed to build for it.\n'
      'Your checkout is on ${target.tag}; the flutter-tvos command will not work '
      'until this is resolved.\n\n'
      'To return to the version you came from:\n'
      '  git -C $_repoRoot reset --hard $back',
    );
  }
}
```

Register it in `lib/executable.dart` next to `TvosVersionsCommand()`:

```dart
      TvosUseCommand(),
```

with the import:

```dart
import 'package:flutter_tvos/commands/use.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/flutter-tvos test test/general/tvos_use_command_test.dart`
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add lib/commands/use.dart lib/executable.dart test/general/tvos_use_command_test.dart
git commit -m "Add flutter-tvos use <version>

Resolves a bare Flutter version or an exact tag, guards the checkout, then
resets to the tag; shared.sh re-bootstraps the SDK and snapshot by itself
on the next invocation.

Past the reset the target line's toolchain is what runs, and if it will not
build there is no flutter-tvos left to run the undo. So the failure prints
the literal git reset --hard back to the recorded previous tag, and the
switch shells out rather than finishing through a --continue round-trip:
the message has to come from a process that still exists.

The already-on-target check deliberately precedes the dirty-tree guard, so
local edits do not block a no-op."
```

---

### Task 7: Override `downgrade`, unregister `channel`

Both are forwarded stock today, in a block commented "no tvOS-specific behaviour". Both run `git reset --hard` inside `Cache.flutterRoot` — the vendored SDK — which is the hazard `TvosUpgradeCommand` exists to avoid.

**Files:**
- Create: `lib/commands/downgrade.dart`
- Modify: `lib/executable.dart` — swap `DowngradeCommand` for `TvosDowngradeCommand`, delete `ChannelCommand`
- Test: `test/general/tvos_downgrade_command_test.dart`

**Interfaces:**
- Consumes: `TvosReleases`, `TvosToolState`, and `TvosUseCommand`'s switch behaviour.
- Produces: `TvosDowngradeCommand({TvosReleases? releases, TvosToolState? toolState, BootstrapRunner? runBootstrap})`, command name `downgrade`.

- [ ] **Step 1: Write the failing test**

Create `test/general/tvos_downgrade_command_test.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tvos/commands/downgrade.dart';
import 'package:flutter_tvos/tvos_releases.dart';
import 'package:flutter_tvos/tvos_tool_state.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_process_manager.dart';

void main() {
  late FakeProcessManager processManager;
  late BufferLogger logger;
  late FileSystem fileSystem;
  late TvosReleases releases;
  late TvosToolState toolState;

  setUp(() {
    processManager = FakeProcessManager.empty();
    logger = BufferLogger.test();
    fileSystem = MemoryFileSystem.test();
    fileSystem.directory('/repo/.git').createSync(recursive: true);
    releases = TvosReleases(
      workingDirectory: '/repo',
      processUtils: ProcessUtils(processManager: processManager, logger: logger),
    );
    toolState = TvosToolState(repoRoot: '/repo', fileSystem: fileSystem);
  });

  testUsingContext('with nothing recorded, says so and points at versions', () async {
    final command = TvosDowngradeCommand(releases: releases, toolState: toolState);

    await expectToolExitLater(
      createTestCommandRunner(command).run(<String>['downgrade']),
      allOf(contains('no previous'), contains('versions')),
    );
    expect(processManager, hasNoRemainingExpectations);
  }, overrides: <Type, Generator>{Logger: () => logger});

  testUsingContext('switches back to the recorded tag', () async {
    toolState.writePreviousTag('v3.44.7-tvos.1.4.2');
    processManager.addCommands(<FakeCommand>[
      const FakeCommand(command: <String>['git', 'fetch', '--tags']),
      const FakeCommand(
        command: <String>['git', 'tag', '-l', '--sort=-v:refname'],
        stdout: 'v3.44.7-tvos.1.4.2\nv3.32.8-tvos.1.0.0\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', 'v3.44.7-tvos.1.4.2^{commit}'],
        stdout: 'aaaabbbbccccddddeeeeffff0000111122223333\n',
      ),
      const FakeCommand(
        command: <String>['git', 'rev-parse', '--verify', 'HEAD'],
        stdout: 'cafebabecafebabecafebabecafebabecafebabe\n',
      ),
      const FakeCommand(
        command: <String>['git', 'describe', '--tags', '--exact-match', 'HEAD'],
        stdout: 'v3.32.8-tvos.1.0.0\n',
      ),
      const FakeCommand(command: <String>['git', 'status', '-s'], stdout: ''),
      const FakeCommand(
        command: <String>[
          'git',
          'reset',
          '--hard',
          'aaaabbbbccccddddeeeeffff0000111122223333',
        ],
      ),
    ]);
    final command = TvosDowngradeCommand(
      releases: releases,
      toolState: toolState,
      runBootstrap: (_) async => 0,
    );

    await createTestCommandRunner(command).run(<String>['downgrade']);

    expect(processManager, hasNoRemainingExpectations);
    // Going back records where we came from, so downgrade is reversible.
    expect(toolState.readPreviousTag(), 'v3.32.8-tvos.1.0.0');
  }, overrides: <Type, Generator>{Logger: () => logger});
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/flutter-tvos test test/general/tvos_downgrade_command_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:flutter_tvos/commands/downgrade.dart'`

- [ ] **Step 3: Write minimal implementation**

Create `lib/commands/downgrade.dart`:

```dart
// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tvos/commands/use.dart';
import 'package:flutter_tvos/tvos_releases.dart';
import 'package:flutter_tvos/tvos_tool_state.dart';

/// `flutter-tvos downgrade` — returns to the release switched away from.
///
/// Stock `DowngradeCommand` cannot be forwarded: it sets
/// `workingDirectory = Cache.flutterRoot` and runs `git reset --hard` there,
/// and `Cache.flutterRoot` is the *vendored SDK*. That breaks the
/// `flutter.version` ↔ engine-artifact pin the same way stock `upgrade` would,
/// which is why `TvosUpgradeCommand` exists. The next invocation's
/// `update_flutter()` restores the pin, so the damage is bounded — the user
/// just gets a silent revert plus a multi-minute re-bootstrap for nothing.
///
/// Like stock downgrade, this takes no version argument: it only undoes the
/// last switch. Use `flutter-tvos use <version>` to go somewhere specific.
class TvosDowngradeCommand extends TvosUseCommand {
  TvosDowngradeCommand({super.releases, super.toolState, super.runBootstrap});

  @override
  final String name = 'downgrade';

  @override
  final String description =
      'Return to the Flutter version this checkout was switched away from.';

  @override
  String get invocation => 'flutter-tvos downgrade';

  @override
  Future<FlutterCommandResult> runCommand() async {
    final String? previous = toolState.readPreviousTag();
    if (previous == null) {
      throwToolExit(
        'There is no previous flutter-tvos version recorded for this checkout, '
        'so there is nothing to go back to.\n'
        'Run "flutter-tvos versions" to see what is available, then '
        '"flutter-tvos use <version>".',
      );
    }
    return switchTo(previous);
  }
}
```

No constructor changes are needed in `TvosUseCommand`. Dart super-parameters forward by *constructor parameter* name, not field name, so `TvosDowngradeCommand({super.releases, super.toolState, super.runBootstrap})` already binds to `TvosUseCommand`'s `{TvosReleases? releases, TvosToolState? toolState, BootstrapRunner? runBootstrap}` from Task 6, which assign to the private fields. Task 6's tests keep their `releases:` / `toolState:` / `runBootstrap:` call sites untouched.

The one change to `lib/commands/use.dart` is splitting the body so `downgrade` can call it with a tag instead of a command-line argument. Add `import 'package:meta/meta.dart';`, then replace `runCommand` with:

```dart
  @override
  Future<FlutterCommandResult> runCommand() async {
    if (argResults!.rest.length != 1) {
      throwToolExit(
        'Specify exactly one version, e.g. "flutter-tvos use 3.32.8".\n'
        'Run "flutter-tvos versions" to see what is available.',
      );
    }
    return switchTo(argResults!.rest.single);
  }

  /// Everything after argument parsing. `downgrade` reuses this with the tag it
  /// read from the tool state instead of a command-line argument.
  @protected
  Future<FlutterCommandResult> switchTo(String selector) async {
    final TvosRelease target = await releases.resolve(selector);
    final TvosVersion current = await releases.current();

    // Before the dirty-tree guard on purpose: someone with local edits who
    // names the version they are already on should not be refused an
    // operation that would do nothing.
    if (current.tag == target.tag) {
      globals.printStatus('flutter-tvos is already on ${target.flutterVersion} (${target.tag}).');
      return FlutterCommandResult.success();
    }

    if (!boolArg('force') && await releases.hasUncommittedChanges()) {
      throwToolExit(
        'Your flutter-tvos checkout in $_repoRoot has uncommitted changes.\n'
        'Commit or stash them first, or re-run with --force to discard them '
        'and switch anyway.',
      );
    }

    globals.printStatus(
      'Switching flutter-tvos ${current.label} -> ${target.flutterVersion} (${target.tag})...',
    );

    if (current.tag != null) {
      toolState.writePreviousTag(current.tag!);
    }
    await releases.checkout(target.hash!);

    final int code = await _bootstrap(<String>['precache', '--force']);
    if (code != 0) {
      _throwStranded(target, current);
    }

    final int doctorCode = await _bootstrap(<String>['doctor']);
    if (doctorCode != 0) {
      globals.printWarning(
        'Switched to ${target.flutterVersion}, but "flutter-tvos doctor" reported problems.',
      );
    }

    globals.printStatus('');
    globals.printStatus('Now on Flutter ${target.flutterVersion} (${target.tag}).');
    return FlutterCommandResult.success();
  }
```

`TvosDowngradeCommand` inherits the `--force` flag from `TvosUseCommand`'s constructor, which is correct: going back can hit a dirty tree for the same reasons going forward can.

Then in `lib/executable.dart`:
- Replace `DowngradeCommand(verboseHelp: verboseHelp, logger: globals.logger),` with `TvosDowngradeCommand(),`
- Delete the `ChannelCommand(verboseHelp: verboseHelp),` line entirely
- Remove the now-unused imports of `package:flutter_tools/src/commands/channel.dart` and `package:flutter_tools/src/commands/downgrade.dart`
- Add `import 'package:flutter_tvos/commands/downgrade.dart';`

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/flutter-tvos test test/general/tvos_downgrade_command_test.dart test/general/tvos_use_command_test.dart`
Expected: PASS — downgrade's 2 tests plus use's 6, unbroken by the refactor.

- [ ] **Step 5: Verify the command surface by hand**

Run: `bin/flutter-tvos --help`
Expected: `versions`, `use` and `downgrade` listed; **no** `channel`.

Run: `bin/flutter-tvos channel`
Expected: `Could not find a command named "channel"`.

- [ ] **Step 6: Commit**

```bash
git add lib/commands/downgrade.dart lib/commands/use.dart lib/executable.dart test/general/tvos_downgrade_command_test.dart
git commit -m "Override downgrade, unregister channel

Both were forwarded stock in the block commented 'no tvOS-specific
behaviour', and both are: stock DowngradeCommand sets workingDirectory to
Cache.flutterRoot -- the vendored SDK -- and resets hard in it, breaking the
flutter.version to engine-artifact pin exactly as stock upgrade would. The
next invocation restores the pin, so the user only loses a silent revert and
a re-bootstrap, but it is still wrong.

downgrade now moves the flutter-tvos checkout back to the tag recorded in
.git/flutter-tvos-previous, and takes no version argument, matching stock.
channel is gone: we pin a commit, not a channel, so it had nothing to say."
```

---

### Task 8: Point `upgrade` at `TvosReleases`

Narrow delegation. `TvosUpgradeCommand`'s two-phase `--continue` flow is unchanged — only where it gets tags from moves.

**Files:**
- Modify: `lib/commands/upgrade.dart`
- Test: `test/general/tvos_upgrade_test.dart` (existing — must keep passing)

**Interfaces:**
- Consumes: `TvosReleases.list()` from Task 2.
- Produces: nothing new.

- [ ] **Step 1: Run the existing tests to establish the baseline**

Run: `bin/flutter-tvos test test/general/tvos_upgrade_test.dart`
Expected: PASS. Record the count; it must not change.

- [ ] **Step 2: Delegate tag discovery**

In `lib/commands/upgrade.dart`, replace the body of `fetchLatestReleaseVersion` so it uses `TvosReleases` instead of running git itself, keeping the same signature, the same `TvosVersion` return, and the same tool-exit message:

```dart
  /// Fetches tags from the remote and resolves the newest release tag.
  Future<TvosVersion> fetchLatestReleaseVersion() async {
    final releases = TvosReleases(
      workingDirectory: workingDirectory!,
      processUtils: _processUtils,
    );
    final List<TvosRelease> all = await releases.list();
    if (all.isEmpty) {
      throwToolExit(
        'Unable to upgrade flutter-tvos: no release tags '
        '(v<flutter>-tvos.<version>) were found.\n'
        'Make sure your flutter-tvos checkout tracks the upstream repository.',
      );
    }
    // Peel here rather than calling resolve(): resolve() runs list() again,
    // which would issue a second `git fetch --tags` and break the command
    // sequence the existing test asserts.
    final TvosRelease newest = all.first;
    final TvosRelease resolved = newest.withHash(
      await releases.peelToCommit(newest.tag),
    );
    return TvosVersion(hash: resolved.hash!, tag: resolved.tag);
  }
```

`peelToCommit` is already public from Task 2; nothing in `tvos_releases.dart` changes here.

**The existing test is the specification for this task.** It asserts the exact sequence `git fetch --tags` → `git tag -l --sort=-v:refname` → `git rev-parse <tag>^{commit}`, which the code above reproduces. If your delegation changes that sequence, the delegation is wrong — do not edit the test to match.

- [ ] **Step 3: Run the existing tests to verify they still pass**

Run: `bin/flutter-tvos test test/general/tvos_upgrade_test.dart`
Expected: PASS, same count as Step 1, with no edits to the test file.

- [ ] **Step 4: Run the whole suite**

Run: `bin/flutter-tvos test test/general`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/commands/upgrade.dart
git commit -m "Point upgrade's tag discovery at TvosReleases

Delegation only: the two-phase --continue flow, the messages and the git
command sequence are unchanged, which the untouched existing test enforces.
Restructuring upgrade to share use's single-phase flow would be a behaviour
change wearing a refactor's clothes."
```

---

## Definition of done

- [ ] `bin/flutter-tvos test test/general` passes.
- [ ] `bin/flutter-tvos versions` lists the real tags with exactly one marked current.
- [ ] `bin/flutter-tvos use <a version already checked out>` reports "already on" and exits 0.
- [ ] `bin/flutter-tvos --help` shows `versions`, `use`, `downgrade`, and no `channel`.
- [ ] `git grep -n "ChannelCommand" lib/` returns nothing.
- [ ] No file in `lib/` reads or writes `~/.config` for version state.
