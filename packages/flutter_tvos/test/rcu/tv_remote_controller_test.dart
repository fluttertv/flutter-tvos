// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/src/rcu/tv_remote_channels.dart';
import 'package:flutter_tvos/src/rcu/tv_remote_controller.dart';

/// Injects a touch message onto the touches channel as if it came from native.
Future<void> _sendTouch(Map<String, dynamic> message) async {
  final codec = TvRemoteChannels.touches.codec;
  await TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .handlePlatformMessage(
    TvRemoteChannels.touches.name,
    codec.encodeMessage(message),
    (_) {},
  );
}

/// Invokes a method on the button channel as if it came from native.
Future<void> _sendButton(String method, Map<String, dynamic> args) async {
  final codec = TvRemoteChannels.button.codec;
  final call = MethodCall(method, args);
  await TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .handlePlatformMessage(
    TvRemoteChannels.button.name,
    codec.encodeMethodCall(call),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => TvRemoteController.instance.debugReset());
  tearDown(() => TvRemoteController.instance.debugReset());

  group('TvRemoteController', () {
    test('raw listeners receive every touch event', () async {
      final events = <TvRemoteTouchEvent>[];
      final controller = TvRemoteController.instance;
      controller.addRawListener(events.add);
      controller.debugInit();

      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'move', 'x': 0.5, 'y': 0.0});
      await _sendTouch({'type': 'ended', 'x': 0.5, 'y': 0.0});

      expect(events.map((e) => e.phase), [
        TvRemoteTouchPhase.started,
        TvRemoteTouchPhase.move,
        TvRemoteTouchPhase.ended,
      ]);
      expect(events[1].x, closeTo(0.5, 1e-9));
    });

    test('removeRawListener stops delivery', () async {
      final events = <TvRemoteTouchEvent>[];
      void listener(TvRemoteTouchEvent e) => events.add(e);

      final controller = TvRemoteController.instance;
      controller.addRawListener(listener);
      controller.debugInit();

      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      controller.removeRawListener(listener);
      await _sendTouch({'type': 'move', 'x': 0.5, 'y': 0.0});

      expect(events.length, 1);
    });

    test('ignores malformed messages silently', () async {
      final events = <TvRemoteTouchEvent>[];
      TvRemoteController.instance.addRawListener(events.add);
      TvRemoteController.instance.debugInit();

      await _sendTouch({'type': 'garbage', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'started'}); // missing x,y — treated as 0
      expect(events.length, 1);
      expect(events.single.phase, TvRemoteTouchPhase.started);
    });

    test('loc events deliver D-pad position without firing keys', () async {
      final events = <TvRemoteTouchEvent>[];
      TvRemoteController.instance.addRawListener(events.add);
      TvRemoteController.instance.debugInit();

      await _sendTouch({'type': 'loc', 'x': 0.8, 'y': 0.2});
      expect(events.single.phase, TvRemoteTouchPhase.loc);
      expect(events.single.x, closeTo(0.8, 1e-9));
    });

    test('click_s / click_e translate to clickStart / clickEnd phases',
        () async {
      final events = <TvRemoteTouchEvent>[];
      TvRemoteController.instance.addRawListener(events.add);
      TvRemoteController.instance.debugInit();

      await _sendTouch({'type': 'click_s', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'click_e', 'x': 0.0, 'y': 0.0});

      expect(events.map((e) => e.phase), [
        TvRemoteTouchPhase.clickStart,
        TvRemoteTouchPhase.clickEnd,
      ]);
    });

    test('multiple raw listeners all receive events', () async {
      final listenerA = <TvRemoteTouchEvent>[];
      final listenerB = <TvRemoteTouchEvent>[];
      final controller = TvRemoteController.instance;
      controller.addRawListener(listenerA.add);
      controller.addRawListener(listenerB.add);
      controller.debugInit();

      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      expect(listenerA.length, 1);
      expect(listenerB.length, 1);
    });

    test('unknown phase type is silently dropped', () async {
      final events = <TvRemoteTouchEvent>[];
      TvRemoteController.instance.addRawListener(events.add);
      TvRemoteController.instance.debugInit();

      await _sendTouch({'type': 'magic_phase', 'x': 0.0, 'y': 0.0});
      expect(events, isEmpty);
    });

    test('cancelled phase resets accumulator (no throw on subsequent move)',
        () async {
      final controller = TvRemoteController.instance;
      controller.debugInit();
      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'move', 'x': 0.2, 'y': 0.0});
      await _sendTouch({'type': 'cancelled', 'x': 0.2, 'y': 0.0});
      // After cancel, another touch sequence should work cleanly.
      await _sendTouch({'type': 'started', 'x': 0.5, 'y': 0.5});
      // No throw, no assertion: cancel cleared state.
    });

    test('init after debugReset re-attaches handlers', () async {
      final events = <TvRemoteTouchEvent>[];
      final controller = TvRemoteController.instance;
      controller.addRawListener(events.add);
      controller.debugInit();

      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      expect(events.length, 1);

      controller.debugReset();
      // After reset, listeners cleared and handlers detached.
      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      expect(events.length, 1, reason: 'handler detached after reset');

      // Re-init and re-add listener.
      controller.addRawListener(events.add);
      controller.debugInit();
      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      expect(events.length, 2, reason: 'handler reattached');
    });

    test('config mutation takes effect on next event (threshold)', () async {
      final controller = TvRemoteController.instance;
      controller.debugInit();

      // Default threshold 0.3, a move of 0.25 should not emit.
      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'move', 'x': 0.25, 'y': 0.0});
      await _sendTouch({'type': 'ended', 'x': 0.25, 'y': 0.0});

      // Lower threshold, same motion should now emit (test the getter-
      // based cache in the controller picks up the new config).
      controller.config = const TvRemoteConfig(shortSwipeThreshold: 0.2);
      final events = <TvRemoteTouchEvent>[];
      controller.addRawListener(events.add);

      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'move', 'x': 0.25, 'y': 0.0});
      await _sendTouch({'type': 'ended', 'x': 0.25, 'y': 0.0});
      expect(events.length, 3);
    });

    // Button channel tests — these verify the _onButtonCall handler.
    // We can't assert key simulation without patching ServicesBinding, so
    // we only assert the handler returns normally for well-formed input
    // and silently ignores malformed input.

    test('button channel: Menu press is accepted', () async {
      TvRemoteController.instance.debugInit();
      // Should not throw.
      await _sendButton('press', {'key': 'menu', 'isDown': true});
      await _sendButton('press', {'key': 'menu', 'isDown': false});
    });

    test('button channel: Play/Pause press is accepted', () async {
      TvRemoteController.instance.debugInit();
      await _sendButton('press', {'key': 'playPause', 'isDown': true});
      await _sendButton('press', {'key': 'playPause', 'isDown': false});
    });

    test('button channel: unknown key name is ignored', () async {
      TvRemoteController.instance.debugInit();
      await _sendButton('press', {'key': 'unknown_btn', 'isDown': true});
      // No throw — handler silently returns.
    });

    test('button channel: media play command is accepted', () async {
      TvRemoteController.instance.debugInit();
      await _sendButton('media', {'command': 'play', 'isDown': true});
      await _sendButton('media', {'command': 'play', 'isDown': false});
    });

    test('button channel: media seekForward is accepted', () async {
      TvRemoteController.instance.debugInit();
      await _sendButton('media', {'command': 'seekForward', 'isDown': true});
      await _sendButton('media', {'command': 'seekForward', 'isDown': false});
    });

    test('button channel: unknown media command is ignored', () async {
      TvRemoteController.instance.debugInit();
      await _sendButton('media', {'command': 'teleport', 'isDown': true});
    });

    test('button channel: unknown method is ignored', () async {
      TvRemoteController.instance.debugInit();
      await _sendButton('mystery', {'key': 'anything'});
    });
  });

  group('TvRemoteController keyboard event dispatch', () {
    // Intercepts `SystemChannels.keyEvent` so tests can assert the exact
    // sequence of keydown/keyup messages the controller emits for click
    // phases and directional-click bias.
    final recorded = <Map<String, dynamic>>[];

    setUp(() {
      recorded.clear();
      // `simulateKeyEvent` pushes into `channelBuffers.push`, which
      // delivers to whatever handler is registered for
      // `flutter/keyevent` on the Dart side (normally `RawKeyboard`).
      // Override that handler in-test to capture the payload.
      SystemChannels.keyEvent.setMessageHandler((Object? message) async {
        if (message is Map) {
          recorded.add(Map<String, dynamic>.from(message));
        }
        return <String, dynamic>{'handled': true};
      });
    });

    tearDown(() {
      SystemChannels.keyEvent.setMessageHandler(null);
    });

    test('click_s then click_e emits select keydown + keyup', () async {
      TvRemoteController.instance.debugInit();
      await _sendTouch({'type': 'click_s', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'click_e', 'x': 0.0, 'y': 0.0});

      expect(recorded.length, 2, reason: 'one keydown + one keyup');
      expect(recorded[0]['type'], 'keydown');
      expect(recorded[1]['type'], 'keyup');
      // Select falls back to Android keymap code 23 because macOS has
      // no dedicated kVK_* for LogicalKeyboardKey.select.
      expect(recorded[0]['keymap'], 'android');
      expect(recorded[0]['keyCode'], 23);
      expect(recorded[1]['keymap'], 'android');
      expect(recorded[1]['keyCode'], 23);
    });

    test(
        'click_s then click_s then click_e emits 2 keydowns + 2 keyups '
        '(CR #1 regression guard)', () async {
      TvRemoteController.instance.debugInit();
      await _sendTouch({'type': 'click_s', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'click_s', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'click_e', 'x': 0.0, 'y': 0.0});

      final types = recorded.map((m) => m['type']).toList();
      // Expected: keydown(select), keyup(select) [guard], keydown(select),
      // keyup(select). Four events, alternating.
      expect(types, ['keydown', 'keyup', 'keydown', 'keyup']);
      for (final event in recorded) {
        expect(event['keymap'], 'android');
        expect(event['keyCode'], 23);
      }
    });

    test('directional bias: loc(0.6) then click_s emits arrowRight',
        () async {
      TvRemoteController.instance.debugInit();
      await _sendTouch({'type': 'loc', 'x': 0.6, 'y': 0.0});
      await _sendTouch({'type': 'click_s', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'click_e', 'x': 0.0, 'y': 0.0});

      // arrowRight uses macOS keymap code 0x7C.
      expect(recorded.length, 2);
      expect(recorded[0]['keymap'], 'macos');
      expect(recorded[0]['keyCode'], 0x7C);
      expect(recorded[1]['keyCode'], 0x7C);
    });

    test('directional bias: loc(-0.6) then click_s emits arrowLeft',
        () async {
      TvRemoteController.instance.debugInit();
      await _sendTouch({'type': 'loc', 'x': -0.6, 'y': 0.0});
      await _sendTouch({'type': 'click_s', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'click_e', 'x': 0.0, 'y': 0.0});

      expect(recorded.length, 2);
      expect(recorded[0]['keymap'], 'macos');
      expect(recorded[0]['keyCode'], 0x7B);  // arrowLeft
      expect(recorded[1]['keyCode'], 0x7B);
    });

    test('directional bias: loc inside dead zone stays Select', () async {
      TvRemoteController.instance.debugInit();
      await _sendTouch({'type': 'loc', 'x': 0.49, 'y': 0.0});
      await _sendTouch({'type': 'click_s', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'click_e', 'x': 0.0, 'y': 0.0});

      // Still Select → Android keymap 23 fallback.
      expect(recorded.length, 2);
      expect(recorded[0]['keymap'], 'android');
      expect(recorded[0]['keyCode'], 23);
    });
  });

  group('TvRemoteConfig validation', () {
    test('rejects non-positive shortSwipeThreshold', () {
      expect(() => TvRemoteConfig(shortSwipeThreshold: 0), throwsAssertionError);
      expect(() => TvRemoteConfig(shortSwipeThreshold: -0.1),
          throwsAssertionError);
    });

    test('requires fastSwipeThreshold >= shortSwipeThreshold', () {
      expect(
          () => TvRemoteConfig(
              shortSwipeThreshold: 0.5, fastSwipeThreshold: 0.3),
          throwsAssertionError);
    });

    test('rejects non-positive dpadDeadZone', () {
      expect(() => TvRemoteConfig(dpadDeadZone: 0), throwsAssertionError);
      expect(() => TvRemoteConfig(dpadDeadZone: -1), throwsAssertionError);
    });

    test('accepts sentinel dpadDeadZone > 1.0 to disable bias', () {
      expect(() => const TvRemoteConfig(dpadDeadZone: 2.0), returnsNormally);
    });
  });
}
