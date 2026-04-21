// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io' show Platform;

/// Cheap, synchronous tvOS detection that mirrors the style of
/// `Platform.isIOS`, `Platform.isAndroid`, etc.
///
/// On a flutter-tvos build:
/// - `Platform.operatingSystem == "tvos"`
/// - `Platform.isIOS == true` (tvOS is an iOS-family OS)
/// - `Platform.isTvOS == true` (new Dart VM getter)
///
/// Since `Platform.isIOS` is `true` on both real iOS and tvOS, app code that
/// wants to branch "iPhone/iPad only" vs "Apple TV only" needs a way to
/// disambiguate. This class provides the idiomatic helpers. It is a zero-FFI
/// string/flag check suitable for hot paths.
///
/// Unlike [TvOSInfo.isTvOS] (which goes through dart:ffi into native
/// Objective-C to read `TARGET_OS_TV` compile flags at runtime), these helpers
/// are pure Dart and trivially inlinable.
///
/// Two usage forms:
///
/// ```dart
/// import 'package:flutter_tvos/flutter_tvos.dart';
///
/// // 1. Static helper (mirrors `Platform.isIOS` call shape)
/// if (FlutterTvosPlatform.isTvos) { /* ... */ }
///
/// // 2. Extension on a Platform instance, for code that already holds one:
/// void run(Platform p) {
///   if (p.isTvos) { /* ... */ }
/// }
/// ```
///
/// Note on naming: we cannot add a true `Platform.isTvos` static getter — Dart
/// does not (yet) support static extensions on external classes. The core
/// Dart VM exposes `Platform.isTvOS` (capital OS) via our engine patch; this
/// class uses `isTvos` (lowercase) to mirror the existing convention of
/// `isIOS` / `isIos`. Either spelling works equivalently.
abstract final class FlutterTvosPlatform {
  /// Whether the current operating system is tvOS.
  ///
  /// Equivalent to `Platform.operatingSystem == 'tvos'` (the string emitted
  /// by our Dart VM patch on Apple TV). The engine also exposes a native
  /// `Platform.isTvOS` getter at runtime, but we use the string check here
  /// so code analyzes cleanly against an unpatched Dart SDK in IDE tooling.
  static bool get isTvos => Platform.operatingSystem == 'tvos';

  /// Whether the current operating system is iOS in the strict sense —
  /// iPhone or iPad — and **not** tvOS.
  ///
  /// `Platform.isIOS` alone is `true` on both iPhone/iPad and Apple TV, so
  /// this helper excludes tvOS. Use this when your code only makes sense on
  /// a handheld (touch gestures, haptics, status bar, etc.).
  ///
  /// ```dart
  /// // Wrong — also runs on Apple TV
  /// if (Platform.isIOS) { showTouchGestureHint(); }
  ///
  /// // Right — iPhone / iPad only
  /// if (FlutterTvosPlatform.isIos) { showTouchGestureHint(); }
  /// ```
  static bool get isIos => Platform.isIOS && !isTvos;

  /// Whether the current OS is any iOS-family platform: iPhone, iPad, or
  /// Apple TV. Equivalent to the raw `Platform.isIOS` check.
  ///
  /// Use this when your code works on any iOS-derived platform (UIKit is
  /// present, Foundation is present, same Darwin kernel). Covers the
  /// "treat Apple's mobile/TV family uniformly" case.
  static bool get isAppleMobile => Platform.isIOS;
}

/// Extension on a [Platform] instance that adds tvOS-aware getters.
///
/// Dart can't extend `Platform`'s static members, but projects that already
/// have a `Platform` instance (for mocking in tests, or to pass around as a
/// `platform.Platform`) can still use the ergonomic form:
///
/// ```dart
/// import 'dart:io';
/// import 'package:flutter_tvos/flutter_tvos.dart';
///
/// void log(Platform p) {
///   if (p.isTvos) print('on tvOS');
///   if (p.isIos) print('on iPhone/iPad (not TV)');
/// }
/// ```
extension FlutterTvosPlatformExt on Platform {
  /// Whether this [Platform] reports tvOS as its operating system.
  bool get isTvos => Platform.operatingSystem == 'tvos';

  /// Whether this [Platform] is strict iOS (iPhone/iPad) — **not** tvOS.
  bool get isIos => Platform.isIOS && Platform.operatingSystem != 'tvos';
}
