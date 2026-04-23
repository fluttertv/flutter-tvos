// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart'
    show BasicMessageChannel, JSONMessageCodec, JSONMethodCodec, MethodChannel;

/// Channel names and codec definitions shared between the native
/// `FlutterTvRemotePlugin` and the Dart [TvRemoteController].
///
/// Both ends must use these exact names for messages to flow.
abstract final class TvRemoteChannels {
  /// Method channel for discrete button presses (arrows, select, menu,
  /// play/pause, page up/down) and media commands (seek, play, pause, stop).
  ///
  /// Methods:
  /// - `press` — `{ 'key': '<LogicalKey>', 'isDown': bool }`
  /// - `media` — `{ 'command': 'seekForward' | 'seekBackward' | 'play' |
  ///   'pause' | 'stop' | 'togglePlayPause' | 'fastForward' | 'rewind',
  ///   'isDown': bool }`
  static const button = MethodChannel(
    'flutter/tv_remote',
    JSONMethodCodec(),
  );

  /// Basic message channel for continuous touchpad events from Siri Remote.
  ///
  /// Message shape:
  /// ```json
  /// {
  ///   "type": "started" | "move" | "ended" | "cancelled" | "loc" | "click_s" | "click_e",
  ///   "x": <double in [-1.0, 1.0]>,
  ///   "y": <double in [-1.0, 1.0]>
  /// }
  /// ```
  ///
  /// - `started` / `move` / `ended` / `cancelled` — touchpad gesture phase.
  ///   x,y are normalized to the view's bounds: origin (0,0) is center,
  ///   corners are (±1, ±1).
  /// - `loc` — D-pad value from `GCMicroGamepad.dpad.valueChangedHandler`.
  ///   x,y are already in [-1.0, 1.0] from GameController framework.
  /// - `click_s` / `click_e` — Siri Remote touchpad physical click
  ///   pressed in / released. x,y are 0.0 (the click is a discrete
  ///   event, not located on the pad).
  static const touches = BasicMessageChannel<dynamic>(
    'flutter/tv_remote_touches',
    JSONMessageCodec(),
  );
}
