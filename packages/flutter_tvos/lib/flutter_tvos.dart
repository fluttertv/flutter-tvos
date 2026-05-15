/// Platform detection and utilities for Flutter apps on Apple TV (tvOS).
///
/// This package provides synchronous runtime checks via dart:ffi to determine
/// if the app is running on tvOS, along with device information and capability
/// queries. All calls are zero-overhead — no async, no platform channels.
///
/// ```dart
/// import 'package:flutter_tvos/flutter_tvos.dart';
///
/// if (TvOSInfo.isTvOS) {
///   print('Running on tvOS ${TvOSInfo.tvOSVersion}');
///   print('Device: ${TvOSInfo.deviceModel} (${TvOSInfo.machineId})');
///   print('Simulator: ${TvOSInfo.isSimulator}');
///   print('Resolution: ${TvOSInfo.displayResolution}');
/// }
/// ```
library flutter_tvos;

export 'src/tvos_info.dart';
export 'src/tvos_ffi_bindings.dart' show TvOSNativeBindings;
export 'src/platform_extension.dart'
    show FlutterTvosPlatform, FlutterTvosPlatformExt;
export 'src/rcu/tv_remote_controller.dart'
    show
        SwipeListener,
        TvRemoteConfig,
        TvRemoteController,
        TvRemoteTouchEvent,
        TvRemoteTouchListener,
        TvRemoteTouchPhase;
export 'src/rcu/swipe_detector.dart' show SwipeDirection, SwipeEvent;
