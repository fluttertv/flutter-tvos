// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tvos/build_targets/application.dart';

import '../src/common.dart';

void main() {
  late MemoryFileSystem fileSystem;

  setUp(() {
    fileSystem = MemoryFileSystem.test();
  });

  List<String> argsFor(Map<String, String> defines) {
    return NativeTvosBundle.tvosGenSnapshotArgs(
      fileSystem: fileSystem,
      genSnapshotPath: '/engine/gen_snapshot',
      assemblyPath: '/out/aot/snapshot_assembly.S',
      kernelSnapshotPath: '/out/app.dill',
      defines: defines,
    );
  }

  testWithoutContext('always emits the base assembly invocation with kernel last', () {
    final List<String> args = argsFor(<String, String>{});
    expect(args.first, '/engine/gen_snapshot');
    expect(
      args,
      containsAllInOrder(<String>[
        '--snapshot_kind=app-aot-assembly',
        '--assembly=/out/aot/snapshot_assembly.S',
      ]),
    );
    expect(args.last, '/out/app.dill');
  });

  testWithoutContext('omits --obfuscate and debug flags when defines are absent', () {
    final List<String> args = argsFor(<String, String>{});
    expect(args, isNot(contains('--obfuscate')));
    expect(args, isNot(contains('--dwarf-stack-traces')));
    expect(args.any((String a) => a.startsWith('--save-debugging-info=')), isFalse);
  });

  testWithoutContext('passes --obfuscate when kDartObfuscation is true', () {
    // The helper is tested in isolation. In production, obfuscation always
    // arrives paired with split-debug-info: upstream FlutterCommand.getBuildInfo
    // rejects `--obfuscate` without `--split-debug-info` (throwToolExit) before
    // the defines ever reach this helper, so we use the reachable combination.
    // Note the helper still emits `--obfuscate` independently of split-debug-info,
    // matching AOTSnapshotter.build (build.dart) which does not gate one on the other.
    final List<String> args = argsFor(<String, String>{
      kDartObfuscation: 'true',
      kSplitDebugInfo: '/symbols',
    });
    expect(args, contains('--obfuscate'));
  });

  testWithoutContext('does not pass --obfuscate when kDartObfuscation is false', () {
    final List<String> args = argsFor(<String, String>{kDartObfuscation: 'false'});
    expect(args, isNot(contains('--obfuscate')));
  });

  testWithoutContext(
    'emits DWARF flags and arch-named symbols path when split-debug-info is set',
    () {
      final List<String> args = argsFor(<String, String>{kSplitDebugInfo: '/symbols'});
      expect(args, contains('--dwarf-stack-traces'));
      expect(args, contains('--resolve-dwarf-paths'));
      expect(args, contains('--save-debugging-info=/symbols/app.tvos-arm64.symbols'));
    },
  );

  testWithoutContext('ignores an empty split-debug-info value', () {
    final List<String> args = argsFor(<String, String>{kSplitDebugInfo: ''});
    expect(args, isNot(contains('--dwarf-stack-traces')));
    expect(args.any((String a) => a.startsWith('--save-debugging-info=')), isFalse);
  });

  testWithoutContext('forwards extra gen_snapshot options', () {
    final List<String> args = argsFor(<String, String>{
      kExtraGenSnapshotOptions: '--foo,--bar=baz',
    });
    expect(args, containsAllInOrder(<String>['--foo', '--bar=baz']));
    // Extra options precede the kernel path.
    expect(args.indexOf('--bar=baz'), lessThan(args.indexOf('/out/app.dill')));
  });

  testWithoutContext('combines obfuscation, split-debug-info, and extra options', () {
    final List<String> args = argsFor(<String, String>{
      kDartObfuscation: 'true',
      kSplitDebugInfo: '/symbols',
      kExtraGenSnapshotOptions: '--write-v8-snapshot-profile-to=/tmp/p.json',
    });
    expect(args, contains('--obfuscate'));
    expect(args, contains('--save-debugging-info=/symbols/app.tvos-arm64.symbols'));
    expect(args, contains('--write-v8-snapshot-profile-to=/tmp/p.json'));
    expect(args.last, '/out/app.dill');
  });
}
