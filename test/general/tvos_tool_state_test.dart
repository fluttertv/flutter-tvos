// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tvos/tvos_tool_state.dart';

import '../src/common.dart';
import '../src/context.dart';

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

  // Plain test() has no Zone context, so globals.printTrace's globals.logger
  // lookup (context.get<Logger>()!) would throw a TypeError before we ever
  // get to see whether the write itself throws. testUsingContext supplies a
  // BufferLogger so the catch's printTrace call has somewhere to go.
  testUsingContext('a write that fails does not throw', () {
    // A checkout whose .git is a file, not a directory — git worktrees and
    // submodules do this. Losing the downgrade breadcrumb is a degraded
    // experience; aborting the switch over it would be worse.
    final fs = MemoryFileSystem.test();
    fs.file('/wt/.git').createSync(recursive: true);
    final worktreeState = TvosToolState(repoRoot: '/wt', fileSystem: fs);

    expect(() => worktreeState.writePreviousTag('v3.44.7-tvos.1.4.2'), returnsNormally);
    expect(worktreeState.readPreviousTag(), isNull);
  });
}
