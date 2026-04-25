// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Single source of truth for the wire protocol shared with the native
/// `FlutterTvRemotePlugin` (engine-side).
///
/// Every literal here MUST match the corresponding `extern NSString*`
/// constant declared in
/// `engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemoteProtocol.h`
/// and defined in `FlutterTvRemoteProtocol.mm`.
///
/// `protocol_drift_test.dart` (Dart) and `testProtocolConstants_*` XCTests
/// (native) both pin the wire values, so any rename of one side without
/// matching the other will fail in CI before reaching runtime.
abstract final class TvRemoteProtocol {
  // ---- Channel names ----

  /// Method channel for `configure` (Dart → native).
  static const String buttonChannelName = 'flutter/tv_remote';

  /// Basic message channel for touch / D-pad / click events
  /// (native → Dart).
  static const String touchesChannelName = 'flutter/tv_remote_touches';

  // ---- Touch phase wire strings ----

  /// Touchpad finger placed.
  static const String phaseStarted = 'started';

  /// Touchpad finger moved.
  static const String phaseMove = 'move';

  /// Touchpad finger lifted normally.
  static const String phaseEnded = 'ended';

  /// Gesture cancelled by the system.
  static const String phaseCancelled = 'cancelled';

  /// D-pad position update from `GCMicroGamepad`.
  static const String phaseLoc = 'loc';

  /// Touchpad pressed in (physical click — start).
  static const String phaseClickStart = 'click_s';

  /// Touchpad released (physical click — end).
  static const String phaseClickEnd = 'click_e';

  // ---- Configure dictionary keys (Dart → native via `configure` method) ----

  static const String cfgShortSwipeThreshold = 'shortSwipeThreshold';
  static const String cfgFastSwipeThreshold = 'fastSwipeThreshold';
  static const String cfgDpadDeadZone = 'dpadDeadZone';
  static const String cfgContinuousSwipeMoveThreshold =
      'continuousSwipeMoveThreshold';
  static const String cfgKeyRepeatInitialDelayMs = 'keyRepeatInitialDelayMs';
  static const String cfgKeyRepeatIntervalMs = 'keyRepeatIntervalMs';

  // ---- Method names ----

  /// Single supported method on the button channel today.
  static const String methodConfigure = 'configure';
}
