// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Web stub — dart:ffi is not available on Web. All getters return safe
// defaults that match the non-tvOS fallback in the native implementation.

/// FFI bindings stub for Web. No native symbols are available.
class TvOSNativeBindings {
  TvOSNativeBindings();
  TvOSNativeBindings.forTesting();

  bool get isTvOS => false;
  String get systemVersion => '';
  String get deviceModel => '';
  String get machineId => '';
  bool get isSimulator => false;
  bool get supports4K => false;
  bool get supportsHDR => false;
  bool get supportsMultiUser => false;
  int get displayWidth => 0;
  int get displayHeight => 0;
  String get displayResolution => '0x0';
}
