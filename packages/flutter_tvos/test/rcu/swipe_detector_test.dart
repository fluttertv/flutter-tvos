// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tvos/src/rcu/swipe_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SwipeDetector', () {
    test('returns null before the short threshold is crossed', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      expect(detector.onMove(0.1, 0), isNull);
      expect(detector.onMove(0.2, 0), isNull);
    });

    test('emits Right when +X delta crosses threshold', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      final event = detector.onMove(0.35, 0);
      expect(event, isNotNull);
      expect(event!.direction, SwipeDirection.right);
      expect(event.isFast, isFalse);
    });

    test('emits Left when -X delta crosses threshold', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      final event = detector.onMove(-0.4, 0);
      expect(event!.direction, SwipeDirection.left);
    });

    test('emits Down/Up on Y delta when bigger than X delta', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      final down = detector.onMove(0.1, 0.35);
      expect(down!.direction, SwipeDirection.down);

      detector.onStart(0, 0);
      final up = detector.onMove(0.1, -0.4);
      expect(up!.direction, SwipeDirection.up);
    });

    test('flags fast swipes when delta crosses fastThreshold', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      final event = detector.onMove(0.6, 0);
      expect(event!.isFast, isTrue);
    });

    test('resets segment start after each emit (cumulative motion)', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      // First swipe
      final first = detector.onMove(0.35, 0);
      expect(first!.direction, SwipeDirection.right);
      // Another 0.35 from the new segment start should fire again
      final second = detector.onMove(0.7, 0);
      expect(second, isNotNull);
      expect(second!.direction, SwipeDirection.right);
    });

    test('onEnd clears active state', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      expect(detector.isActive, isTrue);
      detector.onEnd();
      expect(detector.isActive, isFalse);
      // Move after end does not emit.
      expect(detector.onMove(0.5, 0), isNull);
    });

    test('ignores moves before onStart', () {
      final detector = SwipeDetector();
      expect(detector.onMove(0.5, 0), isNull);
    });

    test('reverses direction mid-touch emits two different arrows', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      final right = detector.onMove(0.4, 0);
      expect(right!.direction, SwipeDirection.right);
      // After the first emit, segment start resets to (0.4, 0). Moving
      // to (0.0, -0.4) produces dx=-0.4, dy=-0.4. |dx| == |dy|, so the
      // `absDx >= absDy` branch wins (horizontal), and dx < 0 → Left.
      final next = detector.onMove(0.0, -0.4);
      expect(next, isNotNull);
      expect(next!.direction, SwipeDirection.left);
    });

    test('zigzag: each segment picks its own axis', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      final first = detector.onMove(0.35, 0);
      expect(first!.direction, SwipeDirection.right);
      // From (0.35, 0) move to (0.3, -0.35): dx=-0.05, dy=-0.35 → Up
      final second = detector.onMove(0.3, -0.35);
      expect(second!.direction, SwipeDirection.up);
    });

    test('barely crosses threshold fires at exactly threshold', () {
      final detector = SwipeDetector(shortThreshold: 0.3);
      detector.onStart(0, 0);
      // Just above threshold.
      final event = detector.onMove(0.3001, 0);
      expect(event, isNotNull);
      expect(event!.direction, SwipeDirection.right);
    });

    test('starts from corner with small motion stays below threshold', () {
      final detector = SwipeDetector();
      detector.onStart(-1, -1);
      // Small motion 0.1 in X → below threshold.
      expect(detector.onMove(-0.9, -1), isNull);
    });

    test('zero-distance move never emits', () {
      final detector = SwipeDetector();
      detector.onStart(0.5, 0.5);
      expect(detector.onMove(0.5, 0.5), isNull);
    });

    test('cumulative with axis change — each axis accumulates separately', () {
      final detector = SwipeDetector();
      detector.onStart(0, 0);
      final right = detector.onMove(0.4, 0);
      expect(right!.direction, SwipeDirection.right);
      // After reset, segment starts at (0.4, 0). Moving to (0.5, -0.35):
      // dx=0.1, dy=-0.35 → Up dominant.
      final up = detector.onMove(0.5, -0.35);
      expect(up!.direction, SwipeDirection.up);
    });

    test('slow swipe (small delta, exact threshold) is not fast', () {
      final detector = SwipeDetector(shortThreshold: 0.3, fastThreshold: 0.5);
      detector.onStart(0, 0);
      final event = detector.onMove(0.3, 0);
      expect(event!.isFast, isFalse);
    });
  });
}
