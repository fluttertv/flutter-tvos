// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tvos/plugin_porting/example_extender.dart';
import 'package:flutter_tvos/plugin_porting/source_analyzer.dart';

import '../src/common.dart';

PluginSource _analyze(FileSystem fs, {bool withExample = true, String? examplePubspec}) {
  final Directory dir = fs.directory('/src/url_launcher_ios')..createSync(recursive: true);
  dir.childFile('pubspec.yaml').writeAsStringSync('''
name: url_launcher_ios
description: iOS implementation of url_launcher.
version: 6.3.4

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  url_launcher_platform_interface: ^2.4.0

flutter:
  plugin:
    platforms:
      ios:
        pluginClass: URLLauncherPlugin
        dartPluginClass: UrlLauncherIOS
''');
  dir.childDirectory('ios').childDirectory('Classes').childFile('URLLauncherPlugin.swift')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('import Flutter\n');
  if (withExample) {
    final Directory ex = dir.childDirectory('example')..createSync();
    ex.childDirectory('lib').childFile('main.dart')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');
    ex.childFile('pubspec.yaml').writeAsStringSync(examplePubspec ??
        '''
name: url_launcher_example
environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  url_launcher: ^6.0.0
''');
  }
  return SourceAnalyzer(fileSystem: fs).analyze(dir);
}

void main() {
  late MemoryFileSystem fs;
  setUp(() => fs = MemoryFileSystem.test());

  group('ExampleExtender', () {
    testWithoutContext('adds dependency_overrides + README note', () {
      final PluginSource source = _analyze(fs);
      final Directory out = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);

      final ExampleExtendResult r = ExampleExtender(fileSystem: fs)
          .extend(source: source, outputPackageDir: out);

      expect(r.skipped, isFalse);
      final String pubspec = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('pubspec.yaml')
          .readAsStringSync();
      expect(pubspec, contains('dependency_overrides:'));
      expect(pubspec, contains('  url_launcher_ios:'));
      expect(pubspec, contains('  url_launcher_tvos:'));
      // Path is relative to the example dir.
      expect(pubspec, contains('path: ..'));
      expect(pubspec, contains('path: ../../../out/url_launcher_tvos'));

      final String readme = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('README.md')
          .readAsStringSync();
      expect(readme, contains('On tvOS: run `flutter-tvos run`.'));
      expect(r.createCommand, contains('flutter-tvos create'));
      expect(r.writtenPaths, isNotEmpty);
    });

    testWithoutContext('is idempotent across repeated ports', () {
      final PluginSource source = _analyze(fs);
      final Directory out = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);
      final ExampleExtender extender = ExampleExtender(fileSystem: fs);

      extender.extend(source: source, outputPackageDir: out);
      final String afterFirst = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('pubspec.yaml')
          .readAsStringSync();
      final ExampleExtendResult second =
          extender.extend(source: source, outputPackageDir: out);
      final String afterSecond = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('pubspec.yaml')
          .readAsStringSync();

      expect(afterSecond, afterFirst, reason: 'second run must not duplicate entries');
      expect(second.writtenPaths, isEmpty, reason: 'nothing left to change');
      // Only one occurrence of each override key.
      expect('  url_launcher_tvos:'.allMatches(afterSecond).length, 1);
      final String readme = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('README.md')
          .readAsStringSync();
      expect('On tvOS: run `flutter-tvos run`.'.allMatches(readme).length, 1);
    });

    testWithoutContext('inserts under an existing dependency_overrides block', () {
      final PluginSource source = _analyze(fs, examplePubspec: '''
name: url_launcher_example
dependencies:
  flutter:
    sdk: flutter

dependency_overrides:
  some_pkg:
    path: ../../some_pkg
''');
      final Directory out = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);

      ExampleExtender(fileSystem: fs).extend(source: source, outputPackageDir: out);

      final String pubspec = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('pubspec.yaml')
          .readAsStringSync();
      expect('dependency_overrides:'.allMatches(pubspec).length, 1,
          reason: 'must reuse the existing block, not add a second');
      expect(pubspec, contains('  some_pkg:'));
      expect(pubspec, contains('  url_launcher_tvos:'));
    });

    testWithoutContext('does not clobber a user-provided override', () {
      final PluginSource source = _analyze(fs, examplePubspec: '''
name: url_launcher_example
dependencies:
  flutter:
    sdk: flutter

dependency_overrides:
  url_launcher_tvos:
    path: /custom/location
''');
      final Directory out = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);

      ExampleExtender(fileSystem: fs).extend(source: source, outputPackageDir: out);

      final String pubspec = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('pubspec.yaml')
          .readAsStringSync();
      expect(pubspec, contains('path: /custom/location'));
      expect('  url_launcher_tvos:'.allMatches(pubspec).length, 1);
    });

    testWithoutContext('skips gracefully when there is no example/', () {
      final PluginSource source = _analyze(fs, withExample: false);
      final Directory out = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);

      final ExampleExtendResult r = ExampleExtender(fileSystem: fs)
          .extend(source: source, outputPackageDir: out);

      expect(r.skipped, isTrue);
      expect(r.reason, contains('No example/'));
    });

    testWithoutContext('--dry-run reports changes but writes nothing', () {
      final PluginSource source = _analyze(fs);
      final Directory out = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);

      final ExampleExtendResult r = ExampleExtender(fileSystem: fs)
          .extend(source: source, outputPackageDir: out, dryRun: true);

      expect(r.skipped, isFalse);
      expect(r.writtenPaths, isNotEmpty);
      final String pubspec = fs
          .directory('/src/url_launcher_ios/example')
          .childFile('pubspec.yaml')
          .readAsStringSync();
      expect(pubspec, isNot(contains('dependency_overrides:')));
      expect(
        fs.directory('/src/url_launcher_ios/example').childFile('README.md').existsSync(),
        isFalse,
      );
    });
  });
}
