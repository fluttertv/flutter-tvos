// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'compatibility_database.dart';
import 'porting_result.dart';

/// Pure-function Objective-C transformer — the `.h`/`.m`/`.mm` analogue of
/// `SwiftPorter`.
///
/// Stateless; safe to call concurrently across files. Like the Swift
/// transformer it is deliberately shallow — regexes plus brace tracking,
/// no real Objective-C parser — so a reviewer can audit a port by eye.
///
/// Two differences from Swift:
///   * Imports are `#import <Framework/...>` or `@import Framework;` rather
///     than `import Framework`. The banned framework list is derived from
///     the same compatibility-database `stripImports` entries (the Swift
///     `import Foo` form is mapped to the ObjC framework name `Foo`).
///   * Method dispatch is an `if ([call.method isEqualToString:@"x"])`
///     chain delimited by braces, not a `switch`/`case`. Handler extents
///     are found by brace tracking from the condition's opening `{`.
class ObjcPorter {
  ObjcPorter({List<ApiPattern> database = compatibilityDatabase})
      : _patterns = <_CompiledPattern>[
          for (final ApiPattern p in database)
            _CompiledPattern(p, RegExp(p.pattern)),
        ],
        _bannedFrameworks = <String, ApiPattern>{
          for (final ApiPattern p in database)
            for (final String imp in p.stripImports)
              if (imp.startsWith('import ')) imp.substring(7).trim(): p,
        };

  final List<_CompiledPattern> _patterns;

  /// framework name (`WebKit`) → the pattern that owns it, so a stripped
  /// `#import <WebKit/WebKit.h>` is attributed to the right report entry.
  final Map<String, ApiPattern> _bannedFrameworks;

  static final RegExp _methodA =
      RegExp(r'@"([^"]+)"\s*\]?\s*isEqualToString:');
  static final RegExp _methodB = RegExp(r'isEqualToString:\s*@"([^"]+)"');
  static final RegExp _objcAngleImport = RegExp(r'^#import\s*<([A-Za-z0-9_]+)/');
  static final RegExp _objcModuleImport = RegExp(r'^@import\s+([A-Za-z0-9_]+)');
  static final RegExp _targetOsIos = RegExp(r'\bTARGET_OS_IOS\b');

  /// Transforms [source]. [fileRelativePath] is recorded into each finding
  /// so the report can point at the issue in the OUTPUT package, e.g.
  /// `tvos/Classes/URLLauncherPlugin.m`.
  PortingResult port(String source, {required String fileRelativePath}) {
    final List<String> lines = source.split('\n');
    final List<String> out = <String>[...lines];
    final List<PortingFinding> findings = <PortingFinding>[];
    final Set<String> strippedImports = <String>{};

    // Pass 1 — map every line inside a recognised handler block to its
    // method name, and remember each block's body extent for stubbing.
    final Map<int, String> methodAt = <int, String>{};
    final Map<String, int> firstBody = <String, int>{};
    final Map<String, int> lastBody = <String, int>{};
    _detectHandlers(lines, methodAt, firstBody, lastBody);

    // Pass 1b — make tvOS follow the iOS code paths. The Objective-C
    // analogue of SwiftPorter's `os(iOS)` widening: plugins gate
    // platform-specific code with `#if TARGET_OS_IOS … #else <macOS> …
    // #endif`. On tvOS `TARGET_OS_IOS` and `TARGET_OS_OSX` are both 0
    // (`TARGET_OS_TV` is 1), so neither branch is taken and the iOS
    // implementation the plugin needs (UIView, CADisplayLink,
    // AVAudioSession, UIViewController — all available on tvOS) is
    // skipped. Widen every `TARGET_OS_IOS` test in a preprocessor
    // conditional to also match tvOS. `TARGET_OS_OSX` is deliberately
    // left untouched (it stays 0 on tvOS, so its `#else`/iOS-shaped
    // branch is taken — exactly what we want). Genuinely iOS-only APIs
    // surfacing through the widened branch are still caught and stubbed
    // by the compatibility-database passes below.
    for (var i = 0; i < lines.length; i++) {
      final String t = lines[i].trimLeft();
      if ((!t.startsWith('#if ') &&
              !t.startsWith('#elif ') &&
              !t.startsWith('#if(') &&
              !t.startsWith('#elif(')) ||
          !_targetOsIos.hasMatch(lines[i]) ||
          lines[i].contains('TARGET_OS_TV')) {
        continue;
      }
      out[i] = lines[i].replaceAll(
        _targetOsIos,
        '(TARGET_OS_IOS || TARGET_OS_TV)',
      );
    }

    // Pass 2 — strip iOS-only framework imports (`#import <F/...>`,
    // `@import F;`). Independent of the usage regex, mirroring SwiftPorter.
    for (var i = 0; i < lines.length; i++) {
      final String trimmed = lines[i].trim();
      if (!trimmed.startsWith('#import') && !trimmed.startsWith('@import')) {
        continue;
      }
      final RegExpMatch? am = _objcAngleImport.firstMatch(trimmed);
      final RegExpMatch? mm = _objcModuleImport.firstMatch(trimmed);
      final String? framework = am?.group(1) ?? mm?.group(1);
      if (framework == null) {
        continue;
      }
      final ApiPattern? owner = _bannedFrameworks[framework];
      if (owner == null) {
        continue;
      }
      out[i] =
          '// ${lines[i]}  // removed by `flutter-tvos plugin port` (tvOS-incompatible)';
      strippedImports.add(trimmed);
      findings.add(PortingFinding(
        fileRelativePath: fileRelativePath,
        line: i + 1,
        column: 1,
        matchedText: trimmed,
        pattern: owner,
        enclosingMethod: null,
        action: FindingAction.importStripped,
      ));
    }

    // Pass 3 — API pattern scan over non-import lines.
    final Set<String> stubbed = <String>{};
    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String lt = line.trimLeft();
      if (lt.startsWith('#import') || lt.startsWith('@import')) {
        continue;
      }
      for (final _CompiledPattern cp in _patterns) {
        final RegExpMatch? m = cp.regex.firstMatch(line);
        if (m == null) {
          continue;
        }
        switch (cp.entry.severity) {
          case Severity.unsupported:
            final String? method = methodAt[i];
            if (method != null) {
              stubbed.add(method);
              findings.add(PortingFinding(
                fileRelativePath: fileRelativePath,
                line: i + 1,
                column: line.indexOf(m.group(0)!) + 1,
                matchedText: m.group(0)!,
                pattern: cp.entry,
                enclosingMethod: method,
                action: FindingAction.stubbedMethod,
              ));
            } else {
              out[i] =
                  '$line  // TODO(porter): ${cp.entry.name} is not available on tvOS.';
              findings.add(PortingFinding(
                fileRelativePath: fileRelativePath,
                line: i + 1,
                column: line.indexOf(m.group(0)!) + 1,
                matchedText: m.group(0)!,
                pattern: cp.entry,
                enclosingMethod: null,
                action: FindingAction.taggedWithTodo,
              ));
            }
          case Severity.partial:
          case Severity.info:
            findings.add(PortingFinding(
              fileRelativePath: fileRelativePath,
              line: i + 1,
              column: line.indexOf(m.group(0)!) + 1,
              matchedText: m.group(0)!,
              pattern: cp.entry,
              enclosingMethod: methodAt[i],
              action: FindingAction.flagged,
            ));
        }
      }
    }

    // Pass 4 — stub the body of every handler that touched an
    // unsupported API.
    for (final String method in stubbed) {
      final int? first = firstBody[method];
      final int? last = lastBody[method];
      if (first == null || last == null || first > last) {
        continue;
      }
      String indent = '  ';
      for (var i = first; i <= last; i++) {
        if (lines[i].trim().isNotEmpty) {
          indent = lines[i].substring(
            0,
            lines[i].length - lines[i].trimLeft().length,
          );
          break;
        }
      }
      for (var i = first; i <= last; i++) {
        if (out[i].isNotEmpty) {
          out[i] = '// ${out[i]}';
        }
      }
      final String stub =
          '${indent}result(FlutterMethodNotImplemented);  // TODO(porter): tvOS-incompatible API stubbed';
      out[first] = '$stub\n${out[first]}';
    }

    String transformed = out.join('\n');
    if (!transformed.endsWith('\n')) {
      transformed = '$transformed\n';
    }

    return PortingResult(
      transformed: transformed,
      findings: findings,
      strippedImports: strippedImports.toList(),
      stubbedCases: stubbed.toList()..sort(),
      detectedMethods: firstBody.keys.toList()..sort(),
    );
  }

  /// Finds `[... isEqualToString:@"method"]` / `[@"method"
  /// isEqualToString:...]` dispatch conditions and brace-tracks each one's
  /// `{ ... }` block. Interior lines are mapped to the method name;
  /// `firstBody`/`lastBody` capture the body extent (excluding the brace
  /// lines) so the stubber can replace it.
  void _detectHandlers(
    List<String> lines,
    Map<int, String> methodAt,
    Map<String, int> firstBody,
    Map<String, int> lastBody,
  ) {
    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (!line.contains('isEqualToString:')) {
        continue;
      }
      final RegExpMatch? a = _methodB.firstMatch(line);
      final RegExpMatch? b = _methodA.firstMatch(line);
      final String? method = a?.group(1) ?? b?.group(1);
      if (method == null) {
        continue;
      }
      // Brace-track from this condition to the `}` that closes its block.
      // Closure must be detected at the character level, not at end of
      // line: in an `if (...) { ... } else if (...) { ... }` chain the
      // closing `}` and the next opening `{` share a line, so a per-line
      // depth check would never see depth return to 0.
      int depth = 0;
      int? openLine;
      int? closeLine;
      for (var scan = i; scan < lines.length && closeLine == null; scan++) {
        final String s = lines[scan];
        final int from = scan == i ? _indexAfterCondition(s) : 0;
        for (var c = from; c < s.length; c++) {
          if (s[c] == '{') {
            depth++;
            openLine ??= scan;
          } else if (s[c] == '}') {
            depth--;
            if (openLine != null && depth == 0) {
              closeLine = scan;
              break;
            }
          }
        }
      }
      if (openLine == null || closeLine == null) {
        continue;
      }
      final int bStart = openLine + 1;
      final int bEnd = closeLine - 1;
      if (bStart <= bEnd) {
        for (var j = bStart; j <= bEnd; j++) {
          methodAt[j] = method;
        }
        firstBody[method] = bStart;
        lastBody[method] = bEnd;
      } else {
        // Empty body: still record the method so the report counts it as
        // detected, with an empty (skipped) extent.
        firstBody[method] = bStart;
        lastBody[method] = bStart - 1;
      }
    }
  }

  /// Where to start counting braces on the condition line: just past the
  /// closing `)` of the `if (...)` so a `{` in the matched string literal
  /// (there is none in practice, but be safe) or the condition itself
  /// isn't miscounted.
  int _indexAfterCondition(String line) {
    final int paren = line.lastIndexOf(')');
    return paren >= 0 ? paren + 1 : 0;
  }
}

class _CompiledPattern {
  _CompiledPattern(this.entry, this.regex);
  final ApiPattern entry;
  final RegExp regex;
}
