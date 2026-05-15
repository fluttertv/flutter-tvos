// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'tvos_ffi_bindings.dart';
import 'tvos_info_platform.dart' as platform;

/// Fallback bindings for platforms where native tvOS symbols are not
/// linked (Web, Android, Linux, Windows).
class _UnsupportedPlatformBindings extends TvOSNativeBindings {
  _UnsupportedPlatformBindings() : super.forTesting();

  @override
  bool get isTvOS => false;
  @override
  String get systemVersion => '';
  @override
  String get deviceModel => '';
  @override
  String get machineId => '';
  @override
  bool get isSimulator => false;
  @override
  bool get supports4K => false;
  @override
  bool get supportsHDR => false;
  @override
  bool get supportsMultiUser => false;
  @override
  int get displayWidth => 0;
  @override
  int get displayHeight => 0;
}

/// Provides runtime information about the tvOS platform.
///
/// All properties are synchronous static getters powered by dart:ffi,
/// calling directly into native C functions with zero async overhead.
///
/// On non-Apple platforms (Android, Linux, Windows), all properties
/// return safe defaults ([isTvOS] returns `false`, strings return `''`,
/// etc.) without attempting FFI symbol lookups.
///
/// Example:
/// ```dart
/// if (TvOSInfo.isTvOS) {
///   print('tvOS version: ${TvOSInfo.tvOSVersion}');
///   print('Device model: ${TvOSInfo.deviceModel}');
///   print('Simulator: ${TvOSInfo.isSimulator}');
/// }
/// ```
class TvOSInfo {
  TvOSInfo._();

  static TvOSNativeBindings? _bindings;

  /// Override the native bindings for testing.
  @visibleForTesting
  static set bindingsOverride(TvOSNativeBindings? bindings) {
    _bindings = bindings;
  }

  static TvOSNativeBindings get _native {
    if (_bindings == null) {
      // Only attempt FFI symbol lookup on Apple platforms where the
      // native tvOS library is linked via CocoaPods.
      // platform.isApple returns false on Web at compile time via
      // conditional imports, so no dart:io usage reaches the Web compiler.
      if (platform.isApple) {
        _bindings = TvOSNativeBindings();
      } else {
        _bindings = _UnsupportedPlatformBindings();
      }
    }
    return _bindings!;
  }

  /// Whether the app is running on tvOS (compiled with TARGET_OS_TV).
  ///
  /// Returns `false` on iOS, macOS, or any non-tvOS platform.
  static bool get isTvOS => _native.isTvOS;

  /// The tvOS version string (e.g., "18.4").
  ///
  /// Returns an empty string if not available.
  static String get tvOSVersion => _native.systemVersion;

  /// The device model (e.g., "Apple TV").
  ///
  /// Returns an empty string if not available.
  static String get deviceModel => _native.deviceModel;

  /// The machine identifier (e.g., "AppleTV14,1").
  ///
  /// Returns an empty string if not available.
  static String get machineId => _native.machineId;

  /// Whether the app is running in the tvOS Simulator.
  static bool get isSimulator => _native.isSimulator;

  /// Whether the display supports 4K output (3840+ pixels wide).
  static bool get supports4K => _native.supports4K;

  /// Whether HDR (High Dynamic Range) is supported.
  static bool get supportsHDR => _native.supportsHDR;

  /// Whether multi-user is supported (tvOS 14+).
  static bool get supportsMultiUser => _native.supportsMultiUser;

  /// The native display width in pixels.
  static int get displayWidth => _native.displayWidth;

  /// The native display height in pixels.
  static int get displayHeight => _native.displayHeight;

  /// The display resolution as a string (e.g., "3840x2160").
  static String get displayResolution => _native.displayResolution;
}
