// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'compatibility_database.dart';

/// Result of running [SwiftPorter.port] on a single Swift source file.
///
/// `transformed` is what the scaffolder writes to the output package;
/// `findings` are the per-line detections fed into `PORTING_REPORT.md`.
class SwiftPortingResult {
  SwiftPortingResult({
    required this.transformed,
    required this.findings,
    required this.strippedImports,
    required this.stubbedCases,
  });

  /// Transformed Swift content. Always ends with a single trailing newline.
  final String transformed;

  /// Every pattern hit, in source-file order. Empty when nothing matched.
  final List<PortingFinding> findings;

  /// Import lines (verbatim, including leading `import `) that were
  /// commented out during the port. Surfaced in the report's "Imports
  /// removed" section.
  final List<String> strippedImports;

  /// `case "method":` blocks whose body was replaced with
  /// `result(FlutterMethodNotImplemented)` because they referenced an
  /// `unsupported` API. Each entry is the method name (the literal
  /// between the case's quotes).
  final List<String> stubbedCases;
}

/// One detection emitted by the porter. There may be multiple findings per
/// file — e.g. a plugin that uses both `WKWebView` and `UIPasteboard` in
/// different methods produces two findings.
class PortingFinding {
  PortingFinding({
    required this.fileRelativePath,
    required this.line,
    required this.column,
    required this.matchedText,
    required this.pattern,
    required this.enclosingMethod,
    required this.action,
  });

  /// Path of the offending file relative to the output package root, e.g.
  /// `tvos/Classes/URLLauncherPlugin.swift`. Hand-printed into the report.
  final String fileRelativePath;

  /// 1-based line number of the matching line.
  final int line;

  /// 1-based column where the match starts on that line.
  final int column;

  /// The exact substring of source that triggered the match. Useful for
  /// the report so the reader can locate it quickly.
  final String matchedText;

  /// The compatibility-database entry that matched.
  final ApiPattern pattern;

  /// Name of the enclosing `case "<method>":` block, or `null` if the
  /// match wasn't inside a recognised case (e.g. it was at top level or
  /// inside a private helper function).
  final String? enclosingMethod;

  /// What the porter did about this finding.
  final FindingAction action;
}

/// What action the porter took for a given finding.
enum FindingAction {
  /// Method-handler body stubbed with `result(FlutterMethodNotImplemented)`.
  /// Applied only to `unsupported` patterns inside a recognised
  /// `case "<method>":` block.
  stubbedMethod,

  /// Source line marked with a `// TODO(porter):` comment but otherwise
  /// untouched. Applied to `unsupported` patterns NOT inside a recognised
  /// case (e.g. private helpers, top-level code).
  taggedWithTodo,

  /// `partial` patterns: source unchanged, finding recorded for manual
  /// review.
  flagged,

  /// Import line commented out, preserving line numbers.
  importStripped,
}

/// Pure-function Swift transformer.
///
/// Applies [compatibilityDatabase] to a Swift source file. Stateless; safe
/// to call concurrently across files. The implementation is deliberately
/// shallow — no real Swift parser, just regexes and brace tracking — so
/// it can be confidently audited by anyone reviewing a port.
class SwiftPorter {
  SwiftPorter({
    List<ApiPattern> database = compatibilityDatabase,
  }) : _patterns = <_CompiledPattern>[
         for (final ApiPattern p in database)
           _CompiledPattern(p, RegExp(p.pattern)),
       ];

  final List<_CompiledPattern> _patterns;

  /// Transforms [source] (the raw file content) and returns the result.
  ///
  /// [fileRelativePath] is recorded into each [PortingFinding] so the
  /// porting report can locate the issue. It should be the path the file
  /// will live at in the OUTPUT package, e.g.
  /// `tvos/Classes/URLLauncherPlugin.swift`.
  SwiftPortingResult port(String source, {required String fileRelativePath}) {
    final List<String> originalLines = source.split('\n');
    final List<String> outputLines = <String>[...originalLines];
    final List<PortingFinding> findings = <PortingFinding>[];
    final Set<String> strippedImports = <String>{};

    // Pass 1 — detect `case "<method>":` blocks. Build a map line → method
    // name so per-line findings can be tagged with their enclosing method.
    final Map<int, String> caseAt = _detectCaseBlocks(originalLines);

    // Pass 2 — pattern scan. For each line, evaluate every pattern. Apply
    // the appropriate action (strip, stub, tag, flag).
    final Set<int> linesInsideStubbedCase = <int>{};
    final Map<String, int> methodToFirstLine = <String, int>{};
    final Map<String, int> methodToLastLine = <String, int>{};
    _computeCaseExtents(originalLines, methodToFirstLine, methodToLastLine);

    final Set<String> stubbedMethods = <String>{};

    for (var i = 0; i < originalLines.length; i++) {
      final String line = originalLines[i];
      for (final _CompiledPattern cp in _patterns) {
        final RegExpMatch? m = cp.regex.firstMatch(line);
        if (m == null) {
          continue;
        }

        // Strip iOS-only imports first — these dominate over case-stubbing
        // because import lines are always at the top of the file.
        if (line.trimLeft().startsWith('import ')) {
          for (final String banned in cp.entry.stripImports) {
            if (line.trim() == banned) {
              outputLines[i] = '// $line  // removed by `flutter-tvos plugin port` (tvOS-incompatible)';
              strippedImports.add(banned);
              findings.add(PortingFinding(
                fileRelativePath: fileRelativePath,
                line: i + 1,
                column: line.indexOf(m.group(0)!) + 1,
                matchedText: m.group(0)!,
                pattern: cp.entry,
                enclosingMethod: caseAt[i],
                action: FindingAction.importStripped,
              ));
              break;
            }
          }
          // Even if the line was an unrelated `import …`, we don't want
          // to also stub it as method-body — fall through to next pattern.
          continue;
        }

        switch (cp.entry.severity) {
          case Severity.unsupported:
            final String? method = caseAt[i];
            if (method != null) {
              // Inside a recognised case: stub the entire body.
              stubbedMethods.add(method);
              findings.add(PortingFinding(
                fileRelativePath: fileRelativePath,
                line: i + 1,
                column: line.indexOf(m.group(0)!) + 1,
                matchedText: m.group(0)!,
                pattern: cp.entry,
                enclosingMethod: method,
                action: FindingAction.stubbedMethod,
              ));
              for (var j = methodToFirstLine[method]!;
                  j <= methodToLastLine[method]!;
                  j++) {
                linesInsideStubbedCase.add(j);
              }
            } else {
              // Outside any case: tag the line so the user notices.
              outputLines[i] =
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
              enclosingMethod: caseAt[i],
              action: FindingAction.flagged,
            ));
        }
      }
    }

    // Pass 3 — apply the stub replacement for marked cases.
    if (stubbedMethods.isNotEmpty) {
      _stubCaseBodies(
        outputLines,
        stubbedMethods,
        methodToFirstLine,
        methodToLastLine,
      );
    }

    String transformed = outputLines.join('\n');
    if (!transformed.endsWith('\n')) {
      transformed = '$transformed\n';
    }

    return SwiftPortingResult(
      transformed: transformed,
      findings: findings,
      strippedImports: strippedImports.toList(),
      stubbedCases: stubbedMethods.toList()..sort(),
    );
  }

  /// Walks the source and returns a map from line index → method name for
  /// every line inside a `case "<method>":` block.
  ///
  /// Cases are detected by the regex `case\s+"([^"]+)"\s*:`. Their extent
  /// runs from the case label line down to (but not including) the next
  /// `case`/`default` at the same indentation, or the closing brace of
  /// the enclosing `switch`.
  ///
  /// Heuristic, not a parser: works for the conventional `switch
  /// call.method` pattern that 90%+ of Flutter plugins use; falls back
  /// to "no enclosing method" for unusual structures.
  Map<int, String> _detectCaseBlocks(List<String> lines) {
    final Map<int, String> result = <int, String>{};
    String? activeCase;
    int activeIndent = -1;
    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final RegExpMatch? caseMatch =
          RegExp(r'^(\s*)case\s+"([^"]+)"\s*:').firstMatch(line);
      final RegExpMatch? defaultMatch =
          RegExp(r'^(\s*)default\s*:').firstMatch(line);
      if (caseMatch != null) {
        activeCase = caseMatch.group(2);
        activeIndent = caseMatch.group(1)!.length;
        // The case label line itself isn't "inside" the body for our
        // purposes — pattern matches on the label string would be a
        // false positive.
        continue;
      }
      if (defaultMatch != null && defaultMatch.group(1)!.length == activeIndent) {
        activeCase = null;
        continue;
      }
      // A close-brace at a lesser indent ends the switch.
      if (line.trim() == '}' && _leadingSpaces(line) < activeIndent) {
        activeCase = null;
      }
      if (activeCase != null) {
        result[i] = activeCase;
      }
    }
    return result;
  }

  /// Builds `methodToFirstLine` / `methodToLastLine` maps so the stubber
  /// knows the bounds of each `case` body. First/last refer to source
  /// lines INSIDE the body (not the case label line itself, not the next
  /// case label).
  void _computeCaseExtents(
    List<String> lines,
    Map<String, int> firstLine,
    Map<String, int> lastLine,
  ) {
    String? activeCase;
    int activeIndent = -1;
    int? bodyStart;
    for (var i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final RegExpMatch? caseMatch =
          RegExp(r'^(\s*)case\s+"([^"]+)"\s*:').firstMatch(line);
      final RegExpMatch? otherCase = RegExp(r'^(\s*)(case\s|default\s*:)').firstMatch(line);
      if (caseMatch != null) {
        // Close out the prior case if any.
        if (activeCase != null && bodyStart != null) {
          firstLine[activeCase] = bodyStart;
          lastLine[activeCase] = i - 1;
        }
        activeCase = caseMatch.group(2);
        activeIndent = caseMatch.group(1)!.length;
        bodyStart = i + 1;
        continue;
      }
      if (otherCase != null && activeCase != null && bodyStart != null) {
        if (otherCase.group(1)!.length == activeIndent) {
          firstLine[activeCase] = bodyStart;
          lastLine[activeCase] = i - 1;
          activeCase = null;
          bodyStart = null;
        }
      }
      if (activeCase != null && line.trim() == '}' && _leadingSpaces(line) < activeIndent) {
        firstLine[activeCase] = bodyStart!;
        lastLine[activeCase] = i - 1;
        activeCase = null;
        bodyStart = null;
      }
    }
    // Handle the last case if the file ends inside one.
    if (activeCase != null && bodyStart != null) {
      firstLine[activeCase] = bodyStart;
      lastLine[activeCase] = lines.length - 1;
    }
  }

  /// Replaces the body of each method in [stubbedMethods] with a single
  /// `result(FlutterMethodNotImplemented)` line, preserving indentation.
  /// The original body is commented out so the user can see what was
  /// removed.
  void _stubCaseBodies(
    List<String> lines,
    Set<String> stubbedMethods,
    Map<String, int> firstLine,
    Map<String, int> lastLine,
  ) {
    for (final String method in stubbedMethods) {
      final int? first = firstLine[method];
      final int? last = lastLine[method];
      if (first == null || last == null || first > last) {
        continue;
      }
      // Detect the indent from the first non-empty body line.
      String indent = '    ';
      for (var i = first; i <= last; i++) {
        if (lines[i].trim().isNotEmpty) {
          indent = lines[i].substring(
            0,
            lines[i].length - lines[i].trimLeft().length,
          );
          break;
        }
      }
      // Comment out original body.
      for (var i = first; i <= last; i++) {
        if (lines[i].isNotEmpty) {
          lines[i] = '// ${lines[i]}';
        }
      }
      // Insert the stub at the top by prefixing the first line; we don't
      // want to add new lines (which would change line numbers reported
      // by previous findings). Pre-pending preserves layout enough for
      // the user to navigate.
      final String stub =
          '${indent}result(FlutterMethodNotImplemented)  // TODO(porter): tvOS-incompatible API stubbed';
      lines[first] = '$stub\n${lines[first]}';
    }
  }

  static int _leadingSpaces(String s) => s.length - s.trimLeft().length;
}

class _CompiledPattern {
  _CompiledPattern(this.entry, this.regex);
  final ApiPattern entry;
  final RegExp regex;
}
