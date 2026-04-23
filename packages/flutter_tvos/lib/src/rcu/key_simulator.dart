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
/// We use the `macos` keymap for keys Apple's `kVK_*` constants cover
/// (arrows, enter, escape). For `LogicalKeyboardKey.select` there is no
/// dedicated macOS keycode — the closest match, `kVK_Return` (0x24),
/// decodes to `enter` in Flutter's `kMacOsToLogicalKey` table. To still
/// deliver `LogicalKeyboardKey.select`, we fall back to the `android`
/// keymap, which maps `23 → select`. Both paths land in the same
/// `HardwareKeyboard` state so consumers see a consistent key.
///
/// Returns `true` if the event was handled by Flutter, `false` otherwise.
Future<bool> simulateKeyEvent(
  LogicalKeyboardKey logicalKey, {
  required bool isDown,
}) async {
  final encoding = _encodingFor(logicalKey);
  if (encoding == null) {
    return false;
  }

  final message = <String, dynamic>{
    'type': isDown ? 'keydown' : 'keyup',
    'keymap': encoding.keymap,
    'keyCode': encoding.keyCode,
    'modifiers': 0,
    if (encoding.keymap == 'macos') ...{
      'characters': '',
      'charactersIgnoringModifiers': '',
    } else ...{
      'scanCode': 0,
      'metaState': 0,
    },
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

class _KeyEncoding {
  const _KeyEncoding(this.keymap, this.keyCode);
  final String keymap;
  final int keyCode;
}

_KeyEncoding? _encodingFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowUp) return const _KeyEncoding('macos', 0x7E);
  if (key == LogicalKeyboardKey.arrowDown) return const _KeyEncoding('macos', 0x7D);
  if (key == LogicalKeyboardKey.arrowLeft) return const _KeyEncoding('macos', 0x7B);
  if (key == LogicalKeyboardKey.arrowRight) return const _KeyEncoding('macos', 0x7C);
  if (key == LogicalKeyboardKey.enter) return const _KeyEncoding('macos', 0x24);
  if (key == LogicalKeyboardKey.escape) return const _KeyEncoding('macos', 0x35);
  // No macOS keycode produces `LogicalKeyboardKey.select`; use Android
  // keymap entry `23 → select` from Flutter's `kAndroidToLogicalKey`.
  if (key == LogicalKeyboardKey.select) return const _KeyEncoding('android', 23);
  return null;
}
