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
///     the same compatibility-database `stripSwiftImports` entries (the Swift
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
            for (final String imp in p.stripSwiftImports)
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

  /// `@available(iOS 14.0, *)` — group 1 is the platform list.
  static final RegExp _objcAtAvail =
      RegExp(r'@available\s*\(([^)]*)\)');

  /// `iOS <version>` inside an `@available(...)` clause.
  static final RegExp _objcAtAvailIos =
      RegExp(r'(?<![A-Za-z])iOS (\d+(?:\.\d+)*)');

  /// `ios(14)` / `ios(14.0)` inside `API_AVAILABLE(...)` / `NS_AVAILABLE`
  /// macros. Group 1 is the version.
  static final RegExp _objcApiIos =
      RegExp(r'\bios\((\d+(?:\.\d+)?)\)');

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

    // Pass 1c — widen Objective-C availability annotations to also cover
    // tvOS (the ObjC analogue of SwiftPorter's `@available` widening).
    // Two forms:
    //   * `if (@available(iOS 14.0, *))`           → add `tvOS 14.0`
    //   * `API_AVAILABLE(ios(14))` / `NS_…`        → add `tvos(14)`
    // Apple ships the same symbols on tvOS at the same major version, so
    // a clause that names only iOS still makes the compiler reject the
    // symbol on tvOS. Genuinely tvOS-*unavailable* symbols (e.g.
    // `NEHotspotNetwork`, which no version brings to tvOS) are left to
    // the compatibility-database passes / report — widening can't and
    // must not fabricate them.
    for (var i = 0; i < out.length; i++) {
      String line = out[i];
      if (line.contains('@available(') &&
          _objcAtAvailIos.hasMatch(line) &&
          !line.contains('tvOS ')) {
        line = line.replaceAllMapped(_objcAtAvail, (Match m) {
          final String inner = m.group(1)!;
          if (inner.contains('tvOS ')) {
            return m.group(0)!;
          }
          final Match? ios = _objcAtAvailIos.firstMatch(inner);
          if (ios == null) {
            return m.group(0)!;
          }
          return '@available(${inner.replaceFirst(ios.group(0)!, '${ios.group(0)!}, tvOS ${ios.group(1)!}')})';
        });
      }
      if (line.contains('_AVAILABLE(') &&
          _objcApiIos.hasMatch(line) &&
          !line.contains('tvos(')) {
        line = line.replaceFirstMapped(
          _objcApiIos,
          (Match m) => '${m.group(0)!}, tvos(${m.group(1)!})',
        );
      }
      out[i] = line;
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
    // line index → unsupported API name; enclosing construct is wrapped
    // in `#if !TARGET_OS_TV` so the package still compiles on tvOS.
    final Map<int, String> disableAnchors = <int, String>{};
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
              // Type / top-level use: record it; its enclosing construct
              // is wrapped in `#if !TARGET_OS_TV` in Pass 5 so the rest
              // of the package compiles, feature disabled on tvOS.
              disableAnchors.putIfAbsent(i, () => cp.entry.name);
              findings.add(PortingFinding(
                fileRelativePath: fileRelativePath,
                line: i + 1,
                column: line.indexOf(m.group(0)!) + 1,
                matchedText: m.group(0)!,
                pattern: cp.entry,
                enclosingMethod: null,
                action: FindingAction.disabledOnTvos,
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

    // Pass 5 — wrap the enclosing construct of every type-level
    // unsupported use in `#if !TARGET_OS_TV` (graceful partial port).
    final List<String> finalLines = disableAnchors.isEmpty
        ? out
        : _disableTvosRegions(out, lines, disableAnchors);

    String transformed = finalLines.join('\n');
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

  static final RegExp _objcMethodDecl = RegExp(r'^[-+]\s*\(');
  static final RegExp _objcImpl =
      RegExp(r'^@(implementation|interface|protocol)\b');

  /// Wraps the enclosing construct of every type-level unsupported use
  /// in `#if !TARGET_OS_TV` / `#endif` so the package still compiles on
  /// tvOS with that construct disabled. Best-effort and brace-shallow;
  /// every region is recorded in the port summary.
  List<String> _disableTvosRegions(
    List<String> out,
    List<String> orig,
    Map<int, String> anchors,
  ) {
    final List<List<int>> ranges = <List<int>>[];
    final Map<int, Set<String>> namesByStart = <int, Set<String>>{};
    for (final MapEntry<int, String> e in anchors.entries) {
      final List<int> r = _objcMemberRange(orig, e.key);
      ranges.add(r);
      namesByStart.putIfAbsent(r[0], () => <String>{}).add(e.value);
    }
    ranges.sort((List<int> a, List<int> b) => a[0].compareTo(b[0]));
    final List<List<int>> merged = <List<int>>[];
    for (final List<int> r in ranges) {
      if (merged.isNotEmpty && r[0] <= merged.last[1]) {
        if (r[1] > merged.last[1]) {
          merged.last[1] = r[1];
        }
        (namesByStart[merged.last[0]] ??= <String>{})
            .addAll(namesByStart[r[0]] ?? const <String>{});
      } else {
        merged.add(<int>[r[0], r[1]]);
      }
    }
    final List<String> result = <String>[];
    var ri = 0;
    for (var i = 0; i < out.length; i++) {
      if (ri < merged.length && i == merged[ri][0]) {
        final int end = merged[ri][1];
        final String names =
            (namesByStart[merged[ri][0]]?.toList()?..sort())?.join(', ') ?? '';
        result.add('#if !TARGET_OS_TV');
        for (var j = i; j <= end && j < out.length; j++) {
          result.add(out[j]);
        }
        result.add(
            '#endif  // flutter-tvos plugin port: disabled on tvOS ($names) — see PORTING_REPORT.md');
        i = end;
        ri++;
        continue;
      }
      result.add(out[i]);
    }
    return result;
  }

  /// Smallest enclosing construct of [a]: the Objective-C method / C
  /// function it lives in, or the whole `@implementation`/`@interface`
  /// when the token is on that line. Inclusive `[start, end]`.
  List<int> _objcMemberRange(List<String> lines, int a) {
    for (var i = a; i >= 0; i--) {
      final String tl = lines[i].trimLeft();
      if (_objcMethodDecl.hasMatch(tl) || _looksLikeCFunction(tl)) {
        final int end = _objcConstructEnd(lines, i);
        if (end >= a) {
          return <int>[i, end];
        }
        continue;
      }
      if (_objcImpl.hasMatch(tl)) {
        if (i == a) {
          // Token on the @implementation/@interface line itself: wrap to
          // the matching @end.
          for (var j = i + 1; j < lines.length; j++) {
            if (lines[j].trimLeft().startsWith('@end')) {
              return <int>[i, j];
            }
          }
          return <int>[i, lines.length - 1];
        }
        return <int>[a, _objcConstructEnd(lines, a)];
      }
    }
    return <int>[a, _objcConstructEnd(lines, a)];
  }

  bool _looksLikeCFunction(String tl) =>
      RegExp(r'^[A-Za-z_].*\)\s*\{?\s*$').hasMatch(tl) &&
      !tl.startsWith('@') &&
      !tl.startsWith('#') &&
      !tl.startsWith('//') &&
      tl.contains('(');

  /// Last line of the construct at [s]: matching `}` when it opens a
  /// brace, otherwise the `;`-terminated (paren/bracket-aware) statement.
  int _objcConstructEnd(List<String> lines, int s) {
    var depth = 0;
    var sawBrace = false;
    var round = 0;
    var square = 0;
    for (var j = s; j < lines.length; j++) {
      final String l = lines[j];
      for (var c = 0; c < l.length; c++) {
        switch (l[c]) {
          case '{':
            depth++;
            sawBrace = true;
          case '}':
            depth--;
            if (sawBrace && depth <= 0) {
              return j;
            }
          case '(':
            round++;
          case ')':
            round--;
          case '[':
            square++;
          case ']':
            square--;
        }
      }
      if (!sawBrace) {
        final String t = l.trimRight();
        if (t.endsWith(';') && round <= 0 && square <= 0) {
          return j;
        }
      }
    }
    return lines.length - 1;
  }
}

class _CompiledPattern {
  _CompiledPattern(this.entry, this.regex);
  final ApiPattern entry;
  final RegExp regex;
}
