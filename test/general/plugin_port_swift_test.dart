// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/plugin_porting/swift_porter.dart';

import '../src/common.dart';

/// A gadget_ios-shaped Swift source: one clean handler, one `partial`
/// handler (`UIApplication.shared.open`), two `unsupported` handlers behind
/// `WKWebView`, plus the iOS-only `import WebKit`.
const String _kSwiftSource = '''
import Flutter
import UIKit
import WebKit

public class GadgetPlugin: NSObject, FlutterPlugin {
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
      final PortingResult r =
          SwiftPorter().port(_kSwiftSource, fileRelativePath: 'tvos/Classes/GadgetPlugin.swift');

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
      final PortingResult r =
          SwiftPorter().port(_kSwiftSource, fileRelativePath: 'tvos/Classes/GadgetPlugin.swift');

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
      final PortingResult r =
          SwiftPorter().port(_kSwiftSource, fileRelativePath: 'tvos/Classes/GadgetPlugin.swift');

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
      final PortingResult r =
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
      final PortingResult r = SwiftPorter().port(clean, fileRelativePath: 'x.swift');

      expect(r.transformed, clean);
      expect(r.findings, isEmpty);
      expect(r.stubbedCases, isEmpty);
      expect(r.strippedImports, isEmpty);
    });

    testWithoutContext('always ends with exactly one trailing newline', () {
      final PortingResult noNewline =
          SwiftPorter().port('let x = 1', fileRelativePath: 'x.swift');
      expect(noNewline.transformed, 'let x = 1\n');

      final PortingResult oneNewline =
          SwiftPorter().port('let x = 1\n', fileRelativePath: 'x.swift');
      expect(oneNewline.transformed, 'let x = 1\n');
    });

    testWithoutContext('widens the Pigeon/Flutter import guard to tvOS', () {
      const String pigeon = '''
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

final class Foo {}
''';
      final PortingResult r =
          SwiftPorter().port(pigeon, fileRelativePath: 'tvos/Classes/messages.g.swift');
      // tvOS now takes the iOS branch (parenthesised to keep precedence).
      expect(r.transformed, contains('#if (os(iOS) || os(tvOS))'));
      expect(r.transformed, contains('  import Flutter'));
      // macOS branch and non-iOS directives are untouched.
      expect(r.transformed, contains('#elseif os(macOS)'));
    });

    testWithoutContext('widens os(iOS) behaviour + messenger branches, keeps precedence', () {
      const String src = '''
func f() {
#if os(iOS)
  let m = registrar.messenger()
#else
  let m = registrar.messenger
#endif
#if os(iOS) && DEBUG
  log()
#endif
#if os(macOS)
  mac()
#endif
}
''';
      final PortingResult r = SwiftPorter().port(src, fileRelativePath: 'x.swift');
      // Plain iOS guard widened so tvOS uses the iOS (messenger()) branch.
      expect(r.transformed, contains('#if (os(iOS) || os(tvOS))\n'));
      // Compound condition keeps `&&` precedence via parentheses.
      expect(r.transformed, contains('#if (os(iOS) || os(tvOS)) && DEBUG'));
      // Non-iOS directives are left exactly as-is.
      expect(r.transformed, contains('#if os(macOS)\n'));
    });

    testWithoutContext(
        'widens the bundled-asset fallback to tvOS but not the FlutterMacOS import',
        () {
      // The shared flutter/packages asset-resolution idiom: the macOS
      // fallback is Foundation-only and is also needed on tvOS, where
      // Bundle.main.path(forResource:ofType:) cannot resolve a nested
      // flutter_assets/ path. The `import FlutterMacOS` guard right
      // above it must stay macOS-only (tvOS uses the iOS Flutter
      // module). Synthetic fixture — no real plugin names.
      const String src = '''
import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

func fileURLForAsset(_ key: String) -> String? {
  var path = Bundle.main.path(forResource: key, ofType: nil)
  #if os(macOS)
    if path == nil {
      path = URL(string: key, relativeTo: Bundle.main.bundleURL)?.path
    }
  #endif
  return path
}
''';
      final PortingResult r =
          SwiftPorter().port(src, fileRelativePath: 'x.swift');

      // The asset-fallback guard is widened to also run on tvOS.
      expect(
        r.transformed,
        contains('#if (os(macOS) || os(tvOS))\n'),
        reason: 'asset fallback must execute on tvOS',
      );
      expect(r.transformed,
          contains('relativeTo: Bundle.main.bundleURL'));
      // The import guard is NOT widened — tvOS must not import
      // FlutterMacOS (it takes the widened os(iOS) Flutter branch).
      expect(r.transformed, contains('#elseif os(macOS)\n'));
      expect(r.transformed, contains('  import FlutterMacOS'));
      expect(
        r.transformed,
        isNot(contains('(os(macOS) || os(tvOS))\n  import FlutterMacOS')),
        reason: 'FlutterMacOS import guard must stay macOS-only',
      );
      // And the iOS branch is widened as before.
      expect(r.transformed, contains('#if (os(iOS) || os(tvOS))\n'));
    });

    testWithoutContext('widens @available/#available iOS clauses to tvOS', () {
      const String src = '''
@available(iOS 15.0, macOS 12.0, *)
extension Foo {
  func bar() {
    if #available(iOS 26.0, *), x.isUltraConstrained {
      use()
    }
    if #available(iOS 17.4, macOS 14.4, *) {
      newApi()
    }
  }
}

@available(iOS 13.0, tvOS 13.0, *)
func alreadyWide() {}

@available(macOS 12.0, *)
func macOnly() {}
''';
      final PortingResult r =
          SwiftPorter().port(src, fileRelativePath: 'x.swift');

      // iOS version mirrored onto tvOS, other platforms + `*` preserved,
      // and a trailing condition outside the parens is untouched.
      expect(r.transformed,
          contains('@available(iOS 15.0, tvOS 15.0, macOS 12.0, *)'));
      expect(
        r.transformed,
        contains('if #available(iOS 26.0, tvOS 26.0, *), x.isUltraConstrained {'),
      );
      expect(r.transformed,
          contains('if #available(iOS 17.4, tvOS 17.4, macOS 14.4, *) {'));
      // Idempotent: a clause that already names tvOS is left as-is.
      expect(r.transformed, contains('@available(iOS 13.0, tvOS 13.0, *)'));
      expect(
        r.transformed,
        isNot(contains('tvOS 13.0, tvOS 13.0')),
        reason: 'must not double-insert tvOS',
      );
      // A clause with no iOS entry is not touched.
      expect(r.transformed, contains('@available(macOS 12.0, *)'));
    });

    testWithoutContext(
        'type-level tvOS-absent APIs produce taggedWithTodo (the fail-fast signal)',
        () {
      // `flutter-tvos plugin port` refuses to emit a package when any
      // finding is `taggedWithTodo` (an unsupported API used at type /
      // top-level scope, not a stubbable handler). Assert the porter
      // raises exactly that for the newly-covered tvOS-absent APIs.
      const String src = '''
import Flutter
import SafariServices

final class Session: NSObject, SFSafariViewControllerDelegate {
  let vc: SFSafariViewController
}

func wifi() {
  let info = CNCopyCurrentNetworkInfo("en0" as CFString)
}
''';
      final PortingResult r =
          SwiftPorter().port(src, fileRelativePath: 'tvos/Classes/Session.swift');

      final Set<String> tagged = <String>{
        for (final PortingFinding f in r.findings)
          if (f.action == FindingAction.taggedWithTodo) f.pattern.name,
      };
      expect(tagged, containsAll(<String>['SafariServices', 'CaptiveNetwork']),
          reason: 'type-level unsupported APIs must be non-stubbable findings '
              'so the command can refuse to emit a broken package');
    });
  });
}
