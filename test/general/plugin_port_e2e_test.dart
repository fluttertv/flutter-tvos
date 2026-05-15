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

/// A url_launcher_ios-shaped Swift plugin: two clean handlers, two that
/// touch WebKit (`launchInWebView`, `closeWebView`), plus `import WebKit`.
const String _kUrlLauncherSwift = '''
import Flutter
import UIKit
import WebKit

public class URLLauncherPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "plugins.flutter.io/url_launcher_ios",
      binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(URLLauncherPlugin(), channel: channel)
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

Directory _createUrlLauncherIos(FileSystem fs) {
  final Directory dir = fs.directory('/src/url_launcher_ios')..createSync(recursive: true);
  dir.childFile('pubspec.yaml').writeAsStringSync('''
name: url_launcher_ios
description: iOS implementation of url_launcher.
version: 6.3.4

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
  dir
      .childDirectory('ios')
      .childDirectory('Classes')
      .childFile('URLLauncherPlugin.swift')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_kUrlLauncherSwift);
  return dir;
}

void main() {
  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test();
  });

  group('plugin port end-to-end (Swift, Phase 3)', () {
    testWithoutContext('ports url_launcher_ios: strips WebKit, stubs web handlers', () {
      final Directory src = _createUrlLauncherIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/url_launcher_tvos');

      final ScaffoldResult result = Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: out);

      final String swift = out
          .childDirectory('tvos')
          .childDirectory('Classes')
          .childFile('URLLauncherPlugin.swift')
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
      final Directory src = _createUrlLauncherIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/url_launcher_tvos');

      Scaffolder(
        fileSystem: fs,
        logger: BufferLogger.test(),
        licenseHolder: 'Test',
      ).scaffold(source: source, outputDirectory: out);

      final String report = out.childFile('PORTING_REPORT.md').readAsStringSync();

      expect(report, contains('# url_launcher_tvos — porting report'));
      expect(report, contains('Source: `url_launcher_ios` 6.3.4'));
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
      expect(report, contains('tvos/Classes/URLLauncherPlugin.swift'));
      expect(report, contains('Reason: WebKit'));
      expect(
        report,
        contains('Manual review required. Read this report top-to-bottom'),
      );
    });

    testWithoutContext('--no-report suppresses the report but still ports', () {
      final Directory src = _createUrlLauncherIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/url_launcher_tvos');

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
          .childFile('URLLauncherPlugin.swift')
          .readAsStringSync();
      expect(swift, contains('// import WebKit'));
      expect(result.findings, isNotEmpty);
    });

    testWithoutContext('--dry-run previews findings without writing', () {
      final Directory src = _createUrlLauncherIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final Directory out = fs.directory('/out/url_launcher_tvos');

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
      final Directory src = _createUrlLauncherIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final SwiftPortingResult r = SwiftPorter().port(
        _kUrlLauncherSwift,
        fileRelativePath: 'tvos/Classes/URLLauncherPlugin.swift',
      );

      final String report = const ReportEmitter().render(
        source: source,
        results: <SwiftPortingResult>[r],
        today: '2026-01-02',
      );

      expect(
        report,
        contains('Generated by `flutter-tvos plugin port` on 2026-01-02.'),
      );
      expect(report, contains('| Compile errors expected | 0 |'));
      expect(report, contains('## Checklist'));
      expect(report, contains('- [ ] '));
    });

    testWithoutContext('handles a clean port with no findings', () {
      final Directory src = _createUrlLauncherIos(fs);
      final PluginSource source = SourceAnalyzer(fileSystem: fs).analyze(src);
      final SwiftPortingResult clean = SwiftPorter().port(
        'import Flutter\n\npublic class P {}\n',
        fileRelativePath: 'tvos/Classes/P.swift',
      );

      final String report = const ReportEmitter().render(
        source: source,
        results: <SwiftPortingResult>[clean],
        today: '2026-01-02',
      );

      expect(report, contains('| Methods stubbed (iOS-only) | 0 |'));
      expect(report, contains('None. Every `import` in the source compiles on tvOS.'));
      expect(report, contains('No `case "<method>":` handlers were detected'));
    });
  });
}
