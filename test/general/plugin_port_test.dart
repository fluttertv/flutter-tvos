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
      // The source's own constraint is carried over verbatim (not a
      // hardcoded ^1.0.0, which would break `pub get` for real plugins).
      expect(pubspec, contains('url_launcher_platform_interface: ^2.4.0'));

      // Podspec
      final String podspec = outputDir.childDirectory('tvos').childFile('url_launcher_tvos.podspec').readAsStringSync();
      expect(podspec, contains("s.name             = 'url_launcher_tvos'"));
      expect(podspec, contains(':tvos, '));
      expect(podspec, isNot(contains("s.dependency 'Flutter'")),
          reason: 'podspec must not depend on the Flutter pod, which lacks tvOS support');
      expect(podspec, contains('FRAMEWORK_SEARCH_PATHS'));

      // Phase 2: the real iOS source from the fixture is copied verbatim.
      // The Phase-1 stub is only emitted as a fallback when the source has
      // no native files at all (covered by a separate test below).
      final String swift = outputDir
          .childDirectory('tvos')
          .childDirectory('Classes')
          .childFile('URLLauncherPlugin.swift')
          .readAsStringSync();
      expect(
        swift,
        equals(_kRealisticSwiftSource),
        reason: 'Swift source should be copied verbatim from <ios>/Classes/',
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

    testWithoutContext('copies Objective-C sources verbatim', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'audio_session', objc: true);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/audio_session_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: outputDir);

      // Both .h and .m land in tvos/Classes/ unchanged.
      final Directory tvosClasses = outputDir.childDirectory('tvos').childDirectory('Classes');
      expect(tvosClasses.childFile('URLLauncherPlugin.h').readAsStringSync(), _kRealisticObjcHeader);
      expect(tvosClasses.childFile('URLLauncherPlugin.m').readAsStringSync(), _kRealisticObjcImpl);

      // No Swift stub written when ObjC sources are present.
      expect(tvosClasses.childFile('URLLauncherPlugin.swift').existsSync(), isFalse);
    });

    testWithoutContext('preserves subdirectory structure under Classes/', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'url_launcher_ios');
      // Add a nested helper file.
      sourceDir
          .childDirectory('ios')
          .childDirectory('Classes')
          .childDirectory('Helpers')
          .childFile('UrlValidator.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// helper');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/url_launcher_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: outputDir);

      // Helper landed at tvos/Classes/Helpers/UrlValidator.swift, not
      // flattened. Phase 3: Swift files flow through SwiftPorter, which
      // normalises the file to end with exactly one trailing newline — so
      // the content is the source plus a `\n`, not a byte-for-byte copy.
      expect(
        outputDir
            .childDirectory('tvos')
            .childDirectory('Classes')
            .childDirectory('Helpers')
            .childFile('UrlValidator.swift')
            .readAsStringSync(),
        '// helper\n',
      );
    });

    testWithoutContext('copies <platform>/Resources/ when present', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'url_launcher_ios');
      sourceDir
          .childDirectory('ios')
          .childDirectory('Resources')
          .childFile('Localizable.strings')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('"key" = "value";');
      sourceDir
          .childDirectory('ios')
          .childDirectory('Resources')
          .childDirectory('Assets.xcassets')
          .childFile('Contents.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"info": {"version": 1}}');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/url_launcher_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: outputDir);

      final Directory tvosResources = outputDir.childDirectory('tvos').childDirectory('Resources');
      expect(tvosResources.childFile('Localizable.strings').readAsStringSync(), '"key" = "value";');
      expect(
        tvosResources.childDirectory('Assets.xcassets').childFile('Contents.json').readAsStringSync(),
        '{"info": {"version": 1}}',
      );
    });

    testWithoutContext('falls back to Swift stub when source has no native files', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: empty_native_plugin
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: EmptyNativePlugin
        dartPluginClass: EmptyNativePluginIOS
''');
      // Note: no ios/Classes/ files at all.
      dir.childDirectory('ios').childDirectory('Classes').createSync(recursive: true);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);
      final Directory outputDir = fs.directory('/out/empty_native_plugin_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: outputDir);

      final Directory tvosClasses = outputDir.childDirectory('tvos').childDirectory('Classes');
      // Stub Swift class is emitted with the plugin class name from pubspec.
      expect(
        tvosClasses.childFile('EmptyNativePlugin.swift').readAsStringSync(),
        contains('public class EmptyNativePlugin'),
      );
      // Bridging header companion is also written in stub mode.
      expect(tvosClasses.childFile('EmptyNativePlugin-Bridging-Header.h').existsSync(), isTrue);
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

  group('SourceAnalyzer modern layouts', () {
    testWithoutContext('resolves a Swift Package Manager layout', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: url_launcher_ios
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: URLLauncherPlugin
        dartPluginClass: UrlLauncherIOS
''');
      dir
          .childDirectory('ios')
          .childDirectory('url_launcher_ios')
          .childDirectory('Sources')
          .childDirectory('url_launcher_ios')
          .childFile('URLLauncherPlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('import Flutter\n');
      dir
          .childDirectory('ios')
          .childDirectory('url_launcher_ios')
          .childFile('Package.swift')
          .writeAsStringSync('// swift-tools-version:5.9\n');

      final PluginSource s = SourceAnalyzer(fileSystem: fs).analyze(dir);
      expect(s.classesDirectory.path, contains('ios/url_launcher_ios/Sources/url_launcher_ios'));
      expect(s.pluginClass, 'URLLauncherPlugin');
    });

    testWithoutContext('resolves sharedDarwinSource under darwin/', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: shared_preferences_foundation
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: SharedPreferencesPlugin
        dartPluginClass: SharedPreferencesFoundation
        sharedDarwinSource: true
      macos:
        pluginClass: SharedPreferencesPlugin
        dartPluginClass: SharedPreferencesFoundation
        sharedDarwinSource: true
''');
      dir
          .childDirectory('darwin')
          .childDirectory('shared_preferences_foundation')
          .childDirectory('Sources')
          .childDirectory('shared_preferences_foundation')
          .childFile('SharedPreferencesPlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('import Flutter\n');

      final PluginSource s = SourceAnalyzer(fileSystem: fs).analyze(dir);
      expect(s.classesDirectory.path,
          contains('darwin/shared_preferences_foundation/Sources'));
      expect(s.basePackageName, 'shared_preferences');
    });

    testWithoutContext('infers pluginClass from sources when pubspec omits it', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: foo_ios
flutter:
  plugin:
    platforms:
      ios:
        dartPluginClass: FooIOS
''');
      dir
          .childDirectory('ios')
          .childDirectory('Classes')
          .childFile('FooNativePlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
            'import Flutter\npublic class FooNativePlugin: NSObject, FlutterPlugin {}\n');

      final warnings = <String>[];
      final PluginSource s = SourceAnalyzer(fileSystem: fs, warningSink: warnings.add).analyze(dir);
      expect(s.pluginClass, 'FooNativePlugin');
      expect(warnings.join(), contains('declares no `pluginClass`'));
    });

    testWithoutContext('advisory exit for a pure-Dart/FFI plugin (no native, no pluginClass)', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: path_provider_foundation
dependencies:
  ffi: ^2.1.4
  objective_c: ^9.2.1
flutter:
  plugin:
    platforms:
      ios:
        dartPluginClass: PathProviderFoundation
      macos:
        dartPluginClass: PathProviderFoundation
''');
      // No native sources anywhere.
      expect(
        () => SourceAnalyzer(fileSystem: fs).analyze(dir),
        throwsA(isA<PluginSourceError>()
            .having((PluginSourceError e) => e.advisory, 'advisory', isTrue)
            .having((PluginSourceError e) => e.message, 'm',
                contains('no `path_provider_tvos` package is needed'))),
      );
    });

    testWithoutContext('SPM Package.swift is excluded from the generated package', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: url_launcher_ios
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: URLLauncherPlugin
''');
      final Directory spm = dir
          .childDirectory('ios')
          .childDirectory('url_launcher_ios')
          .childDirectory('Sources')
          .childDirectory('url_launcher_ios')
        ..createSync(recursive: true);
      spm.childFile('URLLauncherPlugin.swift').writeAsStringSync('import Flutter\n');
      // A stray Package.swift inside the resolved sources dir must be
      // filtered out by the scaffolder, not copied into Classes/.
      spm.childFile('Package.swift').writeAsStringSync('// swift-tools-version:5.9\n');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);
      final Directory out = fs.directory('/out/url_launcher_tvos');

      Scaffolder(fileSystem: fs, logger: BufferLogger.test(), licenseHolder: 'T')
          .scaffold(source: source, outputDirectory: out);

      final Directory tvosClasses = out.childDirectory('tvos').childDirectory('Classes');
      expect(tvosClasses.childFile('URLLauncherPlugin.swift').existsSync(), isTrue);
      expect(tvosClasses.childFile('Package.swift').existsSync(), isFalse,
          reason: 'SPM manifest must not be copied into Classes/');
    });

    testWithoutContext('strips federated Apple impl suffixes for the output name', () {
      for (final (String src, String want) in <(String, String)>[
        ('video_player_avfoundation', 'video_player_tvos'),
        ('in_app_purchase_storekit', 'in_app_purchase_tvos'),
        ('geolocator_apple', 'geolocator_tvos'),
        ('audioplayers_darwin', 'audioplayers_tvos'),
        ('google_sign_in_ios', 'google_sign_in_tvos'),
        ('device_info_plus', 'device_info_plus_tvos'),
      ]) {
        final Directory dir = fs.directory('/p_$src')..createSync();
        dir.childFile('pubspec.yaml').writeAsStringSync('''
name: $src
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: SomePlugin
''');
        dir.childDirectory('ios').childDirectory('Classes').childFile('SomePlugin.swift')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('import Flutter\n');
        final PluginSource s = SourceAnalyzer(fileSystem: fs).analyze(dir);
        expect(s.outputPackageName, want, reason: '$src → $want');
      }
    });

    testWithoutContext('carries the platform-interface constraint; falls back to any', () {
      Directory mk(String depLine) {
        final Directory dir = fs.directory('/pi')..createSync();
        dir.childFile('pubspec.yaml').writeAsStringSync('''
name: thing_ios
dependencies:
$depLine
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: ThingPlugin
''');
        dir.childDirectory('ios').childDirectory('Classes').childFile('ThingPlugin.swift')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('import Flutter\n');
        return dir;
      }

      final PluginSource pinned =
          SourceAnalyzer(fileSystem: fs).analyze(mk('  thing_platform_interface: ^3.1.0'));
      expect(pinned.platformInterfaceConstraint, '^3.1.0');

      fs.directory('/pi').deleteSync(recursive: true);
      final PluginSource none = SourceAnalyzer(fileSystem: fs)
          .analyze(mk('  thing_platform_interface:\n    git: https://x/y.git'));
      expect(none.platformInterfaceConstraint, isNull,
          reason: 'non-string constraint → null → template uses `any`');
    });

    testWithoutContext('range constraints are quoted in the generated pubspec', () {
      final Directory dir = fs.directory('/r')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: sqflite_darwin
dependencies:
  sqflite_platform_interface: ">=2.4.0 <3.0.0"
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: SqflitePlugin
''');
      dir.childDirectory('ios').childDirectory('Classes').childFile('SqflitePlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('import Flutter\n');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);
      final Directory out = fs.directory('/out/sqflite_tvos');
      Scaffolder(fileSystem: fs, logger: BufferLogger.test(), licenseHolder: 'T')
          .scaffold(source: source, outputDirectory: out);

      final String pubspec = out.childFile('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('sqflite_platform_interface: ">=2.4.0 <3.0.0"'),
          reason: 'range constraint must be quoted or YAML parsing fails');
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
    classes.childFile('URLLauncherPlugin.h').writeAsStringSync(_kRealisticObjcHeader);
    classes.childFile('URLLauncherPlugin.m').writeAsStringSync(_kRealisticObjcImpl);
  } else {
    classes.childFile('URLLauncherPlugin.swift').writeAsStringSync(_kRealisticSwiftSource);
  }
  return dir;
}

/// A trimmed-down Swift implementation that looks enough like a real plugin
/// for "copied verbatim" tests to be meaningful. Keep this in sync with the
/// expected-content checks in tests above.
const String _kRealisticSwiftSource = '''
import Flutter
import UIKit

public class URLLauncherPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "plugins.flutter.io/url_launcher_ios",
      binaryMessenger: registrar.messenger())
    let instance = URLLauncherPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
''';

const String _kRealisticObjcHeader = '''
#import <Flutter/Flutter.h>

@interface URLLauncherPlugin : NSObject <FlutterPlugin>
@end
''';

const String _kRealisticObjcImpl = '''
#import "URLLauncherPlugin.h"

@implementation URLLauncherPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  // Intentionally empty for the test fixture.
}
@end
''';
