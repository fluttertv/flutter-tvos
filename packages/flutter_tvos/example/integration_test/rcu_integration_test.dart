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
// These tests are the cheapest layer that catches the class of bug
// Mehmet found — a method channel with no listener on the other side.
// Widget tests can't observe that; only a live engine sending real
// method calls exposes it.

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
}
