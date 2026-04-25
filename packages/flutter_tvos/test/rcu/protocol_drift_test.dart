// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Drift detection: pin the wire-format values used by `TvRemoteProtocol`.
// These values must match the constants in
// `engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterTvRemoteProtocol.h`.
// A native counterpart test (`testProtocolConstants_StableWireValues`)
// asserts the same values on the engine side, so renaming on either
// side without matching the other will fail in CI.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/src/rcu/tv_remote_protocol.dart';

void main() {
  group('TvRemoteProtocol wire values', () {
    test('channel names', () {
      expect(TvRemoteProtocol.buttonChannelName, 'flutter/tv_remote');
      expect(TvRemoteProtocol.touchesChannelName,
          'flutter/tv_remote_touches');
    });

    test('touch phase strings', () {
      expect(TvRemoteProtocol.phaseStarted, 'started');
      expect(TvRemoteProtocol.phaseMove, 'move');
      expect(TvRemoteProtocol.phaseEnded, 'ended');
      expect(TvRemoteProtocol.phaseCancelled, 'cancelled');
      expect(TvRemoteProtocol.phaseLoc, 'loc');
      expect(TvRemoteProtocol.phaseClickStart, 'click_s');
      expect(TvRemoteProtocol.phaseClickEnd, 'click_e');
    });

    test('configure dictionary keys', () {
      expect(TvRemoteProtocol.cfgShortSwipeThreshold, 'shortSwipeThreshold');
      expect(TvRemoteProtocol.cfgFastSwipeThreshold, 'fastSwipeThreshold');
      expect(TvRemoteProtocol.cfgDpadDeadZone, 'dpadDeadZone');
      expect(TvRemoteProtocol.cfgContinuousSwipeMoveThreshold,
          'continuousSwipeMoveThreshold');
      expect(TvRemoteProtocol.cfgKeyRepeatInitialDelayMs,
          'keyRepeatInitialDelayMs');
      expect(TvRemoteProtocol.cfgKeyRepeatIntervalMs, 'keyRepeatIntervalMs');
    });

    test('method names', () {
      expect(TvRemoteProtocol.methodConfigure, 'configure');
    });
  });
}
