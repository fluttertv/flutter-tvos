// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async' show Completer;

import 'package:flutter/services.dart'
    show LogicalKeyboardKey, ServicesBinding, SystemChannels;

/// Simulates a hardware keyboard event and dispatches it through Flutter's
/// `SystemChannels.keyEvent`, the same pipeline a real keypress uses.
///
/// Most keyboard simulation in this package happens natively: physical
/// arrow/page buttons and continuous swipes go through the engine plugin
/// directly to `flutter/keyevent`, so the Dart controller never touches
/// them. This helper is only used for touchpad **click** events, where
/// the Dart controller applies directional bias before emitting a key —
/// logic that stays in Dart so it can be configured per-app via
/// [TvRemoteConfig.dpadDeadZone].
///
/// On Apple TV we use the `macos` keymap because the Flutter engine's
/// Darwin path decodes that format.
///
/// Returns `true` if the event was handled by Flutter, `false` otherwise.
Future<bool> simulateKeyEvent(
  LogicalKeyboardKey logicalKey, {
  required bool isDown,
}) async {
  final macOsKeyCode = _logicalKeyToMacOsKeyCode(logicalKey);
  if (macOsKeyCode == null) {
    return false;
  }

  final message = <String, dynamic>{
    'type': isDown ? 'keydown' : 'keyup',
    'keymap': 'macos',
    'keyCode': macOsKeyCode,
    'characters': '',
    'charactersIgnoringModifiers': '',
    'modifiers': 0,
  };

  final completer = Completer<bool>();
  final codec = SystemChannels.keyEvent.codec;
  ServicesBinding.instance.channelBuffers.push(
    SystemChannels.keyEvent.name,
    codec.encodeMessage(message),
    (data) {
      if (data == null) {
        completer.complete(false);
        return;
      }
      final decoded = codec.decodeMessage(data);
      if (decoded is Map && decoded['handled'] is bool) {
        completer.complete(decoded['handled'] as bool);
      } else {
        completer.complete(false);
      }
    },
  );
  return completer.future;
}

int? _logicalKeyToMacOsKeyCode(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return 0x7E;
  if (key == LogicalKeyboardKey.arrowDown) return 0x7D;
  if (key == LogicalKeyboardKey.arrowLeft) return 0x7B;
  if (key == LogicalKeyboardKey.arrowRight) return 0x7C;
  if (key == LogicalKeyboardKey.select) return 0x24;
  if (key == LogicalKeyboardKey.enter) return 0x24;
  if (key == LogicalKeyboardKey.escape) return 0x35;
  return null;
}
