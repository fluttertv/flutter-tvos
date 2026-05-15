// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails, visibleForTesting;

import '../platform_extension.dart' show FlutterTvosPlatform;
import 'swipe_detector.dart';
import 'tv_remote_channels.dart';
import 'tv_remote_protocol.dart';

/// Runtime configuration for [TvRemoteController].
///
/// All tuning is shipped to the native plugin when [config] is assigned
/// (and once at [init]) via the `configure` method on the
/// [TvRemoteChannels.button] channel. Mutations take effect on the next
/// input event. Before [TvRemoteController.init] runs, `config` is stored
/// locally and pushed once during initialization. On iOS / Android `config`
/// is a no-op.
class TvRemoteConfig {
  const TvRemoteConfig({
    this.shortSwipeThreshold = 0.3,
    this.fastSwipeThreshold = 0.5,
    this.dpadDeadZone = 0.5,
    this.continuousSwipeMoveThreshold = 3,
    this.keyRepeatInitialDelay = const Duration(milliseconds: 400),
    this.keyRepeatInterval = const Duration(milliseconds: 80),
  })  : assert(shortSwipeThreshold > 0, 'shortSwipeThreshold must be positive'),
        assert(fastSwipeThreshold >= shortSwipeThreshold,
            'fastSwipeThreshold must be >= shortSwipeThreshold'),
        assert(dpadDeadZone > 0,
            'dpadDeadZone must be positive (use a value > 1.0 to disable bias)'),
        assert(continuousSwipeMoveThreshold >= 1,
            'continuousSwipeMoveThreshold must be at least 1');

  /// Accumulated delta that triggers a single arrow-key emit from a
  /// discrete swipe gesture (as seen by [TvRemoteController.addRawListener]).
  /// The native continuous-swipe detector uses its own threshold —
  /// see [continuousSwipeMoveThreshold].
  final double shortSwipeThreshold;

  /// Single-move delta above which the swipe is "fast". Consumers of
  /// [TvRemoteController.addRawListener] may use this to accelerate their
  /// own scrolling.
  final double fastSwipeThreshold;

  /// D-pad axis magnitude threshold used natively to bias a Siri Remote
  /// touchpad click toward an arrow key. Set to a value > 1.0 to disable
  /// the bias entirely.
  final double dpadDeadZone;

  /// Number of consecutive same-direction touchpad `move` events required
  /// natively before continuous-swipe auto-repeat engages.
  final int continuousSwipeMoveThreshold;

  /// Delay from the initial keydown to the first auto-repeated keydown
  /// on a held arrow/page button. Applied to the native `NSTimer`.
  final Duration keyRepeatInitialDelay;

  /// Interval between auto-repeated keydown events while the key is held.
  final Duration keyRepeatInterval;

  /// Serialize to the method-channel payload expected by the native
  /// plugin's `configure` method. Keys are the wire-format strings
  /// defined in [TvRemoteProtocol]; the native plugin reads exactly
  /// these names.
  Map<String, dynamic> toMap() => <String, dynamic>{
        TvRemoteProtocol.cfgShortSwipeThreshold: shortSwipeThreshold,
        TvRemoteProtocol.cfgFastSwipeThreshold: fastSwipeThreshold,
        TvRemoteProtocol.cfgDpadDeadZone: dpadDeadZone,
        TvRemoteProtocol.cfgContinuousSwipeMoveThreshold:
            continuousSwipeMoveThreshold,
        TvRemoteProtocol.cfgKeyRepeatInitialDelayMs:
            keyRepeatInitialDelay.inMilliseconds,
        TvRemoteProtocol.cfgKeyRepeatIntervalMs:
            keyRepeatInterval.inMilliseconds,
      };
}

/// A single raw touch event from the Siri Remote touchpad, exposed for
/// advanced consumers via [TvRemoteController.addRawListener].
class TvRemoteTouchEvent {
  const TvRemoteTouchEvent({
    required this.phase,
    required this.x,
    required this.y,
  });

  final TvRemoteTouchPhase phase;

  /// Normalized x in `[-1.0, 1.0]` (0 = view center, ±1 = edge).
  final double x;

  /// Normalized y in `[-1.0, 1.0]`.
  final double y;

  @override
  String toString() => 'TvRemoteTouchEvent($phase, ${x.toStringAsFixed(2)}, '
      '${y.toStringAsFixed(2)})';
}

/// Phase of a [TvRemoteTouchEvent]. Mirrors the native channel protocol.
enum TvRemoteTouchPhase {
  /// Finger placed on touchpad.
  started,

  /// Finger moving on touchpad.
  move,

  /// Finger lifted normally.
  ended,

  /// Gesture cancelled by the system.
  cancelled,

  /// D-pad position update from `GCMicroGamepad` (not an actual touch).
  loc,

  /// Physical click of the Siri Remote (touchpad pressed in).
  clickStart,

  /// Physical click released.
  clickEnd,
}

/// Signature for raw touch event listeners.
typedef TvRemoteTouchListener = void Function(TvRemoteTouchEvent event);

/// Signature for aggregated swipe-event listeners. Receives a
/// [SwipeEvent] each time accumulated touchpad motion crosses
/// `shortSwipeThreshold` from [TvRemoteConfig]. Independent from
/// [TvRemoteTouchListener] — both fire in parallel for the same gesture.
typedef SwipeListener = void Function(SwipeEvent event);

/// Dart-side companion to the native `FlutterTvRemotePlugin`.
///
/// The native plugin owns all keyboard-event generation: arrow/page
/// button presses, continuous-swipe auto-repeat, and the Select-click
/// directional bias are emitted directly to `flutter/keyevent`. This
/// controller only:
///
///   - ships tuning values ([TvRemoteConfig]) to native;
///   - fan-outs raw touchpad events to [addRawListener] consumers
///     (video scrubbers, custom swipe zones).
///
/// Initialize once at app startup with `TvRemoteController.instance.init()`
/// before registering listeners or relying on remote input. This keeps
/// initialization order explicit and easy to debug.
class TvRemoteController {
  TvRemoteController._();

  /// Process-wide singleton.
  static final TvRemoteController instance = TvRemoteController._();

  @visibleForTesting
  static bool debugForceTvosForTesting = false;

  TvRemoteConfig _config = const TvRemoteConfig();

  /// Current tuning. Assigning a new value ships it to the native plugin.
  TvRemoteConfig get config => _config;
  set config(TvRemoteConfig next) {
    _config = next;
    _cachedSwipe = null;
    if (_initialized) {
      _pushConfig();
    }
  }

  /// Swipe detector that drives [addSwipeListener] consumers and keeps
  /// the raw-listener-facing aggregation state in sync. Lazily rebuilt
  /// when thresholds change. Native runs its own detector for arrow-key
  /// auto-repeat — those are unrelated layers.
  SwipeDetector get _swipe {
    _cachedSwipe ??= SwipeDetector(
      shortThreshold: _config.shortSwipeThreshold,
      fastThreshold: _config.fastSwipeThreshold,
    );
    return _cachedSwipe!;
  }

  SwipeDetector? _cachedSwipe;
  final _rawListeners = <TvRemoteTouchListener>[];
  final _swipeListeners = <SwipeListener>[];
  bool _initialized = false;

  /// Wire up channel handlers. Idempotent — subsequent calls are no-ops.
  /// Does nothing if not running on tvOS.
  void init() {
    if (!FlutterTvosPlatform.isTvos && !debugForceTvosForTesting) {
      return;
    }
    _attachChannelHandlers();
  }

  /// Test-only variant that skips the tvOS platform check.
  @visibleForTesting
  void debugInit() => _attachChannelHandlers();

  /// Test-only reset — detaches handlers and clears accumulated state.
  @visibleForTesting
  void debugReset() {
    TvRemoteChannels.touches.setMessageHandler(null);
    _rawListeners.clear();
    _swipeListeners.clear();
    _cachedSwipe?.onEnd();
    _cachedSwipe = null;
    _config = const TvRemoteConfig();
    _initialized = false;
  }

  void _attachChannelHandlers() {
    if (_initialized) {
      return;
    }
    TvRemoteChannels.touches.setMessageHandler(_onTouchMessage);
    _initialized = true;
    _pushConfig();
  }

  void _pushConfig() {
    unawaited(TvRemoteChannels.button
        .invokeMethod<void>(TvRemoteProtocol.methodConfigure, _config.toMap())
        .catchError((Object error, StackTrace stack) {
      // Before native is reachable (e.g. iOS / Android / test binding
      // without a plugin), the invocation fails. Silently ignore — the
      // native side holds default values that match [TvRemoteConfig]
      // defaults, so apps that never touch `config` behave identically.
    }));
  }

  /// Register a listener that receives every raw touchpad event.
  void addRawListener(TvRemoteTouchListener listener) {
    _rawListeners.add(listener);
  }

  /// Remove a previously-added listener. No-op if [listener] wasn't added.
  void removeRawListener(TvRemoteTouchListener listener) {
    _rawListeners.remove(listener);
  }

  /// Register a listener that receives aggregated [SwipeEvent]s.
  ///
  /// Fires when the touchpad delta crosses
  /// [TvRemoteConfig.shortSwipeThreshold] in a dominant cardinal
  /// direction. Independent from [addRawListener] — both fire in
  /// parallel for the same gesture; raw listeners get every move,
  /// swipe listeners get aggregated direction + magnitude + isFast.
  ///
  /// Use this for high-level gesture handling (video scrub, custom
  /// swipe zones) where focus-navigation arrow keys aren't enough.
  void addSwipeListener(SwipeListener listener) {
    _swipeListeners.add(listener);
  }

  /// Remove a previously-added swipe listener. No-op if not registered.
  void removeSwipeListener(SwipeListener listener) {
    _swipeListeners.remove(listener);
  }

  Future<dynamic> _onTouchMessage(dynamic message) async {
    if (message is! Map) {
      return null;
    }
    final typeStr = message['type'];
    final x = (message['x'] as num?)?.toDouble() ?? 0.0;
    final y = (message['y'] as num?)?.toDouble() ?? 0.0;

    final phase = _phaseFromString(typeStr);
    if (phase == null) {
      return null;
    }

    if (_rawListeners.isNotEmpty) {
      final event = TvRemoteTouchEvent(phase: phase, x: x, y: y);
      // Iterate over a snapshot — a listener that calls addRawListener /
      // removeRawListener during delivery would otherwise throw
      // ConcurrentModificationError. Wrap each call in try/catch so one
      // bad listener cannot poison the rest.
      for (final listener in List.of(_rawListeners)) {
        try {
          listener(event);
        } catch (error, stack) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'flutter_tvos',
            context: ErrorDescription('while dispatching a raw touch event'),
          ));
        }
      }
    }

    // Drive the swipe detector. Native runs its own detector for arrow-
    // key auto-repeat; this one is for high-level [SwipeEvent] consumers
    // (video scrub, custom gesture zones).
    switch (phase) {
      case TvRemoteTouchPhase.started:
        _swipe.onStart(x, y);
        break;
      case TvRemoteTouchPhase.move:
        final swipe = _swipe.onMove(x, y);
        if (swipe != null) {
          _dispatchSwipe(swipe);
        }
        break;
      case TvRemoteTouchPhase.ended:
      case TvRemoteTouchPhase.cancelled:
        _swipe.onEnd();
        break;
      case TvRemoteTouchPhase.loc:
      case TvRemoteTouchPhase.clickStart:
      case TvRemoteTouchPhase.clickEnd:
        // Native handles keyboard emission for these phases.
        break;
    }
    return null;
  }

  void _dispatchSwipe(SwipeEvent event) {
    if (_swipeListeners.isEmpty) {
      return;
    }
    // Iterate over a snapshot — see _onTouchMessage for rationale.
    // Wrap each listener in try/catch so one bad subscriber cannot
    // poison the rest.
    for (final listener in List.of(_swipeListeners)) {
      try {
        listener(event);
      } catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_tvos',
          context: ErrorDescription('while dispatching a swipe event'),
        ));
      }
    }
  }
}

TvRemoteTouchPhase? _phaseFromString(dynamic type) {
  if (type is! String) return null;
  switch (type) {
    case TvRemoteProtocol.phaseStarted:
      return TvRemoteTouchPhase.started;
    case TvRemoteProtocol.phaseMove:
      return TvRemoteTouchPhase.move;
    case TvRemoteProtocol.phaseEnded:
      return TvRemoteTouchPhase.ended;
    case TvRemoteProtocol.phaseCancelled:
      return TvRemoteTouchPhase.cancelled;
    case TvRemoteProtocol.phaseLoc:
      return TvRemoteTouchPhase.loc;
    case TvRemoteProtocol.phaseClickStart:
      return TvRemoteTouchPhase.clickStart;
    case TvRemoteProtocol.phaseClickEnd:
      return TvRemoteTouchPhase.clickEnd;
  }
  return null;
}
