// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart' show LogicalKeyboardKey;

/// Direction derived from a swipe gesture on the Siri Remote touchpad.
enum SwipeDirection {
  left(LogicalKeyboardKey.arrowLeft),
  right(LogicalKeyboardKey.arrowRight),
  up(LogicalKeyboardKey.arrowUp),
  down(LogicalKeyboardKey.arrowDown);

  const SwipeDirection(this.arrowKey);

  /// The arrow key that represents moving focus in this direction.
  final LogicalKeyboardKey arrowKey;
}

/// Detects swipe gestures from the sequence of normalized touchpad points
/// emitted by the native plugin.
///
/// Algorithm (adapted from horizon `SwipeMixin`):
/// - Track the starting point of the current "swipe segment".
/// - On each `move`, compute the delta from the segment start.
/// - If the larger delta axis exceeds [shortThreshold], emit a swipe in
///   that direction, and reset the segment start to the current point.
/// - If a single delta exceeds [fastThreshold], the swipe is marked as
///   "fast" — useful for accelerated navigation.
///
/// Coordinates are in `[-1.0, 1.0]` normalized view space, so thresholds
/// are also in that space (typical `shortThreshold ~ 0.3`).
class SwipeDetector {
  SwipeDetector({
    this.shortThreshold = 0.3,
    this.fastThreshold = 0.5,
  });

  /// Delta magnitude at which a single direction change emits a swipe.
  final double shortThreshold;

  /// Delta magnitude above which the swipe is considered "fast".
  final double fastThreshold;

  double _segmentStartX = 0;
  double _segmentStartY = 0;
  bool _isActive = false;

  /// True while a touch is in progress (between `started` and `ended`).
  bool get isActive => _isActive;

  /// Called when the user places a finger on the touchpad.
  void onStart(double x, double y) {
    _segmentStartX = x;
    _segmentStartY = y;
    _isActive = true;
  }

  /// Called on each touchpad move. Returns a [SwipeEvent] if the
  /// accumulated motion crossed [shortThreshold], otherwise `null`.
  SwipeEvent? onMove(double x, double y) {
    if (!_isActive) return null;

    final dx = x - _segmentStartX;
    final dy = y - _segmentStartY;
    final absDx = dx.abs();
    final absDy = dy.abs();

    if (absDx < shortThreshold && absDy < shortThreshold) return null;

    final SwipeDirection direction;
    final double magnitude;
    if (absDx >= absDy) {
      direction = dx >= 0 ? SwipeDirection.right : SwipeDirection.left;
      magnitude = absDx;
    } else {
      direction = dy >= 0 ? SwipeDirection.down : SwipeDirection.up;
      magnitude = absDy;
    }

    // Reset the segment start so further motion measures from here.
    _segmentStartX = x;
    _segmentStartY = y;

    return SwipeEvent(
      direction: direction,
      magnitude: magnitude,
      isFast: magnitude >= fastThreshold,
    );
  }

  /// Called when the touch ends (lift, cancel). Resets internal state.
  void onEnd() {
    _isActive = false;
    _segmentStartX = 0;
    _segmentStartY = 0;
  }
}

/// A single swipe emitted by [SwipeDetector].
class SwipeEvent {
  const SwipeEvent({
    required this.direction,
    required this.magnitude,
    required this.isFast,
  });

  final SwipeDirection direction;

  /// Magnitude of the motion that triggered this event, in the same
  /// normalized `[-1, 1]` coordinate space as the input.
  final double magnitude;

  /// `true` if the magnitude crossed `fastThreshold` — caller may want
  /// to accelerate scrolling or emit multiple events.
  final bool isFast;

  @override
  String toString() =>
      'SwipeEvent($direction, magnitude=${magnitude.toStringAsFixed(2)}, '
      'fast=$isFast)';
}
