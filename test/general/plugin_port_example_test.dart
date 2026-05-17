// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tvos/plugin_porting/example_porter.dart';

import '../src/common.dart';

Directory _basePluginWithExample(FileSystem fs) {
  final Directory base = fs.directory('/src/audbox')..createSync(recursive: true);
  final Directory ex = base.childDirectory('example')..createSync(recursive: true);
  ex.childDirectory('lib').childFile('main.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
        "import 'package:audbox/audbox.dart';\nvoid main() {}\n");
  ex.childDirectory('assets').childFile('sound.mp3')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('ID3');
  // Other-platform folders that must be dropped.
  ex.childDirectory('android').childFile('build.gradle')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('// android');
  ex.childDirectory('ios').childFile('Podfile')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('# ios');
  ex.childFile('pubspec.yaml').writeAsStringSync('''
name: audbox_example
description: Demonstrates audbox.
publish_to: "none"

environment:
  sdk: ">=3.1.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  audbox:
    path: ../
  provider: ^6.0.5

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
  assets:
    - assets/
''');
  return base;
}

void main() {
  late MemoryFileSystem fs;
  setUp(() => fs = MemoryFileSystem.test());

  group('ExamplePorter', () {
    test('copies upstream example, drops other platforms, dual-deps pubspec', () {
      final Directory base = _basePluginWithExample(fs);
      final Directory out = fs.directory('/out/audbox_tvos')..createSync(recursive: true);

      final ExamplePortResult r = ExamplePorter(fileSystem: fs).port(
        basePluginDir: base,
        outputPackageDir: out,
        baseName: 'audbox',
        tvosPackageName: 'audbox_tvos',
        baseVersion: '6.6.0',
      );

      expect(r.skipped, isFalse);
      final Directory exo = out.childDirectory('example');
      // Real example code + assets copied.
      expect(exo.childDirectory('lib').childFile('main.dart').readAsStringSync(),
          contains("import 'package:audbox/audbox.dart'"));
      expect(exo.childDirectory('assets').childFile('sound.mp3').existsSync(), isTrue);
      // Other platforms dropped.
      expect(exo.childDirectory('android').existsSync(), isFalse);
      expect(exo.childDirectory('ios').existsSync(), isFalse);

      final String pub = exo.childFile('pubspec.yaml').readAsStringSync();
      // App-facing plugin pinned to the resolved version (path replaced).
      expect(pub, contains('  audbox: ^6.6.0'));
      expect(pub, isNot(contains('audbox:\n    path: ../')));
      // Federated impl under test wired by local path.
      expect(pub, contains('  audbox_tvos:\n    path: ../'));
      // Untouched deps preserved.
      expect(pub, contains('  provider: ^6.0.5'));
      expect(pub, contains('  flutter:\n    sdk: flutter'));
      // Example assets section preserved.
      expect(pub, contains('assets:'));
    });

    test('idempotent: re-porting replaces managed keys, no duplicates', () {
      final Directory base = _basePluginWithExample(fs);
      final Directory out = fs.directory('/out/audbox_tvos')..createSync(recursive: true);
      final ExamplePorter p = ExamplePorter(fileSystem: fs);
      p.port(
        basePluginDir: base,
        outputPackageDir: out,
        baseName: 'audbox',
        tvosPackageName: 'audbox_tvos',
        baseVersion: '6.6.0',
      );
      p.port(
        basePluginDir: base,
        outputPackageDir: out,
        baseName: 'audbox',
        tvosPackageName: 'audbox_tvos',
        baseVersion: '6.7.0',
      );
      final String pub =
          out.childDirectory('example').childFile('pubspec.yaml').readAsStringSync();
      expect('audbox_tvos:'.allMatches(pub).length, 1);
      expect(pub, contains('  audbox: ^6.7.0'));
      expect(pub, isNot(contains('^6.6.0')));
    });

    test('skips when the app-facing plugin has no usable example', () {
      final Directory base = fs.directory('/src/foo')..createSync(recursive: true);
      final Directory out = fs.directory('/out/foo_tvos')..createSync(recursive: true);

      final ExamplePortResult r = ExamplePorter(fileSystem: fs).port(
        basePluginDir: base,
        outputPackageDir: out,
        baseName: 'foo',
        tvosPackageName: 'foo_tvos',
        baseVersion: '1.0.0',
      );
      expect(r.skipped, isTrue);
      expect(r.reason, contains('no usable example/'));
    });
  });
}
