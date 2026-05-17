// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/memory.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tvos/plugin_porting/report_emitter.dart';
import 'package:flutter_tvos/plugin_porting/scaffolder.dart';
import 'package:flutter_tvos/plugin_porting/source_analyzer.dart';
import 'package:flutter_tvos/plugin_porting/swift_porter.dart';

import '../src/common.dart';

/// A gadget_ios-shaped Swift plugin: two clean handlers, two that
/// touch WebKit (`launchInWebView`, `closeWebView`), plus `import WebKit`.
const String _kGadgetSwift = '''
import Flutter
import UIKit
import WebKit

public class GadgetPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "plugins.flutter.io/gadget_ios",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(GadgetPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canLaunch":
      result(true)
    case "launch":
      self.launchURL(call.arguments, result: result)
    case "launchInWebView":
      let webView = WKWebView(frame: .zero)
      self.present(webView)
      result(true)
    case "closeWebView":
      if let webView = self.currentView as? WKWebView {
        webView.removeFromSuperview()
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
''';

Directory _createGadgetIos(FileSystem fs) {
  final Directory dir = fs.directory('/src/gadget_ios')..createSync(recursive: true);
  dir.childFile('pubspec.yaml').writeAsStringSync('''
name: gadget_ios
description: iOS implementation of gadget.
version: 6.3.4

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
  dir
      .childDirectory('ios')
      .childDirectory('Classes')
      .childFile('GadgetPlugin.swift')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_kGadgetSwift);
  return dir;
}

void main() {
  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test();
  });

  group('plugin port end-to-end (Swift, Phase 3)', () {
    testWithoutContext('ports gadget_ios: strips WebKit, stubs web handlers', () {
      final Directory src = _createGadgetIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/gadget_tvos');

      final ScaffoldResult result = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: out);

      final String swift = out
          .childDirectory('tvos')
          .childDirectory('Classes')
          .childFile('GadgetPlugin.swift')
          .readAsStringSync();

      // iOS-only import commented out.
      expect(swift, contains('// import WebKit  // removed by `flutter-tvos plugin port`'));
      // Supported imports preserved.
      expect(swift, startsWith('import Flutter\nimport UIKit\n'));
      // Both web handlers stubbed.
      expect(
        'result(FlutterMethodNotImplemented)  // TODO(porter): tvOS-incompatible API stubbed'
            .allMatches(swift)
            .length,
        2,
      );
      // The clean handlers are untouched.
      expect(swift, contains('case "canLaunch":'));
      expect(swift, contains('self.launchURL(call.arguments, result: result)'));

      expect(result.reportPath, isNotNull);
      expect(result.findings, isNotEmpty);
    });

    testWithoutContext('writes a PORTING_REPORT.md that names every stub', () {
      final Directory src = _createGadgetIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/gadget_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: out);

      final String report = out.childFile('PORTING_REPORT.md').readAsStringSync();

      expect(report, contains('# gadget_tvos — porting report'));
      expect(report, contains('Source: `gadget_ios` 6.3.4'));
      expect(report, contains('Base platform: ios (Swift)'));
      expect(report, contains('| Methods ported as-is | 2 |'));
      expect(report, contains('| Methods stubbed (iOS-only) | 2 |'));
      expect(report, contains('| Manual review items | 0 |'));
      expect(report, contains('### `closeWebView` ✗ stubbed'));
      expect(report, contains('### `launchInWebView` ✗ stubbed'));
      expect(report, contains('### `canLaunch` ✓ ported'));
      expect(report, contains('### `launch` ✓ ported'));
      expect(report, contains('## Imports removed'));
      expect(report, contains('`import WebKit`'));
      expect(report, contains('tvos/Classes/GadgetPlugin.swift'));
      expect(report, contains('Reason: WebKit'));
      expect(
        report,
        contains('Manual review required. Read this report top-to-bottom'),
      );
    });

    testWithoutContext('--no-report suppresses the report but still ports', () {
      final Directory src = _createGadgetIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/gadget_tvos');

      final ScaffoldResult result = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: out, emitReport: false);

      expect(out.childFile('PORTING_REPORT.md').existsSync(), isFalse);
      expect(result.reportPath, isNull);
      // Code transform still ran.
      final String swift = out
          .childDirectory('tvos')
          .childDirectory('Classes')
          .childFile('GadgetPlugin.swift')
          .readAsStringSync();
      expect(swift, contains('// import WebKit'));
      expect(result.findings, isNotEmpty);
    });

    testWithoutContext('--dry-run previews findings without writing', () {
      final Directory src = _createGadgetIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/gadget_tvos');

      final ScaffoldResult result = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: out, dryRun: true);

      expect(out.existsSync(), isFalse);
      // Findings are still computed so the command can preview the report.
      expect(
        result.findings.where((f) => f.action == FindingAction.stubbedMethod),
        isNotEmpty,
      );
      expect(
        result.writtenPaths.any((String p) => p.endsWith('PORTING_REPORT.md')),
        isTrue,
      );
    });
  });

  group('ReportEmitter', () {
    testWithoutContext('emits a deterministic, well-formed report', () {
      final Directory src = _createGadgetIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final PortingResult r = SwiftPorter().port(
        _kGadgetSwift,
        fileRelativePath: 'tvos/Classes/GadgetPlugin.swift',
      );

      final String report = const ReportEmitter().render(
        source: source,
        results: <PortingResult>[r],
        today: '2026-01-02',
      );

      expect(
        report,
        contains('Generated by `flutter-tvos plugin port` on 2026-01-02.'),
      );
      // All WebKit use is inside recognised handlers (stubbable), nothing
      // at type level → expected to compile.
      expect(report, contains('| tvOS build outlook | ✅ expected to compile |'));
      expect(report, contains('✅ No tvOS-incompatible APIs detected at type level'));
      expect(report, contains('## Checklist'));
      expect(report, contains('- [ ] '));
    });

    testWithoutContext('flags a NOT-buildable plugin when an unsupported API is type-level', () {
      final Directory src = _createGadgetIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      // WKWebView used at type/top-level scope (a stored property), not
      // inside a method-channel case — the porter can't stub this.
      const String typeLevel = '''
import Flutter
import WebKit

public class BrowserPlugin: NSObject, FlutterPlugin {
  let web = WKWebView(frame: .zero)
}
''';
      final PortingResult r = SwiftPorter()
          .port(typeLevel, fileRelativePath: 'tvos/Classes/BrowserPlugin.swift');
      final String report = const ReportEmitter()
          .render(source: source, results: <PortingResult>[r], today: '2026-01-02');

      expect(report, contains('⚠️ This plugin is not buildable on tvOS as-is'));
      expect(report,
          contains('| tvOS build outlook | ❌ will NOT compile (manual work required) |'));
      expect(report, contains('WebKit'));
    });

    testWithoutContext('handles a clean port with no findings', () {
      final Directory src = _createGadgetIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final PortingResult clean = SwiftPorter().port(
        'import Flutter\n\npublic class P {}\n',
        fileRelativePath: 'tvos/Classes/P.swift',
      );

      final String report = const ReportEmitter().render(
        source: source,
        results: <PortingResult>[clean],
        today: '2026-01-02',
      );

      expect(report, contains('| Methods stubbed (iOS-only) | 0 |'));
      expect(report, contains('None. Every `import` in the source compiles on tvOS.'));
      expect(report, contains('No `case "<method>":` handlers were detected'));
    });
  });
}
