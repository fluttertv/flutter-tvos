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
      final Directory dir = _createIosPlugin(fs, name: 'gadget_ios');

      final analyzer = SourceAnalyzer(fileSystem: fs);
      final PluginSource source = analyzer.analyze(dir);

      expect(source.packageName, 'gadget_ios');
      expect(source.basePackageName, 'gadget');
      expect(source.outputPackageName, 'gadget_tvos');
      expect(source.sourcePlatform, 'ios');
      expect(source.pluginClass, 'GadgetPlugin');
      expect(source.dartPluginClass, 'GadgetIOS');
      expect(source.platformInterfacePackage, 'gadget_platform_interface');
      expect(source.sourceLanguage, SourceLanguage.swift);
    });

    testWithoutContext('strips _foundation suffix on shared iOS/macOS packages', () {
      final Directory dir = _createIosPlugin(fs, name: 'prefsbox_foundation');

      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);

      expect(source.basePackageName, 'prefsbox');
      expect(source.outputPackageName, 'prefsbox_tvos');
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
name: widgetbox_macos
flutter:
  plugin:
    platforms:
      macos:
        pluginClass: WidgetboxPlugin
        dartPluginClass: WidgetboxMacOS
''');
      dir.childDirectory('macos').childDirectory('Classes').createSync(recursive: true);
      dir.childDirectory('macos').childDirectory('Classes').childFile('WidgetboxPlugin.swift').writeAsStringSync('// stub');

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
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/gadget_tvos');

      final scaffolder = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test Holder',
      );
      final ScaffoldResult result = scaffolder.scaffold(source: source, outputDirectory: outputDir);

      expect(result.dryRun, isFalse);

      // Pubspec
      final String pubspec = outputDir.childFile('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: gadget_tvos'));
      expect(pubspec, contains('pluginClass: GadgetPlugin'));
      expect(pubspec, contains('dartPluginClass: GadgetIOS'));
      // The source's own constraint is carried over verbatim (not a
      // hardcoded ^1.0.0, which would break `pub get` for real plugins).
      expect(pubspec, contains('gadget_platform_interface: ^2.4.0'));

      // Podspec
      final String podspec = outputDir.childDirectory('tvos').childFile('gadget_tvos.podspec').readAsStringSync();
      expect(podspec, contains("s.name             = 'gadget_tvos'"));
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
          .childFile('GadgetPlugin.swift')
          .readAsStringSync();
      expect(
        swift,
        equals(_kRealisticSwiftSource),
        reason: 'Swift source should be copied verbatim from <ios>/Classes/',
      );

      // Dart entry uses the dartPluginClass and the platform interface package.
      final String dartEntry = outputDir
          .childDirectory('lib')
          .childFile('gadget_tvos.dart')
          .readAsStringSync();
      expect(dartEntry, contains("import 'package:gadget_platform_interface/gadget_platform_interface.dart'"));
      expect(dartEntry, contains('base class GadgetIOS extends GadgetPlatform'));
      expect(dartEntry, contains('static void registerWith()'));

      // Test stub.
      expect(
        outputDir.childDirectory('test').childFile('gadget_tvos_test.dart').existsSync(),
        isTrue,
      );

      // Standard package files.
      expect(outputDir.childFile('README.md').existsSync(), isTrue);
      expect(outputDir.childFile('CHANGELOG.md').existsSync(), isTrue);
      expect(outputDir.childFile('analysis_options.yaml').existsSync(), isTrue);
      expect(outputDir.childFile('.gitignore').existsSync(), isTrue);
    });

    testWithoutContext('--dry-run does not write any files', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/gadget_tvos');

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
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/gadget_tvos')..createSync(recursive: true);
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
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/gadget_tvos')..createSync(recursive: true);
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
      expect(tvosClasses.childFile('GadgetPlugin.h').readAsStringSync(), _kRealisticObjcHeader);
      expect(tvosClasses.childFile('GadgetPlugin.m').readAsStringSync(), _kRealisticObjcImpl);

      // No Swift stub written when ObjC sources are present.
      expect(tvosClasses.childFile('GadgetPlugin.swift').existsSync(), isFalse);
    });

    testWithoutContext('preserves subdirectory structure under Classes/', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      // Add a nested helper file.
      sourceDir
          .childDirectory('ios')
          .childDirectory('Classes')
          .childDirectory('Helpers')
          .childFile('UrlValidator.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// helper');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/gadget_tvos');

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
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
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
      final Directory outputDir = fs.directory('/out/gadget_tvos');

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
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      sourceDir.childFile('LICENSE').writeAsStringSync('BSD-3 license body');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory outputDir = fs.directory('/out/gadget_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: outputDir);

      expect(outputDir.childFile('LICENSE').readAsStringSync(), 'BSD-3 license body');
    });

    testWithoutContext('copies the source Dart lib/, renaming entry + rewriting self-imports', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      sourceDir.childDirectory('lib').childFile('gadget_ios.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          "import 'package:gadget_platform_interface/gadget_platform_interface.dart';\n"
          "import 'package:gadget_ios/src/messages.g.dart';\n"
          'class GadgetIOS extends GadgetPlatform {}\n',
        );
      sourceDir
          .childDirectory('lib')
          .childDirectory('src')
          .childFile('messages.g.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// pigeon generated\n');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory out = fs.directory('/out/gadget_tvos');

      Scaffolder(fileSystem: fs, logger: BufferLogger.test(), licenseHolder: 'T')
          .scaffold(source: source, outputDirectory: out);

      // Entry renamed to <out>.dart; real upstream class preserved.
      final String entry =
          out.childDirectory('lib').childFile('gadget_tvos.dart').readAsStringSync();
      expect(entry, contains('class GadgetIOS extends GadgetPlatform'));
      // Self-import rewritten to the output package; interface import kept.
      expect(entry, contains("package:gadget_tvos/src/messages.g.dart"));
      expect(entry, isNot(contains('package:gadget_ios/')));
      expect(entry,
          contains("package:gadget_platform_interface/gadget_platform_interface.dart"));
      // Sub-tree copied verbatim, structure preserved.
      expect(
        out.childDirectory('lib').childDirectory('src').childFile('messages.g.dart').readAsStringSync(),
        '// pigeon generated\n',
      );
      // No hand-written guessed stub left behind.
      expect(entry, isNot(contains('TODO(porter): override the platform interface')));
    });

    testWithoutContext('falls back to the Dart stub when the source has no lib/', () {
      final Directory sourceDir = _createIosPlugin(fs, name: 'gadget_ios');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(sourceDir);
      final Directory out = fs.directory('/out/gadget_tvos');

      Scaffolder(fileSystem: fs, logger: BufferLogger.test(), licenseHolder: 'T')
          .scaffold(source: source, outputDirectory: out);

      final String entry =
          out.childDirectory('lib').childFile('gadget_tvos.dart').readAsStringSync();
      expect(entry, contains('base class GadgetIOS extends GadgetPlatform'));
      expect(entry, contains('static void registerWith()'));
    });
  });

  group('SourceAnalyzer modern layouts', () {
    testWithoutContext('resolves a Swift Package Manager layout', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: gadget_ios
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: GadgetPlugin
        dartPluginClass: GadgetIOS
''');
      dir
          .childDirectory('ios')
          .childDirectory('gadget_ios')
          .childDirectory('Sources')
          .childDirectory('gadget_ios')
          .childFile('GadgetPlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('import Flutter\n');
      dir
          .childDirectory('ios')
          .childDirectory('gadget_ios')
          .childFile('Package.swift')
          .writeAsStringSync('// swift-tools-version:5.9\n');

      final PluginSource s = SourceAnalyzer(fileSystem: fs).analyze(dir);
      expect(s.classesDirectory.path, contains('ios/gadget_ios/Sources/gadget_ios'));
      expect(s.pluginClass, 'GadgetPlugin');
      expect(s.isMultiTargetSpm, isFalse,
          reason: 'a lone SwiftPM target is the ordinary single-directory layout');
    });

    testWithoutContext('resolves sharedDarwinSource under darwin/', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: prefsbox_foundation
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: PrefsboxPlugin
        dartPluginClass: PrefsboxFoundation
        sharedDarwinSource: true
      macos:
        pluginClass: PrefsboxPlugin
        dartPluginClass: PrefsboxFoundation
        sharedDarwinSource: true
''');
      dir
          .childDirectory('darwin')
          .childDirectory('prefsbox_foundation')
          .childDirectory('Sources')
          .childDirectory('prefsbox_foundation')
          .childFile('PrefsboxPlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('import Flutter\n');

      final PluginSource s = SourceAnalyzer(fileSystem: fs).analyze(dir);
      expect(s.classesDirectory.path,
          contains('darwin/prefsbox_foundation/Sources'));
      expect(s.basePackageName, 'prefsbox');
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

    testWithoutContext('genuinely pure-Dart plugin → advisory no _tvos package needed', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: some_thing
dependencies:
  some_thing_platform_interface: ^1.0.0
flutter:
  plugin:
    platforms:
      ios:
        dartPluginClass: SomeThingIos
''');
      expect(
        () => SourceAnalyzer(fileSystem: fs).analyze(dir),
        throwsA(isA<PluginSourceError>()
            .having((PluginSourceError e) => e.advisory, 'advisory', isTrue)
            .having((PluginSourceError e) => e.message, 'm',
                contains('no `some_thing_tvos` package is needed'))),
      );
    });

    testWithoutContext('SPM Package.swift is excluded from the generated package', () {
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: gadget_ios
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: GadgetPlugin
''');
      final Directory spm = dir
          .childDirectory('ios')
          .childDirectory('gadget_ios')
          .childDirectory('Sources')
          .childDirectory('gadget_ios')
        ..createSync(recursive: true);
      spm.childFile('GadgetPlugin.swift').writeAsStringSync('import Flutter\n');
      // A stray Package.swift inside the resolved sources dir must be
      // filtered out by the scaffolder, not copied into Classes/.
      spm.childFile('Package.swift').writeAsStringSync('// swift-tools-version:5.9\n');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);
      final Directory out = fs.directory('/out/gadget_tvos');

      Scaffolder(fileSystem: fs, logger: BufferLogger.test(), licenseHolder: 'T')
          .scaffold(source: source, outputDirectory: out);

      final Directory tvosClasses = out.childDirectory('tvos').childDirectory('Classes');
      expect(tvosClasses.childFile('GadgetPlugin.swift').existsSync(), isTrue);
      expect(tvosClasses.childFile('Package.swift').existsSync(), isFalse,
          reason: 'SPM manifest must not be copied into Classes/');
    });

    testWithoutContext('strips federated Apple impl suffixes for the output name', () {
      for (final (String src, String want) in <(String, String)>[
        ('vidbox_avfoundation', 'vidbox_tvos'),
        ('iapbox_storekit', 'iapbox_tvos'),
        ('geobox_apple', 'geobox_tvos'),
        ('audbox_darwin', 'audbox_tvos'),
        ('signbox_ios', 'signbox_tvos'),
        ('devbox', 'devbox_tvos'),
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
name: dbbox_darwin
dependencies:
  dbbox_platform_interface: ">=2.4.0 <3.0.0"
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: DbboxPlugin
''');
      dir.childDirectory('ios').childDirectory('Classes').childFile('DbboxPlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('import Flutter\n');
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(dir);
      final Directory out = fs.directory('/out/dbbox_tvos');
      Scaffolder(fileSystem: fs, logger: BufferLogger.test(), licenseHolder: 'T')
          .scaffold(source: source, outputDirectory: out);

      final String pubspec = out.childFile('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('dbbox_platform_interface: ">=2.4.0 <3.0.0"'),
          reason: 'range constraint must be quoted or YAML parsing fails');
    });

    testWithoutContext('FFI source → generic buildable native federated skeleton', () {
      // Synthetic fixture — the CLI is plugin-agnostic, so tests are too.
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: acme_foundation
version: 1.2.3
dependencies:
  ffi: ^2.1.4
  objective_c: ^9.2.1
  acme_platform_interface: ^2.1.0
flutter:
  plugin:
    platforms:
      ios:
        dartPluginClass: AcmeFoundation
''');
      final PluginSource s = SourceAnalyzer(fileSystem: fs).analyze(dir);
      expect(s.ffiNativeAssets, isTrue);
      expect(s.outputPackageName, 'acme_tvos');
      expect(s.pluginClass, 'AcmePlugin');
      expect(s.dartPluginClass, 'AcmeTvos');

      final Directory out = fs.directory('/out/acme_tvos');
      final ScaffoldResult r = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'T',
      ).scaffold(source: s, outputDirectory: out);
      expect(r.findings, isEmpty);

      // Dart: federated subclass that compiles (inherits the interface's
      // throwing defaults). No hand-written implementation in the CLI.
      final String dart = out
          .childDirectory('lib')
          .childFile('acme_tvos.dart')
          .readAsStringSync();
      expect(dart, contains('AcmeTvos extends AcmePlatform'));
      expect(dart, contains('AcmePlatform.instance = AcmeTvos()'));
      expect(dart, isNot(contains('invokeMethod')));

      // Swift: stub only — returns FlutterMethodNotImplemented.
      final String swift = out
          .childDirectory('tvos')
          .childDirectory('Classes')
          .childFile('AcmePlugin.swift')
          .readAsStringSync();
      expect(swift, contains('result(FlutterMethodNotImplemented)'));
      expect(swift, contains('TODO(porter)'));
      expect(swift, isNot(contains('NSSearchPathForDirectoriesInDomains')));

      final String pubspec = out.childFile('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: acme_tvos'));
      expect(pubspec, contains('acme_platform_interface: ^2.1.0'));
      expect(pubspec, contains('pluginClass: AcmePlugin'));
      expect(pubspec, contains('dartPluginClass: AcmeTvos'));

      final String report =
          out.childFile('PORTING_REPORT.md').readAsStringSync();
      expect(report, contains('native federated'));
      expect(report, contains('BUILDABLE SKELETON'));
      expect(report, contains('plugins/packages/acme_tvos'));

      // A runnable tvOS-only example ships with the skeleton.
      final String exPubspec = out
          .childDirectory('example')
          .childFile('pubspec.yaml')
          .readAsStringSync();
      expect(exPubspec, contains('name: acme_example'));
      expect(exPubspec, contains('acme: any'));
      expect(exPubspec, contains('acme_tvos:\n    path: ../'));
      expect(
        out.childDirectory('example').childDirectory('lib').childFile('main.dart').existsSync(),
        isTrue,
      );
    });

    testWithoutContext(
        'modular multi-target SwiftPM: copies every sibling target, drops macOS, '
        'preserves structure, collapses into one module', () {
      // Synthetic fixture mirroring the modern flutter/packages modular
      // SwiftPM layout (a Swift API target + Objective-C `_objc` core +
      // platform `_ios`/`_macos` targets). Plugin-agnostic — no real
      // plugin names anywhere.
      final Directory dir = fs.directory('/p')..createSync();
      dir.childFile('pubspec.yaml').writeAsStringSync('''
name: gizmo_avfoundation
version: 4.5.6
dependencies:
  gizmo_platform_interface: ^2.0.0
flutter:
  plugin:
    implements: gizmo
    platforms:
      ios:
        pluginClass: GizmoPlugin
        dartPluginClass: AvfoundationGizmo
        sharedDarwinSource: true
      macos:
        pluginClass: GizmoPlugin
        dartPluginClass: AvfoundationGizmo
        sharedDarwinSource: true
''');
      final Directory sources = dir
          .childDirectory('darwin')
          .childDirectory('gizmo_avfoundation')
          .childDirectory('Sources');
      dir
          .childDirectory('darwin')
          .childDirectory('gizmo_avfoundation')
          .childFile('Package.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('// swift-tools-version: 5.9\n');

      // Swift API target: branches on os(iOS)/os(macOS) and pulls the
      // ObjC core in via a `canImport` module guard.
      sources
          .childDirectory('gizmo_avfoundation')
          .childFile('GizmoPlugin.swift')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

#if canImport(gizmo_avfoundation_objc)
  import gizmo_avfoundation_objc
#endif

final class GizmoPlugin: NSObject {
  let core = GizmoCore()
}
''');
      // ObjC core target with modular `include/` headers and a
      // TARGET_OS_IOS/else platform branch.
      final Directory objc = sources.childDirectory('gizmo_avfoundation_objc');
      objc.childFile('GizmoCore.m')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
#import "./include/gizmo_avfoundation_objc/GizmoCore.h"
@import Foundation;

@implementation GizmoCore
- (void)tick {
#if TARGET_OS_IOS
  [self iosPath];
#else
  [self macPath];
#endif
}
@end
''');
      objc
          .childDirectory('include')
          .childDirectory('gizmo_avfoundation_objc')
          .childFile('GizmoCore.h')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('@import Foundation;\n@interface GizmoCore : NSObject\n@end\n');
      // iOS platform target: reaches the ObjC core via a cross-target
      // relative path that only resolves if structure is preserved.
      sources
          .childDirectory('gizmo_avfoundation_ios')
          .childFile('GizmoView.m')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
            '#import "../gizmo_avfoundation_objc/include/gizmo_avfoundation_objc/GizmoCore.h"\n'
            '@import UIKit;\n');
      // macOS platform target: AppKit — must be dropped for tvOS.
      sources
          .childDirectory('gizmo_avfoundation_macos')
          .childFile('GizmoViewMac.m')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('@import Cocoa;\n');

      final PluginSource s = SourceAnalyzer(fileSystem: fs).analyze(dir);
      expect(s.isMultiTargetSpm, isTrue);
      expect(s.outputPackageName, 'gizmo_tvos');
      expect(s.pluginClass, 'GizmoPlugin');

      final Directory out = fs.directory('/out/gizmo_tvos');
      Scaffolder(fileSystem: fs, logger: BufferLogger.test(), licenseHolder: 'T')
          .scaffold(source: s, outputDirectory: out);

      final Directory classes =
          out.childDirectory('tvos').childDirectory('Classes');

      // Every kept target copied, internal structure preserved.
      final String swift = classes
          .childDirectory('gizmo_avfoundation')
          .childFile('GizmoPlugin.swift')
          .readAsStringSync();
      final String core = classes
          .childDirectory('gizmo_avfoundation_objc')
          .childFile('GizmoCore.m')
          .readAsStringSync();
      expect(
        classes
            .childDirectory('gizmo_avfoundation_objc')
            .childDirectory('include')
            .childDirectory('gizmo_avfoundation_objc')
            .childFile('GizmoCore.h')
            .existsSync(),
        isTrue,
        reason: 'modular include/ headers must keep their path',
      );
      final String view = classes
          .childDirectory('gizmo_avfoundation_ios')
          .childFile('GizmoView.m')
          .readAsStringSync();

      // macOS-only target dropped — tvOS uses the iOS sibling.
      expect(classes.childDirectory('gizmo_avfoundation_macos').existsSync(),
          isFalse);
      expect(s.spmSourcesRoot, isNotNull);

      // Swift: os(iOS) widened to tvOS; the canImport guard is kept (it
      // self-disables under one CocoaPods module, exposing the ObjC
      // symbols via the shared umbrella instead).
      expect(swift, contains('#if (os(iOS) || os(tvOS))'));
      expect(swift, contains('#if canImport(gizmo_avfoundation_objc)'));

      // ObjC: TARGET_OS_IOS widened so tvOS takes the iOS branch; the
      // cross-target relative import is untouched (resolves because the
      // structure is preserved).
      expect(core, contains('#if (TARGET_OS_IOS || TARGET_OS_TV)'));
      expect(core, contains('#import "./include/gizmo_avfoundation_objc/GizmoCore.h"'));
      expect(
        view,
        contains(
            '#import "../gizmo_avfoundation_objc/include/gizmo_avfoundation_objc/GizmoCore.h"'),
      );

      // Podspec collapses the targets into one module the way the
      // upstream CocoaPods podspec does.
      final String podspec = out
          .childDirectory('tvos')
          .childFile('gizmo_tvos.podspec')
          .readAsStringSync();
      expect(podspec, contains("s.source_files     = 'Classes/**/*.{h,m,mm,swift}'"));
      expect(
          podspec, contains("s.public_header_files = 'Classes/**/include/**/*.h'"));
      expect(podspec, contains("'DEFINES_MODULE' => 'YES'"));
    });
  });
}

/// Builds a minimal but valid iOS plugin in [fs] under `/p` and returns it.
///
/// Keeps the fixture inline so test files don't need on-disk artefacts. The
/// pubspec mirrors a real federated plugin (gadget_ios style).
Directory _createIosPlugin(FileSystem fs, {required String name, bool objc = false}) {
  final Directory dir = fs.directory('/p')..createSync();
  dir.childFile('pubspec.yaml').writeAsStringSync('''
name: $name
description: iOS implementation of gadget.
version: 6.3.4
homepage: https://github.com/flutter/packages/

environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.13.0"

dependencies:
  flutter:
    sdk: flutter
  gadget_platform_interface: ^2.4.0

flutter:
  plugin:
    implements: gadget
    platforms:
      ios:
        pluginClass: GadgetPlugin
        dartPluginClass: GadgetIOS
''');
  final Directory classes = dir.childDirectory('ios').childDirectory('Classes')
    ..createSync(recursive: true);
  if (objc) {
    classes.childFile('GadgetPlugin.h').writeAsStringSync(_kRealisticObjcHeader);
    classes.childFile('GadgetPlugin.m').writeAsStringSync(_kRealisticObjcImpl);
  } else {
    classes.childFile('GadgetPlugin.swift').writeAsStringSync(_kRealisticSwiftSource);
  }
  return dir;
}

/// A trimmed-down Swift implementation that looks enough like a real plugin
/// for "copied verbatim" tests to be meaningful. Keep this in sync with the
/// expected-content checks in tests above.
const String _kRealisticSwiftSource = '''
import Flutter
import UIKit

public class GadgetPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "plugins.flutter.io/gadget_ios",
      binaryMessenger: registrar.messenger())
    let instance = GadgetPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
''';

const String _kRealisticObjcHeader = '''
#import <Flutter/Flutter.h>

@interface GadgetPlugin : NSObject <FlutterPlugin>
@end
''';

const String _kRealisticObjcImpl = '''
#import "GadgetPlugin.h"

@implementation GadgetPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  // Intentionally empty for the test fixture.
}
@end
''';
