// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'tvos_ffi_bindings.dart';

/// Provides runtime information about the tvOS platform.
///
/// All properties are synchronous static getters powered by dart:ffi,
/// calling directly into native C functions with zero async overhead.
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
    _bindings ??= TvOSNativeBindings();
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
