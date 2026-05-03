// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tvos/plugin_porting/scaffolder.dart';
import 'package:flutter_tvos/plugin_porting/source_analyzer.dart';

import '../src/common.dart';

void main() {
  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test();
  });

  group('SourceAnalyzer', () {
    testWithoutContext('reads a federated iOS plugin pubspec', () {
      final Directory dir = _createIosPlugin(fs, name: 'url_launcher_ios');

      final analyzer = SourceAnalyzer(fileSystem: fs);
      final PluginSource source = analyzer.analyze(dir);

      expect(source.packageName, 'url_launcher_ios');
      expect(source.basePackageName, 'url_launcher');
      expect(source.outputPackageName, 'url_launcher_tvos');
      expect(source.sourcePlatform, 'ios');
      expect(source.pluginClass, 'URLLauncherPlugin');
      expect(source.dartPluginClass, 'UrlLauncherIOS');
      expect(source.platformInterfacePackage, 'url_launcher_platform_interface');
      expect(source.sourceLanguage, SourceLanguage.swift);
    });

    testWithoutContext('strips _foundation suffix on shared iOS/macOS packages', () {
      final Directory dir = _createIosPlugin(fs, name: 'shared_preferences_foundation');

      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);

      expect(source.basePackageName, 'shared_preferences');
      expect(source.outputPackageName, 'shared_preferences_tvos');
    });

    testWithoutContext('rejects pure-Dart plugins with no native impl', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: my_pure_dart_plugin
flutter:
  plugin:
    platforms:
      web:
        pluginClass: MyPlugin
''');

      expect(
        () => SourceAnalyzer(fileSystem: fs).analyze(dir),
        throwsA(
          isA<PluginSourceError>().having(
            (PluginSourceError e) => e.message,
            'message',
            contains('neither an `ios` nor a `macos`'),
          ),
        ),
      );
    });

    testWithoutContext('rejects packages already targeting tvOS', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('name: foo_tvos\n');

      expect(
        () => SourceAnalyzer(fileSystem: fs).analyze(dir),
        throwsA(
          isA<PluginSourceError>().having(
            (PluginSourceError e) => e.message,
            'message',
            contains('already targets tvOS'),
          ),
        ),
      );
    });

    testWithoutContext('refuses missing pubspec', () {
      final Directory dir = fs.directory('/p')..createSync();

      expect(
        () => SourceAnalyzer(fileSystem: fs).analyze(dir),
        throwsA(isA<PluginSourceError>()),
      );
    });

    testWithoutContext('detects Objective-C sources', () {
      final Directory dir = _createIosPlugin(fs, name: 'audio_session', objc: true);

      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);

      expect(source.sourceLanguage, SourceLanguage.objc);
    });

    testWithoutContext('falls back to macOS when iOS is missing and prefer=ios', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: path_provider_macos
flutter:
  plugin:
    platforms:
      macos:
        pluginClass: PathProviderPlugin
        dartPluginClass: PathProviderMacOS
''');
      dir.childDirectory('macos').childDirectory('Classes').createSync(recursive: true);
      dir.childDirectory('macos').childDirectory('Classes').childFile('PathProviderPlugin.swift').writeAsStringSync('// stub');

      final warnings = <String>[];
      final PluginSource source = SourceAnalyzer(
        fileSystem: fs,
        warningSink: warnings.add,
      ).analyze(dir);

      expect(source.sourcePlatform, 'macos');
      expect(warnings.single, contains('no iOS implementation'));
    });
  });

  group('Scaffolder', () {
    testWithoutContext('writes a complete federated package skeleton', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'url_launcher_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/url_launcher_tvos');

      final scaffolder = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test Holder',
      );
      final ScaffoldResult result = scaffolder.scaffold(source: source, outputDirectory: outputDir);

      expect(result.dryRun, isFalse);

      // Pubspec
      final String pubspec = outputDir.childFile('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: url_launcher_tvos'));
      expect(pubspec, contains('pluginClass: URLLauncherPlugin'));
      expect(pubspec, contains('dartPluginClass: UrlLauncherIOS'));
      expect(pubspec, contains('url_launcher_platform_interface: ^1.0.0'));

      // Podspec
      final String podspec = outputDir.childDirectory('tvos').childFile('url_launcher_tvos.podspec').readAsStringSync();
      expect(podspec, contains("s.name             = 'url_launcher_tvos'"));
      expect(podspec, contains(':tvos, '));
      expect(podspec, isNot(contains("s.dependency 'Flutter'")),
          reason: 'podspec must not depend on the Flutter pod, which lacks tvOS support');
      expect(podspec, contains('FRAMEWORK_SEARCH_PATHS'));

      // Swift stub references the plugin class name from the source pubspec.
      final String swift = outputDir
          .childDirectory('tvos')
          .childDirectory('Classes')
          .childFile('URLLauncherPlugin.swift')
          .readAsStringSync();
      expect(swift, contains('public class URLLauncherPlugin'));
      expect(swift, contains('register(with registrar:'));

      // Bridging header is the same basename + -Bridging-Header.h.
      expect(
        outputDir
            .childDirectory('tvos')
            .childDirectory('Classes')
            .childFile('URLLauncherPlugin-Bridging-Header.h')
            .existsSync(),
        isTrue,
      );

      // Dart entry uses the dartPluginClass and the platform interface package.
      final String dartEntry = outputDir
          .childDirectory('lib')
          .childFile('url_launcher_tvos.dart')
          .readAsStringSync();
      expect(dartEntry, contains("import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart'"));
      expect(dartEntry, contains('base class UrlLauncherIOS extends UrlLauncherPlatform'));
      expect(dartEntry, contains('static void registerWith()'));

      // Test stub.
      expect(
        outputDir.childDirectory('test').childFile('url_launcher_tvos_test.dart').existsSync(),
        isTrue,
      );

      // Standard package files.
      expect(outputDir.childFile('README.md').existsSync(), isTrue);
      expect(outputDir.childFile('CHANGELOG.md').existsSync(), isTrue);
      expect(outputDir.childFile('analysis_options.yaml').existsSync(), isTrue);
      expect(outputDir.childFile('.gitignore').existsSync(), isTrue);
    });

    testWithoutContext('--dry-run does not write any files', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'url_launcher_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/url_launcher_tvos');

      final scaffolder = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      );
      final ScaffoldResult result = scaffolder.scaffold(
        source: source,
        outputDirectory: outputDir,
        dryRun: true,
      );

      expect(result.dryRun, isTrue);
      expect(result.writtenPaths, isNotEmpty);
      expect(outputDir.existsSync(), isFalse);
    });

    testWithoutContext('refuses to overwrite without --force', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'url_launcher_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);
      outputDir.childFile('preexisting.txt').writeAsStringSync('do not touch');

      final scaffolder = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      );
      expect(
        () => scaffolder.scaffold(source: source, outputDirectory: outputDir),
        throwsA(
          isA<ScaffoldError>().having(
            (ScaffoldError e) => e.message,
            'message',
            contains('Output directory already exists'),
          ),
        ),
      );
      // The pre-existing file is still there.
      expect(outputDir.childFile('preexisting.txt').existsSync(), isTrue);
    });

    testWithoutContext('--force overwrites the output directory', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'url_launcher_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/url_launcher_tvos')..createSync(recursive: true);
      outputDir.childFile('preexisting.txt').writeAsStringSync('overwrite me');

      final scaffolder = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      );
      scaffolder.scaffold(
        source: source,
        outputDirectory: outputDir,
        overwrite: true,
      );

      expect(outputDir.childFile('preexisting.txt').existsSync(), isFalse);
      expect(outputDir.childFile('pubspec.yaml').existsSync(), isTrue);
    });

    testWithoutContext('copies LICENSE from source when present', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'url_launcher_ios');
      sourceDir.childFile('LICENSE').writeAsStringSync('BSD-3 license body');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/url_launcher_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: outputDir);

      expect(outputDir.childFile('LICENSE').readAsStringSync(), 'BSD-3 license body');
    });
  });
}

/// Builds a minimal but valid iOS plugin in [fs] under `/p` and returns it.
///
/// Keeps the fixture inline so test files don't need on-disk artefacts. The
/// pubspec mirrors a real federated plugin (url_launcher_ios style).
Directory _createIosPlugin(FileSystem fs, {required String name, bool objc = false}) {
  final Directory dir = fs.directory('/p')..createSync();
  dir.childFile('pubspec.yaml').writeAsStringSync('''
name: $name
description: iOS implementation of url_launcher.
version: 6.3.4
homepage: https://github.com/flutter/packages/

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.13.0"

dependencies:
  flutter:
    sdk: flutter
  url_launcher_platform_interface: ^2.4.0

flutter:
  plugin:
    implements: url_launcher
    platforms:
      ios:
        pluginClass: URLLauncherPlugin
        dartPluginClass: UrlLauncherIOS
''');
  final Directory classes = dir.childDirectory('ios').childDirectory('Classes')
    ..createSync(recursive: true);
  if (objc) {
    classes.childFile('URLLauncherPlugin.h').writeAsStringSync('// header');
    classes.childFile('URLLauncherPlugin.m').writeAsStringSync('// impl');
  } else {
    classes.childFile('URLLauncherPlugin.swift').writeAsStringSync('// stub');
  }
  return dir;
}
