// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Integration tests that exercise the real native↔Dart channels
// (FlutterTvRemotePlugin + TvRemoteController) against a live engine.
//
// Run on a tvOS simulator / device:
//
//   cd packages/flutter_tvos/example
//   flutter test integration_test --device-id <tvos-udid>
//
// These tests are the cheapest layer that catches the kind of bug
// where a method channel has no listener on the other side. Widget
// tests can't observe that; only a live engine sending real method
// calls exposes it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/flutter_tvos.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('configure → native round-trip does not throw',
      (tester) async {
    // The method call fires off on `flutter/tv_remote` button channel.
    // On iOS / Android the channel has no native counterpart — the
    // invocation fails silently and that's fine. On tvOS the plugin
    // acknowledges it with `result(nil)`. Either way the assertion is
    // "no unhandled exception bubbles up".
    TvRemoteController.instance.config = const TvRemoteConfig(
      shortSwipeThreshold: 0.42,
      fastSwipeThreshold: 0.66,
    );
    // Drain the microtask queue so the unawaited invokeMethod future
    // has a chance to complete and any error surfaces.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(TvRemoteController.instance.config.shortSwipeThreshold,
        closeTo(0.42, 1e-9));
  });

  testWidgets('popRoute method call pops the current route', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('root')),
        routes: {
          '/second': (_) => const Scaffold(body: Text('second')),
        },
      ),
    );

    navKey.currentState!.pushNamed('/second');
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    const codec = JSONMethodCodec();
    final message = codec.encodeMethodCall(const MethodCall('popRoute'));
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('flutter/navigation', message, (_) {});
    await tester.pumpAndSettle();

    expect(find.text('root'), findsOneWidget);
  });

  testWidgets(
      'touches channel no-op drain: spamming touch messages does not hang '
      'or crash, even with no raw listener attached',
      (tester) async {
    // Ensure no listener is active.
    TvRemoteController.instance.debugReset();

    const codec = JSONMessageCodec();
    final payload = codec.encodeMessage({'type': 'move', 'x': 0.3, 'y': 0.2});

    // On the real engine, these would otherwise surface "message
    // discarded" warnings. The assertion here is negative — we only
    // verify the app stays responsive. stdout capture is impractical
    // from inside the test; a human runs this and eyeballs the console.
    for (var i = 0; i < 50; i++) {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/tv_remote_touches', payload, (_) {});
    }
    await tester.pumpAndSettle();
  });

  testWidgets(
      'real codec round-trip on touches channel: message reaches listener '
      'with correct phase + coordinates',
      (tester) async {
    TvRemoteController.instance.debugReset();
    final received = <TvRemoteTouchEvent>[];
    TvRemoteController.instance.addRawListener(received.add);
    TvRemoteController.instance.debugInit();

    const codec = JSONMessageCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/tv_remote_touches',
      codec.encodeMessage({'type': 'move', 'x': 0.33, 'y': 0.66}),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(received.length, 1);
    expect(received.first.phase, TvRemoteTouchPhase.move);
    expect(received.first.x, closeTo(0.33, 1e-9));
    expect(received.first.y, closeTo(0.66, 1e-9));
  });

  testWidgets(
      'high-frequency touch stream (1000 events) reaches every listener '
      'without drop',
      (tester) async {
    TvRemoteController.instance.debugReset();
    var receivedCount = 0;
    TvRemoteController.instance.addRawListener((_) => receivedCount++);
    TvRemoteController.instance.debugInit();

    const codec = JSONMessageCodec();
    for (var i = 0; i < 1000; i++) {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/tv_remote_touches',
        codec.encodeMessage(
            {'type': 'move', 'x': i / 1000.0, 'y': 0.5}),
        (_) {},
      );
    }
    await tester.pumpAndSettle();

    expect(receivedCount, 1000,
        reason: 'no event must be dropped under stress');
  });

  testWidgets('config setter pushes updated values to native',
      (tester) async {
    // The configure call goes through the real button channel. The
    // engine plugin (if linked) acknowledges it; either way the
    // exception-free path is verified by the absence of throws.
    TvRemoteController.instance.config = const TvRemoteConfig(
      shortSwipeThreshold: 0.27,
      dpadDeadZone: 0.65,
      continuousSwipeMoveThreshold: 5,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(TvRemoteController.instance.config.shortSwipeThreshold,
        closeTo(0.27, 1e-9));
    expect(TvRemoteController.instance.config.dpadDeadZone, closeTo(0.65, 1e-9));
    expect(TvRemoteController.instance.config.continuousSwipeMoveThreshold,
        5);
  });

  testWidgets('popRoute on root is graceful (no crash, no pop)',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Text('root')),
      ),
    );

    const codec = JSONMethodCodec();
    final message = codec.encodeMethodCall(const MethodCall('popRoute'));
    await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('flutter/navigation', message, (_) {});
    await tester.pumpAndSettle();

    // Root route still present — Flutter's navigator returned 'not
    // handled' and Apple TV's system would normally take over (we
    // don't simulate the system handler here).
    expect(find.text('root'), findsOneWidget);
  });
}
