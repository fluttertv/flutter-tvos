// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// FFI bindings to the native flutter_tvos C functions.
///
/// On tvOS, the native code is statically linked into the app process
/// via CocoaPods, so we use [DynamicLibrary.process()] to look up symbols.
///
/// For testing, subclass this and override the getters. Use the
/// [TvOSNativeBindings.forTesting] named constructor to avoid FFI initialization.
class TvOSNativeBindings {
  /// Creates bindings that look up native symbols in the current process.
  ///
  /// This will throw if the native library is not loaded (e.g., in unit tests).
  /// For testing, use [TvOSInfo.bindingsOverride] with a fake subclass.
  TvOSNativeBindings() : _lib = DynamicLibrary.process();

  /// Constructor for fakes/mocks — skips FFI initialization.
  ///
  /// Subclass this and override the getters to provide test values.
  TvOSNativeBindings.forTesting() : _lib = null;

  final DynamicLibrary? _lib;

  // Lazy-loaded function pointers

  late final bool Function() _isTvOS = _lib!
      .lookupFunction<Bool Function(), bool Function()>('flutter_tvos_is_tvos');

  late final Pointer<Utf8> Function() _systemVersion = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_tvos_system_version');

  late final Pointer<Utf8> Function() _deviceModel = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_tvos_device_model');

  late final Pointer<Utf8> Function() _machineId = _lib!
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
          'flutter_tvos_machine_id');

  late final bool Function() _isSimulator = _lib!
      .lookupFunction<Bool Function(), bool Function()>(
          'flutter_tvos_is_simulator');

  late final bool Function() _supports4K = _lib!
      .lookupFunction<Bool Function(), bool Function()>(
          'flutter_tvos_supports_4k');

  late final bool Function() _supportsHDR = _lib!
      .lookupFunction<Bool Function(), bool Function()>(
          'flutter_tvos_supports_hdr');

  late final bool Function() _supportsMultiUser = _lib!
      .lookupFunction<Bool Function(), bool Function()>(
          'flutter_tvos_supports_multi_user');

  late final int Function() _displayWidth = _lib!
      .lookupFunction<Int32 Function(), int Function()>(
          'flutter_tvos_display_width');

  late final int Function() _displayHeight = _lib!
      .lookupFunction<Int32 Function(), int Function()>(
          'flutter_tvos_display_height');

  // Public API — override these in fakes for testing.

  bool get isTvOS => _isTvOS();
  String get systemVersion => _systemVersion().toDartString();
  String get deviceModel => _deviceModel().toDartString();
  String get machineId => _machineId().toDartString();
  bool get isSimulator => _isSimulator();
  bool get supports4K => _supports4K();
  bool get supportsHDR => _supportsHDR();
  bool get supportsMultiUser => _supportsMultiUser();
  int get displayWidth => _displayWidth();
  int get displayHeight => _displayHeight();
  String get displayResolution => '${displayWidth}x$displayHeight';
}
