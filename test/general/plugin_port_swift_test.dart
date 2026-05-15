// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/plugin_porting/swift_porter.dart';

import '../src/common.dart';

/// A url_launcher_ios-shaped Swift source: one clean handler, one `partial`
/// handler (`UIApplication.shared.open`), two `unsupported` handlers behind
/// `WKWebView`, plus the iOS-only `import WebKit`.
const String _kSwiftSource = '''
import Flutter
import UIKit
import WebKit

public class URLLauncherPlugin: NSObject, FlutterPlugin {
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "canLaunch":
      result(true)
    case "launch":
      let url = URL(string: "https://example.com")!
      UIApplication.shared.open(url, options: [:], completionHandler: nil)
      result(true)
    case "openWebView":
      let webView = WKWebView(frame: .zero)
      self.host.view.addSubview(webView)
      result(nil)
    case "closeWebView":
      self.webView?.removeFromSuperview()
      WKWebViewConfiguration().processPool = pool
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
''';

void main() {
  group('SwiftPorter', () {
    testWithoutContext('strips iOS-only imports independent of the API regex', () {
      final SwiftPortingResult r =
          SwiftPorter().port(_kSwiftSource, fileRelativePath: 'tvos/Classes/URLLauncherPlugin.swift');

      // `import WebKit` is commented out even though "import WebKit" does not
      // itself match the WKWebView usage regex — the bug this asserts against.
      expect(
        r.transformed,
        contains('// import WebKit  // removed by `flutter-tvos plugin port`'),
      );
      expect(r.strippedImports, contains('import WebKit'));
      // The supported imports are untouched and stay at the top.
      expect(r.transformed, startsWith('import Flutter\nimport UIKit\n'));

      final PortingFinding importFinding = r.findings.firstWhere(
        (PortingFinding f) => f.action == FindingAction.importStripped,
      );
      expect(importFinding.pattern.name, 'WebKit');
      expect(importFinding.matchedText, 'import WebKit');
      // Dart strips the newline right after `'''`, so source lines are
      // 1=import Flutter, 2=import UIKit, 3=import WebKit.
      expect(importFinding.line, 3);
    });

    testWithoutContext('stubs handlers that reference unsupported APIs', () {
      final SwiftPortingResult r =
          SwiftPorter().port(_kSwiftSource, fileRelativePath: 'tvos/Classes/URLLauncherPlugin.swift');

      expect(r.stubbedCases, <String>['closeWebView', 'openWebView']);
      // The stub line is injected ...
      expect(
        r.transformed,
        contains('result(FlutterMethodNotImplemented)  // TODO(porter): tvOS-incompatible API stubbed'),
      );
      // ... and the original body is retained but commented out (kept so the
      // user can see what was removed, not active code any more).
      expect(r.transformed, contains('WKWebView(frame: .zero)'));
      expect(
        r.transformed,
        isNot(contains('\n      let webView = WKWebView(frame: .zero)')),
        reason: 'the WKWebView line must be commented, not live',
      );

      final Iterable<PortingFinding> stubFindings = r.findings
          .where((PortingFinding f) => f.action == FindingAction.stubbedMethod);
      expect(
        stubFindings.map((PortingFinding f) => f.enclosingMethod).toSet(),
        <String>{'openWebView', 'closeWebView'},
      );
    });

    testWithoutContext('flags partial APIs without modifying the code', () {
      final SwiftPortingResult r =
          SwiftPorter().port(_kSwiftSource, fileRelativePath: 'tvos/Classes/URLLauncherPlugin.swift');

      // `launch` uses UIApplication.shared.open — partial, code stays.
      expect(
        r.transformed,
        contains('UIApplication.shared.open(url, options: [:], completionHandler: nil)'),
      );
      expect(r.stubbedCases, isNot(contains('launch')));

      final PortingFinding flagged = r.findings.firstWhere(
        (PortingFinding f) => f.action == FindingAction.flagged,
      );
      expect(flagged.pattern.name, 'UIApplication.open');
      expect(flagged.enclosingMethod, 'launch');
    });

    testWithoutContext('records the methods it detected for the report', () {
      final SwiftPortingResult r =
          SwiftPorter().port(_kSwiftSource, fileRelativePath: 'x.swift');

      expect(
        r.detectedMethods,
        containsAll(<String>['canLaunch', 'launch', 'openWebView', 'closeWebView']),
      );
    });

    testWithoutContext('clean source ports to identical content (plus newline)', () {
      const String clean = '''
import Flutter

public class FooPlugin: NSObject, FlutterPlugin {
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
''';
      final SwiftPortingResult r = SwiftPorter().port(clean, fileRelativePath: 'x.swift');

      expect(r.transformed, clean);
      expect(r.findings, isEmpty);
      expect(r.stubbedCases, isEmpty);
      expect(r.strippedImports, isEmpty);
    });

    testWithoutContext('always ends with exactly one trailing newline', () {
      final SwiftPortingResult noNewline =
          SwiftPorter().port('let x = 1', fileRelativePath: 'x.swift');
      expect(noNewline.transformed, 'let x = 1\n');

      final SwiftPortingResult oneNewline =
          SwiftPorter().port('let x = 1\n', fileRelativePath: 'x.swift');
      expect(oneNewline.transformed, 'let x = 1\n');
    });
  });
}
