// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Shared result types produced by the native-source porters
/// ([SwiftPorter], [ObjcPorter]). Kept in their own library so neither
/// porter has to import the other just to name the result shape, and so
/// the scaffolder / report emitter depend on one stable contract.
library;

import 'compatibility_database.dart';

/// What action a porter took for a given finding.
enum FindingAction {
  /// Method-handler body stubbed with `result(FlutterMethodNotImplemented)`.
  /// Applied only to `unsupported` patterns inside a recognised method
  /// handler block.
  stubbedMethod,

  /// Source line marked with a `// TODO(porter):` comment but otherwise
  /// untouched. Applied to `unsupported` patterns NOT inside a recognised
  /// handler (e.g. private helpers, top-level code).
  taggedWithTodo,

  /// `partial` / `info` patterns: source unchanged, finding recorded for
  /// manual review.
  flagged,

  /// Import line commented out, preserving line numbers.
  importStripped,
}

/// One detection emitted by a porter. There may be multiple findings per
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

  /// The exact substring of source that triggered the match.
  final String matchedText;

  /// The compatibility-database entry that matched.
  final ApiPattern pattern;

  /// Name of the enclosing handler (the method-channel method name), or
  /// `null` if the match wasn't inside a recognised handler.
  final String? enclosingMethod;

  /// What the porter did about this finding.
  final FindingAction action;
}

/// Result of running a porter on a single native source file.
///
/// `transformed` is what the scaffolder writes to the output package;
/// `findings` are the per-line detections fed into `PORTING_REPORT.md`.
class PortingResult {
  PortingResult({
    required this.transformed,
    required this.findings,
    required this.strippedImports,
    required this.stubbedCases,
    required this.detectedMethods,
  });

  /// Transformed source content. Always ends with a single trailing
  /// newline.
  final String transformed;

  /// Every pattern hit, in source-file order. Empty when nothing matched.
  final List<PortingFinding> findings;

  /// Import lines (verbatim, including the leading directive) that were
  /// commented out during the port. Surfaced in the report's "Imports
  /// removed" section.
  final List<String> strippedImports;

  /// Method-handler blocks whose body was replaced with
  /// `result(FlutterMethodNotImplemented)` because they referenced an
  /// `unsupported` API. Each entry is the method-channel method name.
  final List<String> stubbedCases;

  /// Every method-channel handler the porter recognised in this file,
  /// sorted and de-duplicated. The report subtracts [stubbedCases] and any
  /// flagged methods from this set to compute "ported as-is".
  final List<String> detectedMethods;
}
