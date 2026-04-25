// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart'
    show BasicMessageChannel, JSONMessageCodec, JSONMethodCodec, MethodChannel;

import 'tv_remote_protocol.dart';

/// Channel definitions shared between the native `FlutterTvRemotePlugin`
/// and the Dart [TvRemoteController]. Channel names live in
/// [TvRemoteProtocol] alongside other wire-format constants.
abstract final class TvRemoteChannels {
  /// Method channel for `configure` (Dart → native).
  static const button = MethodChannel(
    TvRemoteProtocol.buttonChannelName,
    JSONMethodCodec(),
  );

  /// Basic message channel for continuous touchpad / D-pad / click
  /// events (native → Dart).
  ///
  /// Message shape:
  /// ```json
  /// {
  ///   "type": "started" | "move" | "ended" | "cancelled" | "loc" | "click_s" | "click_e",
  ///   "x": <double in [-1.0, 1.0]>,
  ///   "y": <double in [-1.0, 1.0]>
  /// }
  /// ```
  /// Phase strings are defined in [TvRemoteProtocol].
  static const touches = BasicMessageChannel<dynamic>(
    TvRemoteProtocol.touchesChannelName,
    JSONMessageCodec(),
  );
}
