// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/src/rcu/tv_remote_channels.dart';
import 'package:flutter_tvos/src/rcu/tv_remote_controller.dart';

/// Injects a touch message onto the touches channel as if it came from native.
Future<void> _sendTouch(Map<String, dynamic> message) async {
  final codec = TvRemoteChannels.touches.codec;
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    TvRemoteChannels.touches.name,
    codec.encodeMessage(message),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => TvRemoteController.instance.debugReset());
  tearDown(() => TvRemoteController.instance.debugReset());

  group('TvRemoteController raw touch fan-out', () {
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

    test('loc events reach raw listeners', () async {
      final events = <TvRemoteTouchEvent>[];
      TvRemoteController.instance.addRawListener(events.add);
      TvRemoteController.instance.debugInit();

      await _sendTouch({'type': 'loc', 'x': 0.8, 'y': 0.2});
      expect(events.single.phase, TvRemoteTouchPhase.loc);
      expect(events.single.x, closeTo(0.8, 1e-9));
    });

    test('click_s / click_e reach raw listeners as clickStart/clickEnd',
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

    test('throwing listener does not block subsequent listeners', () async {
      final tailEvents = <TvRemoteTouchEvent>[];
      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;

      try {
        final controller = TvRemoteController.instance;
        controller.addRawListener((e) => throw StateError('boom'));
        controller.addRawListener(tailEvents.add);
        controller.debugInit();

        await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
        expect(tailEvents.length, 1, reason: 'tail listener still runs');
        expect(errors.length, 1, reason: 'first listener reported via FlutterError');
      } finally {
        FlutterError.onError = previousOnError;
      }
    });

    test('cancelled phase resets internal swipe state', () async {
      final controller = TvRemoteController.instance;
      controller.debugInit();
      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      await _sendTouch({'type': 'move', 'x': 0.2, 'y': 0.0});
      await _sendTouch({'type': 'cancelled', 'x': 0.2, 'y': 0.0});
      // No throw — subsequent gesture starts cleanly.
      await _sendTouch({'type': 'started', 'x': 0.5, 'y': 0.5});
    });

    test('init after debugReset re-attaches handlers', () async {
      final events = <TvRemoteTouchEvent>[];
      final controller = TvRemoteController.instance;
      controller.addRawListener(events.add);
      controller.debugInit();

      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      expect(events.length, 1);

      controller.debugReset();
      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      expect(events.length, 1, reason: 'handler detached after reset');

      controller.addRawListener(events.add);
      controller.debugInit();
      await _sendTouch({'type': 'started', 'x': 0.0, 'y': 0.0});
      expect(events.length, 2, reason: 'handler reattached');
    });
  });

  group('TvRemoteConfig validation', () {
    test('rejects non-positive shortSwipeThreshold', () {
      expect(() => TvRemoteConfig(shortSwipeThreshold: 0),
          throwsAssertionError);
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

    test('rejects non-positive continuousSwipeMoveThreshold', () {
      expect(() => TvRemoteConfig(continuousSwipeMoveThreshold: 0),
          throwsAssertionError);
    });

    test('accepts sentinel dpadDeadZone > 1.0 to disable bias', () {
      expect(() => const TvRemoteConfig(dpadDeadZone: 2.0),
          returnsNormally);
    });

    test('toMap serializes every field', () {
      const cfg = TvRemoteConfig(
        shortSwipeThreshold: 0.4,
        fastSwipeThreshold: 0.6,
        dpadDeadZone: 0.7,
        continuousSwipeMoveThreshold: 5,
        keyRepeatInitialDelay: Duration(milliseconds: 500),
        keyRepeatInterval: Duration(milliseconds: 100),
      );
      expect(cfg.toMap(), {
        'shortSwipeThreshold': 0.4,
        'fastSwipeThreshold': 0.6,
        'dpadDeadZone': 0.7,
        'continuousSwipeMoveThreshold': 5,
        'keyRepeatInitialDelayMs': 500,
        'keyRepeatIntervalMs': 100,
      });
    });
  });

  group('TvRemoteController config dispatch', () {
    // Intercept the button method channel to record `configure` calls
    // sent from Dart to native.
    final configureCalls = <Map<String, Object?>>[];

    setUp(() {
      configureCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteChannels.button,
              (MethodCall call) async {
        if (call.method == 'configure') {
          configureCalls.add(
              Map<String, Object?>.from(call.arguments as Map));
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteChannels.button, null);
    });

    test('init pushes the current config to native', () async {
      TvRemoteController.instance.config = const TvRemoteConfig(
        shortSwipeThreshold: 0.4,
      );
      TvRemoteController.instance.debugInit();
      // Method call is async; let the event loop drain.
      await Future<void>.delayed(Duration.zero);

      expect(configureCalls.length, greaterThanOrEqualTo(1));
      final last = configureCalls.last;
      expect(last['shortSwipeThreshold'], 0.4);
      expect(last['dpadDeadZone'], 0.5);  // default preserved
    });

    test('config reassignment pushes updated values', () async {
      TvRemoteController.instance.debugInit();
      await Future<void>.delayed(Duration.zero);
      final baseline = configureCalls.length;

      TvRemoteController.instance.config =
          const TvRemoteConfig(dpadDeadZone: 0.8);
      await Future<void>.delayed(Duration.zero);

      expect(configureCalls.length, greaterThan(baseline));
      expect(configureCalls.last['dpadDeadZone'], 0.8);
    });
  });

  group('Edge cases', () {
    final configureCalls = <Map<String, Object?>>[];

    setUp(() {
      configureCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteChannels.button,
              (MethodCall call) async {
        if (call.method == 'configure') {
          configureCalls.add(
              Map<String, Object?>.from(call.arguments as Map));
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TvRemoteChannels.button, null);
    });

    test('init() second call does not re-push config', () async {
      TvRemoteController.instance.debugInit();
      await Future<void>.delayed(Duration.zero);
      final firstCount = configureCalls.length;

      TvRemoteController.instance.debugInit();
      await Future<void>.delayed(Duration.zero);

      expect(configureCalls.length, firstCount,
          reason: 'second init() should be a no-op');
    });

    test('config setter before init() is pushed on init()', () async {
      TvRemoteController.instance.config = const TvRemoteConfig(
        dpadDeadZone: 0.9,
      );
      // Pre-init mutations don't ship to native (no handler attached
      // yet). The dispatch must happen on first init().
      await Future<void>.delayed(Duration.zero);
      expect(configureCalls, isEmpty,
          reason: 'pre-init config setter must not push prematurely');

      TvRemoteController.instance.debugInit();
      await Future<void>.delayed(Duration.zero);
      expect(configureCalls.last['dpadDeadZone'], 0.9);
    });

    test('addRawListener during dispatch fires only on next event',
        () async {
      final orderLog = <String>[];
      final controller = TvRemoteController.instance;
      controller.addRawListener((_) {
        orderLog.add('outer');
        // Adding mid-dispatch must not surface for the current event —
        // List.of(...) snapshot is taken before iteration.
        controller.addRawListener((_) => orderLog.add('inner'));
      });
      controller.debugInit();

      final codec = TvRemoteChannels.touches.codec;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        TvRemoteChannels.touches.name,
        codec.encodeMessage({'type': 'started', 'x': 0.0, 'y': 0.0}),
        (_) {},
      );

      expect(orderLog, ['outer'],
          reason: 'newly added listener must not fire for the same event');

      // Second event — both listeners now installed.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        TvRemoteChannels.touches.name,
        codec.encodeMessage({'type': 'move', 'x': 0.5, 'y': 0.0}),
        (_) {},
      );
      expect(orderLog, ['outer', 'outer', 'inner']);
    });

    test('removeRawListener during dispatch — current iteration still fires',
        () async {
      final received = <String>[];
      final controller = TvRemoteController.instance;
      void secondListener(TvRemoteTouchEvent e) {
        received.add('second');
      }
      void firstListener(TvRemoteTouchEvent e) {
        received.add('first');
        // Remove the second listener during dispatch — but it should
        // still fire on this event (snapshot semantics).
        controller.removeRawListener(secondListener);
      }
      controller.addRawListener(firstListener);
      controller.addRawListener(secondListener);
      controller.debugInit();

      final codec = TvRemoteChannels.touches.codec;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        TvRemoteChannels.touches.name,
        codec.encodeMessage({'type': 'started', 'x': 0.0, 'y': 0.0}),
        (_) {},
      );

      expect(received, ['first', 'second']);

      // Second event: secondListener was removed, only first should run.
      received.clear();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        TvRemoteChannels.touches.name,
        codec.encodeMessage({'type': 'move', 'x': 0.5, 'y': 0.0}),
        (_) {},
      );
      expect(received, ['first']);
    });

    test('x/y outside [-1, 1] are passed through unclamped', () async {
      final events = <TvRemoteTouchEvent>[];
      TvRemoteController.instance.addRawListener(events.add);
      TvRemoteController.instance.debugInit();

      final codec = TvRemoteChannels.touches.codec;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        TvRemoteChannels.touches.name,
        codec.encodeMessage({'type': 'move', 'x': 1.5, 'y': -2.0}),
        (_) {},
      );

      expect(events.single.x, closeTo(1.5, 1e-9));
      expect(events.single.y, closeTo(-2.0, 1e-9));
    });

    test('phase string with wrong case is silently dropped', () async {
      final events = <TvRemoteTouchEvent>[];
      TvRemoteController.instance.addRawListener(events.add);
      TvRemoteController.instance.debugInit();

      final codec = TvRemoteChannels.touches.codec;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        TvRemoteChannels.touches.name,
        codec.encodeMessage({'type': 'STARTED', 'x': 0.0, 'y': 0.0}),
        (_) {},
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        TvRemoteChannels.touches.name,
        codec.encodeMessage({'type': 'Started', 'x': 0.0, 'y': 0.0}),
        (_) {},
      );

      expect(events, isEmpty,
          reason: 'phase strings are case-sensitive on the wire');
    });

    test('TvRemoteConfig accepts Duration.zero for repeat parameters', () {
      expect(
        () => const TvRemoteConfig(
          keyRepeatInitialDelay: Duration.zero,
          keyRepeatInterval: Duration.zero,
        ),
        returnsNormally,
      );
    });

    test('TvRemoteConfig.toMap uses exact wire-format keys', () {
      // Drift detection: native plugin reads these exact keys from the
      // configure args dict. If you rename one, the engine side must
      // mirror — this test will alarm on drift.
      const cfg = TvRemoteConfig(
        shortSwipeThreshold: 0.1,
        fastSwipeThreshold: 0.2,
        dpadDeadZone: 0.3,
        continuousSwipeMoveThreshold: 4,
        keyRepeatInitialDelay: Duration(milliseconds: 100),
        keyRepeatInterval: Duration(milliseconds: 50),
      );
      final map = cfg.toMap();
      expect(map.keys, containsAll(<String>[
        'shortSwipeThreshold',
        'fastSwipeThreshold',
        'dpadDeadZone',
        'continuousSwipeMoveThreshold',
        'keyRepeatInitialDelayMs',
        'keyRepeatIntervalMs',
      ]));
      expect(map['keyRepeatInitialDelayMs'], 100);
      expect(map['keyRepeatIntervalMs'], 50);
    });
  });
}
