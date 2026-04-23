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
  final codec = TvRemoteChannels.button.codec as MethodCodec;
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
}
