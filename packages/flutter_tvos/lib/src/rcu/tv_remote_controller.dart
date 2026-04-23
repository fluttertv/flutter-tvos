// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart'
    show ErrorDescription, FlutterError, FlutterErrorDetails, visibleForTesting;
import 'package:flutter/services.dart' show LogicalKeyboardKey, MethodCall;
import 'package:flutter/widgets.dart'
    show Widget, WidgetsFlutterBinding, runApp;

import '../platform_extension.dart' show FlutterTvosPlatform;
import 'key_simulator.dart';
import 'swipe_detector.dart';
import 'tv_remote_channels.dart';

/// Runtime configuration for [TvRemoteController].
///
/// Defaults match horizon `SwipeMixin` tuning adapted to the normalized
/// `[-1, 1]` coordinate space. A "short swipe" of 0.3 means the user moved
/// their finger across roughly 30% of the touchpad width.
///
/// Key-repeat timing (initial delay + interval) lives in the native plugin
/// and is not exposed here — physical button holds and continuous swipes
/// auto-repeat at engine-set rates (~400ms initial, ~80ms interval).
class TvRemoteConfig {
  const TvRemoteConfig({
    this.shortSwipeThreshold = 0.3,
    this.fastSwipeThreshold = 0.5,
    this.dpadDeadZone = 0.5,
  })  : assert(shortSwipeThreshold > 0,
            'shortSwipeThreshold must be positive'),
        assert(fastSwipeThreshold >= shortSwipeThreshold,
            'fastSwipeThreshold must be >= shortSwipeThreshold'),
        assert(dpadDeadZone > 0,
            'dpadDeadZone must be positive (use a value > 1.0 to disable bias)');

  /// Accumulated delta that triggers a single arrow-key emit from a
  /// discrete swipe gesture (as seen by [addRawListener]). Continuous-swipe
  /// auto-repeat is detected separately in native with a fixed threshold.
  final double shortSwipeThreshold;

  /// Single-move delta above which the swipe is "fast". Consumers of
  /// [addRawListener] may use this flag to accelerate their own scrolling.
  final double fastSwipeThreshold;

  /// D-pad axis magnitude threshold for directional-click bias. If the
  /// last D-pad `loc` X is off-center by at least this value when the
  /// touchpad is clicked, the click is converted to the matching arrow
  /// key instead of Select. Set to a value > 1.0 to disable the bias.
  final double dpadDeadZone;
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
  String toString() =>
      'TvRemoteTouchEvent($phase, ${x.toStringAsFixed(2)}, '
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

/// Receives remote-control events from the native tvOS embedder.
///
/// Most keyboard events come straight from the engine plugin: physical
/// arrow/page button presses (with native auto-repeat) and continuous-swipe
/// auto-repeat. This controller handles the two things that need app-level
/// policy:
///
///   - **Directional click bias.** When the user presses the touchpad with
///     a finger off-center, we convert Select into the matching arrow key,
///     controlled by [TvRemoteConfig.dpadDeadZone].
///   - **Raw touch listeners.** Advanced UIs (video scrubbing, custom
///     swipe zones) can subscribe via [addRawListener] and receive every
///     touchpad event.
///
/// Initialize at app start via [runTvApp] or by calling
/// [TvRemoteController.instance.init()].
class TvRemoteController {
  TvRemoteController._();

  /// Process-wide singleton.
  static final TvRemoteController instance = TvRemoteController._();

  /// Tuning for swipe thresholds and click bias. Mutations take effect on
  /// the next event — no need to re-initialize after changing [config].
  TvRemoteConfig config = const TvRemoteConfig();

  /// SwipeDetector is lazily constructed on first use and refreshed when
  /// thresholds in [config] change.
  SwipeDetector get _swipe {
    final threshold = config.shortSwipeThreshold;
    final fastThreshold = config.fastSwipeThreshold;
    if (_cachedSwipe == null ||
        _cachedSwipeThreshold != threshold ||
        _cachedFastThreshold != fastThreshold) {
      _cachedSwipe = SwipeDetector(
        shortThreshold: threshold,
        fastThreshold: fastThreshold,
      );
      _cachedSwipeThreshold = threshold;
      _cachedFastThreshold = fastThreshold;
    }
    return _cachedSwipe!;
  }

  SwipeDetector? _cachedSwipe;
  double? _cachedSwipeThreshold;
  double? _cachedFastThreshold;

  final _rawListeners = <TvRemoteTouchListener>[];

  /// Last D-pad X from `loc` events. Used to bias touchpad clicks toward
  /// an arrow direction when the user is holding the touchpad off-center.
  double _lastDpadX = 0;

  /// Key emitted on the most recent `clickStart`, so `clickEnd` can send
  /// the matching keyup.
  LogicalKeyboardKey? _lastClickKey;

  bool _initialized = false;

  /// Wire up channel handlers. Idempotent — subsequent calls are no-ops.
  /// Does nothing if not running on tvOS.
  void init() {
    if (!FlutterTvosPlatform.isTvos) return;
    _attachChannelHandlers();
  }

  /// Test-only variant that skips the tvOS platform check.
  @visibleForTesting
  void debugInit() => _attachChannelHandlers();

  /// Test-only reset — detaches handlers and clears accumulated state.
  @visibleForTesting
  void debugReset() {
    TvRemoteChannels.touches.setMessageHandler(null);
    TvRemoteChannels.button.setMethodCallHandler(null);
    _rawListeners.clear();
    _cachedSwipe?.onEnd();
    _lastDpadX = 0;
    _lastClickKey = null;
    _initialized = false;
  }

  void _attachChannelHandlers() {
    if (_initialized) return;
    TvRemoteChannels.touches.setMessageHandler(_onTouchMessage);
    TvRemoteChannels.button.setMethodCallHandler(_onButtonCall);
    _initialized = true;
  }

  /// Register a listener that receives every raw touchpad event.
  void addRawListener(TvRemoteTouchListener listener) {
    _rawListeners.add(listener);
  }

  /// Remove a previously-added listener. No-op if [listener] wasn't added.
  void removeRawListener(TvRemoteTouchListener listener) {
    _rawListeners.remove(listener);
  }

  Future<dynamic> _onTouchMessage(dynamic message) async {
    if (message is! Map) return null;
    final typeStr = message['type'];
    final x = (message['x'] as num?)?.toDouble() ?? 0.0;
    final y = (message['y'] as num?)?.toDouble() ?? 0.0;

    final phase = _phaseFromString(typeStr);
    if (phase == null) return null;

    if (_rawListeners.isNotEmpty) {
      final event = TvRemoteTouchEvent(phase: phase, x: x, y: y);
      // Iterate over a snapshot — a listener that calls addRawListener /
      // removeRawListener during delivery (e.g. a video scrubber that
      // self-removes when it finishes) would otherwise throw
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

    switch (phase) {
      case TvRemoteTouchPhase.started:
        _swipe.onStart(x, y);
        break;
      case TvRemoteTouchPhase.move:
        // SwipeDetector runs for the benefit of raw listeners / tests.
        // Keyboard events from continuous swipes are generated natively.
        _swipe.onMove(x, y);
        break;
      case TvRemoteTouchPhase.ended:
      case TvRemoteTouchPhase.cancelled:
        _swipe.onEnd();
        break;
      case TvRemoteTouchPhase.loc:
        _lastDpadX = x;
        break;
      case TvRemoteTouchPhase.clickStart:
        await _handleClickStart();
        break;
      case TvRemoteTouchPhase.clickEnd:
        await _handleClickEnd();
        break;
    }
    return null;
  }

  /// Apply directional-click bias: if D-pad is off-center, convert to
  /// arrow key; otherwise use Select. If a previous click is still open
  /// (no matching clickEnd arrived), emit its keyup first to keep
  /// `HardwareKeyboard.logicalKeysPressed` consistent.
  Future<void> _handleClickStart() async {
    final previous = _lastClickKey;
    if (previous != null) {
      await simulateKeyEvent(previous, isDown: false);
    }

    final LogicalKeyboardKey key;
    if (_lastDpadX.abs() >= config.dpadDeadZone) {
      key = _lastDpadX >= 0
          ? LogicalKeyboardKey.arrowRight
          : LogicalKeyboardKey.arrowLeft;
    } else {
      key = LogicalKeyboardKey.select;
    }
    _lastClickKey = key;
    await simulateKeyEvent(key, isDown: true);
  }

  Future<void> _handleClickEnd() async {
    final key = _lastClickKey;
    _lastClickKey = null;
    if (key != null) {
      await simulateKeyEvent(key, isDown: false);
    }
  }

  /// Method-channel handler for discrete (non-repeating) button presses
  /// and media commands that native forwards to Dart.
  ///
  /// Arrow keys and page keys are **not** delivered here — native routes
  /// them directly to `flutter/keyevent` via the engine's own key event
  /// channel, with auto-repeat. Only Menu, Play/Pause, and media commands
  /// arrive on this channel.
  Future<dynamic> _onButtonCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return null;

    switch (call.method) {
      case 'press':
        final keyName = args['key'] as String?;
        final isDown = args['isDown'] as bool? ?? false;
        if (keyName == null) return null;
        final key = _logicalKeyFromName(keyName);
        if (key == null) return null;
        await simulateKeyEvent(key, isDown: isDown);
        return null;

      case 'media':
        final command = args['command'] as String?;
        final isDown = args['isDown'] as bool? ?? false;
        if (command == null) return null;
        final key = _logicalKeyForMediaCommand(command);
        if (key == null) return null;
        await simulateKeyEvent(key, isDown: isDown);
        return null;
    }
    return null;
  }
}

/// Entry point equivalent to [runApp] with RCU initialization on tvOS.
/// On iOS / Android / other platforms this is a straight passthrough.
///
/// ```dart
/// void main() => runTvApp(const MyApp());
/// ```
///
/// **Custom `WidgetsBinding` subclasses.** `runTvApp` force-installs the
/// concrete `WidgetsFlutterBinding`. If your app uses a custom binding
/// subclass (e.g. for analytics observers), initialize it first and then
/// wire up RCU manually:
///
/// ```dart
/// void main() {
///   MyCustomBinding.ensureInitialized();
///   if (FlutterTvosPlatform.isTvos) {
///     TvRemoteController.instance.init();
///   }
///   runApp(const MyApp());
/// }
/// ```
///
/// **Hot restart.** On hot restart the Dart VM re-initializes static
/// state: `TvRemoteController.instance._initialized` resets to `false`
/// and its channel handlers disappear. `runTvApp` is not re-invoked —
/// only cold restart re-registers the RCU listeners. If the Remote
/// appears dead after a hot restart, do a cold restart.
void runTvApp(Widget app) {
  WidgetsFlutterBinding.ensureInitialized();
  if (FlutterTvosPlatform.isTvos) {
    TvRemoteController.instance.init();
  }
  runApp(app);
}

TvRemoteTouchPhase? _phaseFromString(dynamic type) {
  if (type is! String) return null;
  switch (type) {
    case 'started':
      return TvRemoteTouchPhase.started;
    case 'move':
      return TvRemoteTouchPhase.move;
    case 'ended':
      return TvRemoteTouchPhase.ended;
    case 'cancelled':
      return TvRemoteTouchPhase.cancelled;
    case 'loc':
      return TvRemoteTouchPhase.loc;
    case 'click_s':
      return TvRemoteTouchPhase.clickStart;
    case 'click_e':
      return TvRemoteTouchPhase.clickEnd;
  }
  return null;
}

LogicalKeyboardKey? _logicalKeyFromName(String name) {
  switch (name) {
    case 'select':
      return LogicalKeyboardKey.select;
    case 'menu':
      return LogicalKeyboardKey.escape;
    case 'playPause':
      return LogicalKeyboardKey.mediaPlayPause;
  }
  return null;
}

LogicalKeyboardKey? _logicalKeyForMediaCommand(String command) {
  switch (command) {
    case 'play':
      return LogicalKeyboardKey.mediaPlay;
    case 'pause':
      return LogicalKeyboardKey.mediaPause;
    case 'stop':
      return LogicalKeyboardKey.mediaStop;
    case 'togglePlayPause':
      return LogicalKeyboardKey.mediaPlayPause;
    case 'seekForward':
    case 'fastForward':
      return LogicalKeyboardKey.mediaFastForward;
    case 'seekBackward':
    case 'rewind':
      return LogicalKeyboardKey.mediaRewind;
  }
  return null;
}
