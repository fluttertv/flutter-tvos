// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Widget-level tests for the Mehmet-review RCU behaviors. These simulate
// the framework-facing surface that the native FlutterTvRemotePlugin
// produces on a real device:
//
//   - Select press → `flutter/keyevent` (macOS keymap, `kVK_Return`)
//     → `LogicalKeyboardKey.enter` → default `ActivateIntent` shortcut.
//   - Menu press → `flutter/navigation popRoute` method call.
//   - Play/Pause press → `flutter/keyevent` (android keymap, 85)
//     → `LogicalKeyboardKey.mediaPlayPause`.
//
// The native→Dart codec step is not re-implemented here — Flutter's
// built-in key simulation helpers inject events at the right layer
// (`platform: 'macos'` / `'android'`), mirroring what the decoded
// message would produce. This covers the framework pipeline
// (shortcut → intent → action) that Mehmet's manual testing exercised
// when M1 was found broken.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RCU framework wiring', () {
    testWidgets(
      'M1: Select (macOS keymap 0x24 → enter) activates focused button '
      'with no custom shortcuts',
      (tester) async {
        var pressed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  autofocus: true,
                  onPressed: () => pressed = true,
                  child: const Text('Target'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'macos');
        await tester.pumpAndSettle();

        expect(pressed, isTrue,
            reason: 'Default ActivateIntent should fire on enter. This is '
                'the whole point of M1 — stock tvOS apps work out of the box.');
      },
    );

    testWidgets(
      'M4: Play/Pause (android keymap 85) surfaces as '
      'LogicalKeyboardKey.mediaPlayPause on HardwareKeyboard',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

        var sawMediaPlayPause = false;
        void handler(KeyEvent event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
            sawMediaPlayPause = true;
          }
        }

        HardwareKeyboard.instance.addHandler((event) {
          handler(event);
          return false;
        });

        await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause,
            platform: 'android');
        await tester.pumpAndSettle();

        expect(sawMediaPlayPause, isTrue);
      },
    );

    testWidgets(
      'Regression: arrow keys (macOS keymap 0x7B/7C/7D/7E) move focus '
      'through a Row of focusable tiles',
      (tester) async {
        final focusNodes = List.generate(3, (_) => FocusNode());
        addTearDown(() {
          for (final n in focusNodes) {
            n.dispose();
          }
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FocusTraversalGroup(
                policy: WidgetOrderTraversalPolicy(),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Focus(
                        focusNode: focusNodes[i],
                        autofocus: i == 0,
                        child: SizedBox(
                          width: 100,
                          height: 100,
                          child: Container(
                              color: focusNodes[i].hasFocus
                                  ? Colors.blue
                                  : Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(focusNodes[0].hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
            platform: 'macos');
        await tester.pumpAndSettle();
        expect(focusNodes[1].hasFocus, isTrue,
            reason: 'arrowRight should move focus forward in traversal order');

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft,
            platform: 'macos');
        await tester.pumpAndSettle();
        expect(focusNodes[0].hasFocus, isTrue,
            reason: 'arrowLeft should move focus back');
      },
    );
  });

  group('M2: Menu → navigation.popRoute', () {
    // The native plugin responds to UIPressTypeMenu by invoking
    // `popRoute` on `flutter/navigation`. The Flutter framework hooks
    // this up to `Navigator.maybePop` via WidgetsBinding's own handler.
    // This test drives the same method call through the binding so the
    // framework pipeline is exercised end-to-end.

    testWidgets('popRoute pops the top route', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: Text('screen-1')),
          routes: {
            '/second': (_) => const Scaffold(body: Text('screen-2')),
          },
        ),
      );

      navKey.currentState!.pushNamed('/second');
      await tester.pumpAndSettle();
      expect(find.text('screen-2'), findsOneWidget);

      // Drive the exact method call the engine emits for Menu presses.
      const codec = JSONMethodCodec();
      final message = codec.encodeMethodCall(
        const MethodCall('popRoute'),
      );
      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage('flutter/navigation', message, (_) {});
      await tester.pumpAndSettle();

      expect(find.text('screen-1'), findsOneWidget,
          reason: 'popRoute should unwind back to the initial route — '
              'this is the entire user-facing behavior Mehmet asked for.');
    });

    testWidgets('popRoute on root route is a no-op (does not crash)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('root'))),
      );

      const codec = JSONMethodCodec();
      final message = codec.encodeMethodCall(
        const MethodCall('popRoute'),
      );
      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage('flutter/navigation', message, (_) {});
      await tester.pumpAndSettle();

      // Root route stays — on a real device, UIKit/Apple TV takes over
      // from here and sends the user Home, which we can't override.
      expect(find.text('root'), findsOneWidget);
    });
  });

  group('Media key surface', () {
    // Native plugin emits all media keys via the android keymap (Flutter's
    // macOS table has no media entries). Verify each one reaches
    // HardwareKeyboard so apps reacting to LogicalKeyboardKey.mediaXxx
    // light up out of the box.
    Future<void> expectMediaKey(WidgetTester tester,
        LogicalKeyboardKey key) async {
      var saw = false;
      bool handler(KeyEvent event) {
        if (event is KeyDownEvent && event.logicalKey == key) {
          saw = true;
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(handler);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

      await tester.sendKeyEvent(key, platform: 'android');
      await tester.pumpAndSettle();
      expect(saw, isTrue, reason: '$key should surface on HardwareKeyboard');
    }

    testWidgets('mediaPlay surfaces on HardwareKeyboard', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await expectMediaKey(tester, LogicalKeyboardKey.mediaPlay);
    });

    testWidgets('mediaPause surfaces on HardwareKeyboard', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await expectMediaKey(tester, LogicalKeyboardKey.mediaPause);
    });

    testWidgets('mediaStop surfaces on HardwareKeyboard', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await expectMediaKey(tester, LogicalKeyboardKey.mediaStop);
    });

    testWidgets('mediaFastForward surfaces on HardwareKeyboard',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await expectMediaKey(tester, LogicalKeyboardKey.mediaFastForward);
    });

    testWidgets('mediaRewind surfaces on HardwareKeyboard', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await expectMediaKey(tester, LogicalKeyboardKey.mediaRewind);
    });
  });

  group('Page navigation regression', () {
    testWidgets(
        'pageUp/pageDown surface as LogicalKeyboardKey on HardwareKeyboard',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      var sawPageUp = false;
      var sawPageDown = false;
      bool handler(KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.pageUp) sawPageUp = true;
          if (event.logicalKey == LogicalKeyboardKey.pageDown) {
            sawPageDown = true;
          }
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(handler);
      addTearDown(() => HardwareKeyboard.instance.removeHandler(handler));

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp, platform: 'macos');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown,
          platform: 'macos');
      await tester.pumpAndSettle();

      expect(sawPageUp, isTrue);
      expect(sawPageDown, isTrue);
    });
  });

  group('Select activates focused button across multiple targets', () {
    testWidgets(
        'enter activates focused ElevatedButton even with multiple buttons',
        (tester) async {
      var pressedFirst = 0;
      var pressedSecond = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    autofocus: true,
                    onPressed: () => pressedFirst++,
                    child: const Text('First'),
                  ),
                  ElevatedButton(
                    onPressed: () => pressedSecond++,
                    child: const Text('Second'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter, platform: 'macos');
      await tester.pumpAndSettle();

      expect(pressedFirst, 1, reason: 'autofocused First should activate');
      expect(pressedSecond, 0,
          reason: 'unfocused Second must not activate');
    });
  });
}
